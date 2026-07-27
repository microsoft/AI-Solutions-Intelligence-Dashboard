<#
.SYNOPSIS
    Collects the Section-A A2 artifact ai_copilot_usage_graph.csv for the AI
    Solutions dashboard. This is a live Microsoft Purview Audit pull of
    CopilotInteraction events, pivoted per user x month by workload.

.DESCRIPTION
    The AI Solutions dashboard (pbit) imports twelve CSVs. This collector
    delivers the last remaining Section-A artifact, A2:

        A2 -- ai_copilot_usage_graph.csv (Power Query table AI_CopilotUsage):
            A Purview Audit search (Search-UnifiedAuditLog) for
            'CopilotInteraction' events over a date window, whose AuditData is
            parsed and pivoted into one row per UserPrincipalName x YearMonth
            with per-surface prompt counts (Teams/Word/Excel/Outlook/PowerPoint/
            Chat), a Total, an ActiveDays distinct-date count, and a
            LastActivityDate.

    Why a SEPARATE script (not the Graph collector): the authoritative source
    for A2 is Microsoft Purview Audit, whose real path requires the
    ExchangeOnlineManagement module plus Connect-ExchangeOnline and the
    Search-UnifiedAuditLog cmdlet. The Section-A Graph collector deliberately
    avoids any SDK/module dependency (raw REST only), so A2 lives here on its
    own. The Graph Reports API alternative only returns per-app last-activity
    DATES (not per-surface prompt counts) and therefore cannot truthfully
    populate this count schema -- hence Purview.

    This collector mirrors the Graph collector's proven pattern: StrictMode
    Latest, $ErrorActionPreference='Stop', StrictMode-safe optional property
    reads (Get-PropValue), a byte-exact header written even on zero rows,
    Export-Csv -UseQuotes AsNeeded (PS7) so simple values (UPNs, yyyy-MM) stay
    bare and the header line is byte-exact, and it returns a summary
    PSCustomObject (it NEVER calls exit).

    NO secret, token, tenant id, or UPN is ever hardcoded or logged.

    The -SearchExecutor scriptblock is the CREDENTIAL-FREE test seam: when
    supplied it is invoked INSTEAD of Search-UnifiedAuditLog, receiving a
    per-page context object and returning a batch of audit records. This lets
    the pagination and parsing logic be tested with no Exchange Online
    connection.

.PARAMETER OutputDirectory
    Directory that receives ai_copilot_usage_graph.csv. Created if missing.

.PARAMETER StartDate
    Lower bound of the audit search window. When unbound, defaults to
    (Get-Date).AddDays(-180).

.PARAMETER EndDate
    Upper bound of the audit search window. When unbound, defaults to
    (Get-Date).

.PARAMETER PageSize
    Search-UnifiedAuditLog ResultSize / page size for the ReturnLargeSet
    session. Defaults to 5000.

.PARAMETER SearchExecutor
    INJECTION SEAM FOR TESTING. A scriptblock that receives a single argument: a
    PSCustomObject context with StartDate, EndDate, SessionId, SessionCommand,
    ResultSize, and a zero-based Page property. It must return the batch of
    audit records for that page (each record exposing an AuditData JSON string).
    When supplied, this is used INSTEAD of Search-UnifiedAuditLog, enabling
    credential-free testing.

.EXAMPLE
    # Live Purview pull (requires ExchangeOnlineManagement + Connect-ExchangeOnline).
    Connect-ExchangeOnline
    .\Collect-AICopilotUsage.ps1 -OutputDirectory .\dashboard_data

.EXAMPLE
    # Credential-free test using an injected mock search executor.
    $mock = { param($ctx) if ($ctx.Page -eq 0) { ,@([pscustomobject]@{ AuditData = '{"UserId":"a@x","CreationDate":"2026-05-04T10:00:00Z","Workload":"Word","CopilotEventData":{"Prompts":[1,2,3]}}' }) } else { @() } }
    .\Collect-AICopilotUsage.ps1 -SearchExecutor $mock -OutputDirectory $tempDir

.NOTES
    Requires PowerShell 7+. For real (non-mock) execution the identity used must
    have Exchange Online audit access (Search-UnifiedAuditLog) via an active
    Connect-ExchangeOnline session with the ExchangeOnlineManagement module.
    Returns a summary PSCustomObject (does NOT call exit). Uses -UseQuotes
    AsNeeded so the CSV header stays byte-exact. The -SearchExecutor seam keeps
    this collector credential-free testable. Source/pivot logic mirrors
    kql_queries_v22_E5V3.kql section A2 and the Graph collector's helper style.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [datetime]$StartDate,

    [datetime]$EndDate,

    [int]$PageSize = 5000,

    [scriptblock]$SearchExecutor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Constant: byte-exact 11-column header (do not rename / reorder).
# ----------------------------------------------------------------------------
$usageHeader = 'UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate'

# ----------------------------------------------------------------------------
# Helpers (StrictMode-safe; copied verbatim from the Graph collector's style).
# ----------------------------------------------------------------------------

function Write-Progress-Log {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
}

function Get-PropValue {
    <#
        StrictMode-safe optional property read. Returns $null when the property
        is absent, otherwise its value.
    #>
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function ConvertTo-CsvField {
    # Coerce a possibly-null value to a plain string ('' for null).
    param($Value)
    if ($null -eq $Value) { return '' }
    return [string]$Value
}

# ----------------------------------------------------------------------------
# Resolve default date window at use-site (only when unbound).
# ----------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey('StartDate')) {
    $StartDate = (Get-Date).AddDays(-180)
}
if (-not $PSBoundParameters.ContainsKey('EndDate')) {
    $EndDate = (Get-Date)
}

# ----------------------------------------------------------------------------
# Resolve output directory.
# ----------------------------------------------------------------------------
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$usagePath = Join-Path $OutputDirectory 'ai_copilot_usage_graph.csv'

# ----------------------------------------------------------------------------
# Auth / seam resolution. The mock seam bypasses Exchange Online entirely; the
# real path requires the Search-UnifiedAuditLog cmdlet (ExchangeOnlineManagement
# + Connect-ExchangeOnline). No secret is ever referenced or logged.
# ----------------------------------------------------------------------------
$useMock = $null -ne $SearchExecutor
if (-not $useMock) {
    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        throw "Search-UnifiedAuditLog not available. Import ExchangeOnlineManagement and Connect-ExchangeOnline, or supply -SearchExecutor for testing."
    }
}

# ----------------------------------------------------------------------------
# Paginated Purview audit search. The mock and real path BOTH return a batch of
# audit records for the requested page; the loop terminates when a page returns
# fewer than PageSize records (or none).
# ----------------------------------------------------------------------------
$sessionId = [guid]::NewGuid().ToString()
$page = 0
$all  = [System.Collections.Generic.List[object]]::new()
do {
    $ctx = [pscustomobject]@{
        StartDate      = $StartDate
        EndDate        = $EndDate
        SessionId      = $sessionId
        SessionCommand = 'ReturnLargeSet'
        ResultSize     = $PageSize
        Page           = $page
    }
    if ($useMock) {
        $batch = & $SearchExecutor $ctx
    }
    else {
        $batch = Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate `
                   -Operations 'CopilotInteraction' -ResultSize $PageSize `
                   -SessionId $sessionId -SessionCommand ReturnLargeSet
    }
    $count = 0
    if ($null -ne $batch) {
        foreach ($r in @($batch)) { [void]$all.Add($r); $count++ }
    }
    $page++
} while ($count -eq $PageSize -and $count -gt 0)

Write-Progress-Log ("  A2 CopilotInteraction events retrieved: {0}" -f $all.Count) ([ConsoleColor]::Cyan)

# ----------------------------------------------------------------------------
# Parse each audit record (StrictMode-safe) into an intermediate usage row.
# ----------------------------------------------------------------------------
$parsed = [System.Collections.Generic.List[object]]::new()
foreach ($rec in $all) {
    $audit = Get-PropValue $rec 'AuditData'
    if ($null -eq $audit) { continue }
    $data = $audit | ConvertFrom-Json

    $userId = Get-PropValue $data 'UserId'
    if ($null -eq $userId -or [string]$userId -eq '') { continue }
    $upn = ([string]$userId).ToLower()

    $creationRaw = Get-PropValue $data 'CreationDate'
    if ($null -eq $creationRaw -or [string]$creationRaw -eq '') { continue }
    $creation = [datetime]::Parse([string]$creationRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    $yearMonth = $creation.ToString('yyyy-MM')
    $date = $creation.ToString('yyyy-MM-dd')

    $rawWorkload = Get-PropValue $data 'Workload'
    $workload = switch ([string]$rawWorkload) {
        'MicrosoftTeams' { 'Teams' }
        'Word'           { 'Word' }
        'Excel'          { 'Excel' }
        'Outlook'        { 'Outlook' }
        'PowerPoint'     { 'PowerPoint' }
        'Bing'           { 'Chat' }
        'M365Chat'       { 'Chat' }
        'Microsoft365'   { 'Chat' }
        default          { [string]$rawWorkload }
    }

    $ced = Get-PropValue $data 'CopilotEventData'
    $p = Get-PropValue $ced 'Prompts'
    $prompts = if ($p) { @($p).Count } else { 1 }

    $parsed.Add([pscustomobject]@{
        UPN       = $upn
        YearMonth = $yearMonth
        Date      = $date
        Workload  = $workload
        Prompts   = $prompts
    })
}

# ----------------------------------------------------------------------------
# Pivot: one row per UPN x YearMonth with per-surface prompt sums. Unknown /
# passthrough workloads are excluded from every surface sum AND from Total
# (matches the reference A2 pivot).
# ----------------------------------------------------------------------------
$usageRows = [System.Collections.Generic.List[object]]::new()
$groups = $parsed | Group-Object -Property UPN, YearMonth
foreach ($g in $groups) {
    $first = $g.Group[0]

    $teams = ($g.Group | Where-Object { $_.Workload -eq 'Teams' }      | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $word  = ($g.Group | Where-Object { $_.Workload -eq 'Word' }       | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $excel = ($g.Group | Where-Object { $_.Workload -eq 'Excel' }      | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $outl  = ($g.Group | Where-Object { $_.Workload -eq 'Outlook' }    | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $ppt   = ($g.Group | Where-Object { $_.Workload -eq 'PowerPoint' } | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $chat  = ($g.Group | Where-Object { $_.Workload -eq 'Chat' }       | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum

    if ($null -eq $teams) { $teams = 0 }
    if ($null -eq $word)  { $word  = 0 }
    if ($null -eq $excel) { $excel = 0 }
    if ($null -eq $outl)  { $outl  = 0 }
    if ($null -eq $ppt)   { $ppt   = 0 }
    if ($null -eq $chat)  { $chat  = 0 }

    $activeDays = @($g.Group | ForEach-Object { $_.Date } | Select-Object -Unique).Count
    $lastActivity = ($g.Group | ForEach-Object { $_.Date } | Measure-Object -Maximum).Maximum
    $total = [int]$teams + [int]$word + [int]$excel + [int]$outl + [int]$ppt + [int]$chat

    $usageRows.Add([pscustomobject]@{
        UserPrincipalName = $first.UPN
        YearMonth         = $first.YearMonth
        TeamsPrompts      = [int]$teams
        WordPrompts       = [int]$word
        ExcelPrompts      = [int]$excel
        OutlookPrompts    = [int]$outl
        PowerPointPrompts = [int]$ppt
        ChatPrompts       = [int]$chat
        TotalPrompts      = [int]$total
        ActiveDays        = [int]$activeDays
        LastActivityDate  = $lastActivity
    })
}

# ----------------------------------------------------------------------------
# Write A2. Export-Csv writes NOTHING for an empty collection, so on zero rows
# emit the byte-exact header line explicitly (the artifact must always exist
# with a valid header so the dashboard's Power Query never errors).
# ----------------------------------------------------------------------------
if ($usageRows.Count -gt 0) {
    # -UseQuotes AsNeeded keeps simple values (including the header names) bare so
    # the first line is the byte-exact header; fields with commas/quotes are still
    # quoted per RFC 4180 (Power Query reads either form).
    $usageRows | Select-Object `
        UserPrincipalName, YearMonth, TeamsPrompts, WordPrompts, ExcelPrompts, `
        OutlookPrompts, PowerPointPrompts, ChatPrompts, TotalPrompts, ActiveDays, `
        LastActivityDate |
        Export-Csv -Path $usagePath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded
}
else {
    Set-Content -Path $usagePath -Value $usageHeader -Encoding UTF8
}
$usageRowCount = $usageRows.Count
Write-Progress-Log ("  A2 ai_copilot_usage_graph.csv: {0} user-month row(s)" -f $usageRowCount) ([ConsoleColor]::Green)

# ----------------------------------------------------------------------------
# Summary (Write-Host does not pollute the pipeline) + return object.
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "==== AI Copilot usage (Purview) collection summary ====" -ForegroundColor White
Write-Host ("OutputDirectory : {0}" -f $OutputDirectory)
Write-Host ("CopilotUsage    : {0} row(s)" -f $usageRowCount)
Write-Host ("EventsParsed    : {0}" -f $parsed.Count)
Write-Host ""

return [PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    CopilotUsage    = [pscustomobject]@{ Path = $usagePath; RowCount = $usageRowCount; EventsParsed = $parsed.Count }
}
