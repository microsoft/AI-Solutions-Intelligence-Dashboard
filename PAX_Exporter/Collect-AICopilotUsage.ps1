<#
.SYNOPSIS
    Collects the Section-A A2 Copilot usage artifacts for the AI Solutions
    dashboard from Microsoft Purview Audit CopilotInteraction events.

.DESCRIPTION
    The AI Solutions dashboard (pbit) imports thirteen CSVs. This collector
    delivers the two Section-A A2 artifacts:

        A2 -- ai_copilot_usage_graph.csv (Power Query table AI_CopilotUsage):
            A Purview Audit search (Search-UnifiedAuditLog) for
            'CopilotInteraction' events over a date window, whose AuditData is
            parsed and pivoted into one row per UserPrincipalName x YearMonth
            with per-surface prompt counts (Teams/Word/Excel/Outlook/PowerPoint/
            Chat), a Total, an ActiveDays distinct-date count, and a
            LastActivityDate.

        A2 normalized -- ai_copilot_surface_usage.csv (Power Query table
            AI_CopilotSurfaceUsage): one row per user x month x observed
            surface x source workload x source app host. This preserves every
            nonblank Purview surface dynamically, including future workloads,
            without requiring a new fixed CSV column.

    Why a SEPARATE script (not the Graph collector): the required source
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
    Directory that receives ai_copilot_usage_graph.csv and
    ai_copilot_surface_usage.csv. Created if missing.

.PARAMETER StartDate
    Lower bound of the audit search window. When unbound, defaults to
    (Get-Date).AddDays(-180).

.PARAMETER EndDate
    Upper bound of the audit search window. When unbound, defaults to
    (Get-Date).

.PARAMETER PageSize
    Search-UnifiedAuditLog ResultSize / page size for the ReturnLargeSet
    session. Defaults to 5000.

.PARAMETER MaxRecordsPerWindow
    ReturnLargeSet can return at most 50,000 records per session. A window that
    reaches this threshold is split in half and retried so truncation is never
    silently accepted. Defaults to 50,000.

.PARAMETER MinWindowMinutes
    Smallest audit window permitted during saturation splitting. If a window at
    this floor still reaches MaxRecordsPerWindow, the collector throws rather
    than writing an incomplete result. Defaults to 1 minute.

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
    $mock = { param($ctx) if ($ctx.Page -eq 0) { ,@([pscustomobject]@{ AuditData = '{"UserId":"a@x","CreationTime":"2026-05-04T10:00:00Z","Workload":"Word","CopilotEventData":{"Prompts":[1,2,3]}}' }) } else { @() } }
    .\Collect-AICopilotUsage.ps1 -SearchExecutor $mock -OutputDirectory $tempDir

.NOTES
    Requires PowerShell 7+. For real (non-mock) execution the identity used must
    have Exchange Online audit access (Search-UnifiedAuditLog) via an active
    Connect-ExchangeOnline session with the ExchangeOnlineManagement module and
    the View-Only Audit Logs or Audit Logs role. Audit-derived Copilot values can
    differ from the official Microsoft 365 Copilot usage report.
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

    [int]$MaxRecordsPerWindow = 50000,

    [double]$MinWindowMinutes = 1,

    [scriptblock]$SearchExecutor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Constants: byte-exact headers (do not rename / reorder).
# ----------------------------------------------------------------------------
$usageHeader = 'UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate'
$surfaceHeader = 'UserPrincipalName,YearMonth,Surface,SourceWorkload,SourceAppHost,PromptCount,ActiveDays,LastActivityDate'

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

function ConvertTo-CopilotSurface {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unknown' }
    $trimmed = $Value.Trim()
    $surface = switch ($trimmed) {
        'MicrosoftTeams' { 'Teams' }
        'Teams'          { 'Teams' }
        'Word'           { 'Word' }
        'Excel'          { 'Excel' }
        'Outlook'        { 'Outlook' }
        'PowerPoint'     { 'PowerPoint' }
        'BizChat'        { 'Chat' }
        'Bing'           { 'Chat' }
        'Office'         { 'Chat' }
        'M365App'        { 'Chat' }
        'M365Chat'       { 'Chat' }
        'Microsoft365'   { 'Chat' }
        default          { $trimmed }
    }
    return $surface
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
if ($EndDate -le $StartDate) {
    throw 'EndDate must be later than StartDate.'
}
if ($PageSize -lt 1 -or $PageSize -gt 5000) {
    throw 'PageSize must be between 1 and 5000.'
}
if ($MaxRecordsPerWindow -lt $PageSize) {
    throw 'MaxRecordsPerWindow must be greater than or equal to PageSize.'
}
if ($MinWindowMinutes -le 0) {
    throw 'MinWindowMinutes must be greater than zero.'
}

# ----------------------------------------------------------------------------
# Resolve output directory.
# ----------------------------------------------------------------------------
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$usagePath = Join-Path $OutputDirectory 'ai_copilot_usage_graph.csv'
$surfacePath = Join-Path $OutputDirectory 'ai_copilot_surface_usage.csv'

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
# Paginated Purview audit search with bounded time-window subdivision. A
# ReturnLargeSet session stops at 50,000 records; any saturated window is split
# and retried. Each accepted record retains its half-open window so boundary
# records can be filtered deterministically during parsing.
# ----------------------------------------------------------------------------
$windowQueue = [System.Collections.Generic.Queue[object]]::new()
$windowQueue.Enqueue([pscustomobject]@{ Start = $StartDate; End = $EndDate })
$all  = [System.Collections.Generic.List[object]]::new()
while ($windowQueue.Count -gt 0) {
    $window = $windowQueue.Dequeue()
    $sessionId = [guid]::NewGuid().ToString()
    $page = 0
    $windowRecords = [System.Collections.Generic.List[object]]::new()
    do {
        $ctx = [pscustomobject]@{
            StartDate      = $window.Start
            EndDate        = $window.End
            SessionId      = $sessionId
            SessionCommand = 'ReturnLargeSet'
            ResultSize     = $PageSize
            Page           = $page
        }
        if ($useMock) {
            $batch = & $SearchExecutor $ctx
        }
        else {
            $batch = Search-UnifiedAuditLog -StartDate $window.Start -EndDate $window.End `
                       -Operations 'CopilotInteraction' -ResultSize $PageSize `
                       -SessionId $sessionId -SessionCommand ReturnLargeSet
        }
        $count = 0
        if ($null -ne $batch) {
            foreach ($r in @($batch)) { [void]$windowRecords.Add($r); $count++ }
        }
        $page++
    } while ($count -gt 0 -and $windowRecords.Count -lt $MaxRecordsPerWindow)

    if ($windowRecords.Count -ge $MaxRecordsPerWindow) {
        $windowMinutes = ($window.End - $window.Start).TotalMinutes
        if ($windowMinutes -le $MinWindowMinutes) {
            throw "Purview audit window [$($window.Start.ToString('o')), $($window.End.ToString('o'))) reached $MaxRecordsPerWindow records at the $MinWindowMinutes-minute floor. Refine the source query or lower the collection range."
        }
        $midpoint = $window.Start.AddTicks([long](($window.End.Ticks - $window.Start.Ticks) / 2))
        $windowQueue.Enqueue([pscustomobject]@{ Start = $window.Start; End = $midpoint })
        $windowQueue.Enqueue([pscustomobject]@{ Start = $midpoint; End = $window.End })
        Write-Warning "Purview audit window reached $MaxRecordsPerWindow records; retrying as two smaller windows."
        continue
    }

    foreach ($r in $windowRecords) {
        [void]$all.Add([pscustomobject]@{
            Record      = $r
            WindowStart = $window.Start
            WindowEnd   = $window.End
        })
    }
}

Write-Progress-Log ("  A2 CopilotInteraction events retrieved: {0}" -f $all.Count) ([ConsoleColor]::Cyan)

# ----------------------------------------------------------------------------
# Parse each audit record (StrictMode-safe) into an intermediate usage row.
# ----------------------------------------------------------------------------
$parsed = [System.Collections.Generic.List[object]]::new()
foreach ($item in $all) {
    $rec = $item.Record
    $audit = Get-PropValue $rec 'AuditData'
    if ($null -eq $audit) { continue }
    $data = $audit | ConvertFrom-Json

    $userId = Get-PropValue $data 'UserId'
    if ($null -eq $userId -or [string]$userId -eq '') { continue }
    $upn = ([string]$userId).ToLower()

    $creationRaw = Get-PropValue $data 'CreationTime'
    if ($null -eq $creationRaw -or [string]$creationRaw -eq '') {
        $creationRaw = Get-PropValue $rec 'CreationDate'
    }
    if ($null -eq $creationRaw -or [string]$creationRaw -eq '') { continue }
    $creation = [datetime]::Parse([string]$creationRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    if ($creation -lt $item.WindowStart -or $creation -ge $item.WindowEnd) { continue }
    $yearMonth = $creation.ToString('yyyy-MM')
    $date = $creation.ToString('yyyy-MM-dd')

    $rawWorkload = ConvertTo-CsvField (Get-PropValue $data 'Workload')
    $ced = Get-PropValue $data 'CopilotEventData'
    $rawAppHost = ConvertTo-CsvField (Get-PropValue $ced 'AppHost')
    if ([string]::IsNullOrWhiteSpace($rawAppHost)) {
        $rawAppHost = ConvertTo-CsvField (Get-PropValue $data 'AppHost')
    }
    $surfaceSource = if ([string]::IsNullOrWhiteSpace($rawAppHost)) {
        $rawWorkload
    }
    else {
        $rawAppHost
    }
    $surface = ConvertTo-CopilotSurface $surfaceSource

    $p = Get-PropValue $ced 'Prompts'
    $prompts = if ($p) { @($p).Count } else { 1 }

    $parsed.Add([pscustomobject]@{
        UPN            = $upn
        YearMonth      = $yearMonth
        Date           = $date
        Surface        = $surface
        SourceWorkload = $rawWorkload
        SourceAppHost  = $rawAppHost
        Prompts        = $prompts
    })
}

# ----------------------------------------------------------------------------
# Legacy compatibility pivot: one row per UPN x YearMonth with the original six
# fixed surface columns. TotalPrompts includes every observed surface.
# ----------------------------------------------------------------------------
$usageRows = [System.Collections.Generic.List[object]]::new()
$groups = $parsed | Group-Object -Property UPN, YearMonth
foreach ($g in $groups) {
    $first = $g.Group[0]

    $teams = ($g.Group | Where-Object { $_.Surface -eq 'Teams' }      | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $word  = ($g.Group | Where-Object { $_.Surface -eq 'Word' }       | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $excel = ($g.Group | Where-Object { $_.Surface -eq 'Excel' }      | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $outl  = ($g.Group | Where-Object { $_.Surface -eq 'Outlook' }    | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $ppt   = ($g.Group | Where-Object { $_.Surface -eq 'PowerPoint' } | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $chat  = ($g.Group | Where-Object { $_.Surface -eq 'Chat' }       | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum

    if ($null -eq $teams) { $teams = 0 }
    if ($null -eq $word)  { $word  = 0 }
    if ($null -eq $excel) { $excel = 0 }
    if ($null -eq $outl)  { $outl  = 0 }
    if ($null -eq $ppt)   { $ppt   = 0 }
    if ($null -eq $chat)  { $chat  = 0 }

    $activeDays = @($g.Group | ForEach-Object { $_.Date } | Select-Object -Unique).Count
    $lastActivity = ($g.Group | ForEach-Object { $_.Date } | Measure-Object -Maximum).Maximum
    $total = ($g.Group | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    if ($null -eq $total) { $total = 0 }

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
# Dynamic surface fact: retain each observed Purview surface and its raw source
# fields. Grouping by source fields preserves provenance while the report can
# aggregate PromptCount by the friendly Surface value.
# ----------------------------------------------------------------------------
$surfaceRows = [System.Collections.Generic.List[object]]::new()
$surfaceGroups = $parsed | Group-Object -Property UPN, YearMonth, Surface, SourceWorkload, SourceAppHost
foreach ($g in $surfaceGroups) {
    $first = $g.Group[0]
    $promptCount = ($g.Group | ForEach-Object { $_.Prompts } | Measure-Object -Sum).Sum
    $activeDays = @($g.Group | ForEach-Object { $_.Date } | Select-Object -Unique).Count
    $lastActivity = ($g.Group | ForEach-Object { $_.Date } | Measure-Object -Maximum).Maximum

    $surfaceRows.Add([pscustomobject]@{
        UserPrincipalName = $first.UPN
        YearMonth         = $first.YearMonth
        Surface           = $first.Surface
        SourceWorkload    = $first.SourceWorkload
        SourceAppHost     = $first.SourceAppHost
        PromptCount       = [int]$promptCount
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

if ($surfaceRows.Count -gt 0) {
    $surfaceRows | Select-Object `
        UserPrincipalName, YearMonth, Surface, SourceWorkload, SourceAppHost, `
        PromptCount, ActiveDays, LastActivityDate |
        Export-Csv -Path $surfacePath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded
}
else {
    Set-Content -Path $surfacePath -Value $surfaceHeader -Encoding UTF8
}

$usageRowCount = $usageRows.Count
$surfaceRowCount = $surfaceRows.Count
Write-Progress-Log ("  A2 ai_copilot_usage_graph.csv: {0} user-month row(s)" -f $usageRowCount) ([ConsoleColor]::Green)
Write-Progress-Log ("  A2 ai_copilot_surface_usage.csv: {0} surface row(s)" -f $surfaceRowCount) ([ConsoleColor]::Green)

# ----------------------------------------------------------------------------
# Summary (Write-Host does not pollute the pipeline) + return object.
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "==== AI Copilot usage (Purview) collection summary ====" -ForegroundColor White
Write-Host ("OutputDirectory : {0}" -f $OutputDirectory)
Write-Host ("CopilotUsage    : {0} row(s)" -f $usageRowCount)
Write-Host ("SurfaceUsage    : {0} row(s)" -f $surfaceRowCount)
Write-Host ("EventsParsed    : {0}" -f $parsed.Count)
Write-Host ""

return [PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    CopilotUsage    = [pscustomobject]@{ Path = $usagePath; RowCount = $usageRowCount; EventsParsed = $parsed.Count }
    SurfaceUsage    = [pscustomobject]@{ Path = $surfacePath; RowCount = $surfaceRowCount; EventsParsed = $parsed.Count }
}
