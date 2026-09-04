<#
.SYNOPSIS
    Exports ALL rows from a Microsoft Defender Advanced Hunting (Microsoft Graph
    security/runHuntingQuery) KQL query, defeating the hard 10,000-row-per-query
    cap by adaptive time-slicing.

.DESCRIPTION
    Microsoft Defender Advanced Hunting returns a HARD MAXIMUM of 10,000 rows per
    query with NO continuation / paging token. This tool defeats that wall by
    reusing the adaptive time-slicing strategy from PAX
    (PAX_Purview_Audit_Log_Processor_v1.11.11.ps1):

      * The overall [StartDate, EndDate) range is split into an initial queue of
        half-open time partitions.
      * Each partition is queried. If it returns >= RowCap rows it is SATURATED,
        meaning rows were almost certainly truncated by the API. The partition is
        SUBDIVIDED and the sub-windows are pushed back onto the work queue.
      * SMART SUBDIVISION (mirrors PAX): instead of blindly halving, the tool
        measures the timespan actually covered by the saturated batch, estimates
        records/hour, and picks a subdivision factor that targets
        ~TargetRowsPerWindow rows per sub-window. A floor of MinWindowMinutes
        prevents infinite subdivision.
      * Partitions returning < RowCap are ACCEPTED and their rows merged.

    Because every interval is half-open [start, end) and contiguous, boundary
    rows are never double-counted, so no deduplication is required by default.

    The query executor is injectable via -QueryExecutor, which lets the entire
    subdivision algorithm be unit-tested with a synthetic dataset and ZERO
    credentials. When -QueryExecutor is not supplied, the tool calls the real
    Microsoft Graph endpoint.

    NO tenant id, client id, secret, or token is ever hardcoded or logged.

.PARAMETER Query
    The KQL query to execute. It MUST contain the literal token {TIMEFILTER} at
    the point where a time predicate belongs. For each partition the token is
    replaced with:
        <TimeColumn> >= datetime(<startISO>) and <TimeColumn> < datetime(<endISO>)
    If the query does not contain {TIMEFILTER} a terminating error is thrown.
    The query MAY ALSO contain the OPTIONAL token {USERFILTER}. It is required
    only when -UserBucketColumn is supplied (Month-mode saturation safeguard);
    it is replaced with a per-user hash-bucket predicate
    (hash(<UserBucketColumn>, <bucketCount>) == <bucketIndex>) while bucketing,
    and with the literal 'true' otherwise. If -UserBucketColumn is NOT supplied,
    any {USERFILTER} token is simply replaced with 'true'.

.PARAMETER StartDate
    Inclusive start of the export range (half-open interval start).

.PARAMETER EndDate
    Exclusive end of the export range (half-open interval end).

.PARAMETER TimeColumn
    The KQL column used for time filtering / subdivision analysis.
    Defaults to 'Timestamp' (the CloudAppEvents time column).

.PARAMETER OutputPath
    Path to the CSV file that receives the merged result set.

.PARAMETER OutputColumns
    Optional ordered list of expected output columns. When supplied, non-empty
    results are validated and reordered to this schema, and zero-row exports
    receive a header-only CSV instead of a blank file.

.PARAMETER InitialPartitionHours
    Initial partition size, in hours, used to build the first work queue.
    Defaults to 12.

.PARAMETER MaxPartitions
    Maximum number of INITIAL partitions. If the range divided by
    InitialPartitionHours would exceed this, the partition size is recomputed as
    totalHours / MaxPartitions (mirrors PAX). Subdivision can still create more
    windows beyond this count. Defaults to 400.

.PARAMETER MinWindowMinutes
    Subdivision floor. A window at or below this size that STILL saturates cannot
    be subdivided further; a warning is emitted and the returned (truncated) rows
    are kept. Defaults to 1.

.PARAMETER RowCap
    Saturation threshold. A partition returning >= RowCap rows triggers
    subdivision. Defaults to 10000 (the real API cap).

.PARAMETER TargetRowsPerWindow
    Smart-subdivision target row count per sub-window (buffer below RowCap,
    mirrors PAX ~8000). Defaults to 8000.

.PARAMETER PartitionMode
    Selects how the initial work queue is built and whether saturated windows
    are subdivided:
      * Adaptive (default) - the current adaptive time-slicing strategy for
        RAW / event-grain rows. Saturated windows are subdivided down to the
        MinWindowMinutes floor to recover truncated rows.
      * Month - one partition per calendar month with NO sub-month
        subdivision. REQUIRED for MONTHLY-AGGREGATED queries (e.g.
        summarize ... dcount(...) by UPN, AISolution, YearMonth) so that a
        single user's month is never split across windows and per-month
        distinct counts stay EXACT. In Month mode a month that still returns
        >= RowCap is kept as-is (its aggregates may be API-truncated) and a
        warning recommends the future -UserBucketColumn safeguard; the window
        is never subdivided.

.PARAMETER UserBucketColumn
    OPTIONAL. Month-mode-only saturation safeguard. The KQL column to hash-bucket
    users on when a calendar month still returns >= RowCap even after month-only
    partitioning (e.g. AccountObjectId for CloudAppEvents-based per-user monthly
    aggregates, AccountUpn for sign-in-based aggregates). When set, the -Query
    MUST contain a {USERFILTER} token, and -PartitionMode MUST be 'Month'. On a
    saturated month the tool re-runs that month split into 2, then 4, 8, ...
    hash buckets (doubling until every bucket is under RowCap or MaxUserBuckets
    is reached). Because hash(col, N) maps a given user to a STABLE bucket, every
    event for that user in that month lands in exactly ONE bucket, so per-month
    distinct counts stay EXACT. Not used in Adaptive mode. Default: unset (no
    bucketing).

.PARAMETER MaxUserBuckets
    Ceiling on the hash-bucket doubling for -UserBucketColumn. Must be >= 2 when
    -UserBucketColumn is supplied. If a bucket STILL saturates at this ceiling,
    the rows are kept, SaturatedWindowHit is set, and a warning is emitted
    (genuine per-user volume beyond the API cap within a single month). Defaults
    to 64.

.PARAMETER AccessToken
    A pre-acquired Microsoft Graph bearer token. If supplied it is used directly
    for the real executor. Never logged.

.PARAMETER TenantId
    Azure AD tenant id for client-credentials token acquisition. Used only when
    -AccessToken is not supplied.

.PARAMETER ClientId
    App registration (client) id for client-credentials token acquisition.

.PARAMETER ClientSecret
    App registration client secret as a SecureString. Never logged.

.PARAMETER QueryExecutor
    INJECTION SEAM FOR TESTING. A scriptblock that receives a single argument: a
    PSCustomObject with properties Kql, Start (datetime), End (datetime), and the
    bucketing context BucketColumn (string, '' when not bucketing), BucketCount
    (int, 0 when not bucketing) and BucketIndex (int). It must return an array of
    row objects (PSCustomObjects). When supplied, this is used INSTEAD of calling
    Microsoft Graph. This enables credential-free testing of the subdivision and
    user-hash-bucket logic.

.PARAMETER DedupeKey
    Optional column name(s). When supplied, the merged result set is de-duplicated
    by these columns after merge. Off by default because half-open contiguous
    intervals already guarantee no boundary double-counting.

.EXAMPLE
    # Real export using a pre-acquired Graph token and a preset KQL file.
    $kql = Get-Content .\presets\CloudAppEvents_ai_activity_sessions.kql -Raw
    .\Export-DefenderAdvancedHunting.ps1 -Query $kql `
        -StartDate '2026-06-01' -EndDate '2026-06-08' `
        -OutputPath .\ai_activity_sessions.csv `
        -AccessToken $env:GRAPH_TOKEN

.EXAMPLE
    # Real export using an app registration (client credentials).
    $secret = Read-Host -AsSecureString 'Client secret'
    .\Export-DefenderAdvancedHunting.ps1 -Query $kql `
        -StartDate '2026-06-01' -EndDate '2026-07-01' `
        -OutputPath .\out.csv `
        -TenantId $tid -ClientId $cid -ClientSecret $secret

.EXAMPLE
    # Credential-free test using an injected mock executor.
    $mock = { param($ctx) $data | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End } }
    .\Export-DefenderAdvancedHunting.ps1 -Query 'CloudAppEvents | where {TIMEFILTER}' `
        -StartDate '2026-06-01' -EndDate '2026-06-02' `
        -OutputPath .\test.csv -QueryExecutor $mock

.NOTES
    Requires PowerShell 7+. Requires Microsoft Graph permission
    ThreatHunting.Read.All for real (non-mock) execution.
    Subdivision logic mirrors PAX_Purview_Audit_Log_Processor_v1.11.11.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Query,

    [Parameter(Mandatory)]
    [datetime]$StartDate,

    [Parameter(Mandatory)]
    [datetime]$EndDate,

    [string]$TimeColumn = 'Timestamp',

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string[]]$OutputColumns,

    [double]$InitialPartitionHours = 12,

    [int]$MaxPartitions = 400,

    [double]$MinWindowMinutes = 1,

    [int]$RowCap = 10000,

    [int]$TargetRowsPerWindow = 8000,

    [ValidateSet('Adaptive','Month')]
    [string]$PartitionMode = 'Adaptive',

    [string]$UserBucketColumn,

    [int]$MaxUserBuckets = 64,

    [string]$AccessToken,

    [string]$TenantId,

    [string]$ClientId,

    [securestring]$ClientSecret,

    [scriptblock]$QueryExecutor,

    [string[]]$DedupeKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

function Write-Progress-Log {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
}

function ConvertTo-IsoUtc {
    # Emit a stable, round-trippable UTC ISO-8601 string for KQL datetime().
    param([datetime]$Value)
    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
}

function Build-Kql {
    param(
        [string]$Template,
        [string]$Column,
        [datetime]$WindowStart,
        [datetime]$WindowEnd,
        [string]$BucketColumn = '',
        [int]$BucketCount = 0,
        [int]$BucketIndex = 0
    )
    if ($Template -notmatch '\{TIMEFILTER\}') {
        throw "The -Query must contain the literal token '{TIMEFILTER}' at the point where a time predicate belongs. Example: CloudAppEvents | where {TIMEFILTER} | project Timestamp, ActionType"
    }
    $predicate = "$Column >= datetime($(ConvertTo-IsoUtc $WindowStart)) and $Column < datetime($(ConvertTo-IsoUtc $WindowEnd))"
    $result = $Template -replace '\{TIMEFILTER\}', $predicate

    $bucketing = ($BucketColumn -ne '') -and ($BucketCount -gt 0)
    if ($result -match '\{USERFILTER\}') {
        $userPredicate = if ($bucketing) { "hash($BucketColumn, $BucketCount) == $BucketIndex" } else { 'true' }
        $result = $result -replace '\{USERFILTER\}', $userPredicate
    }
    elseif ($bucketing) {
        throw "The -Query must contain the literal token '{USERFILTER}' to use -UserBucketColumn hash bucketing. Add it to the where clause, e.g. | where {TIMEFILTER} and {USERFILTER}"
    }
    return $result
}

function Get-GraphToken {
    <#
        Acquire a Microsoft Graph bearer token via the client-credentials flow.
        Never logs the secret or the resulting token.
    #>
    param(
        [string]$Tenant,
        [string]$Client,
        [securestring]$Secret
    )
    $plain = [System.Net.NetworkCredential]::new('', $Secret).Password
    try {
        $body = @{
            client_id     = $Client
            scope         = 'https://graph.microsoft.com/.default'
            client_secret = $plain
            grant_type    = 'client_credentials'
        }
        $uri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"
        $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $resp.access_token
    }
    finally {
        # Best-effort scrub of the plaintext secret from memory.
        $plain = $null
    }
}

function Invoke-GraphHuntingQuery {
    <#
        Real executor: POST the KQL to security/runHuntingQuery with retry on
        429 / 5xx (respecting Retry-After when present). Returns the results array.
    #>
    param(
        [string]$Kql,
        [string]$Token,
        [int]$MaxAttempts = 5
    )
    $uri = 'https://graph.microsoft.com/v1.0/security/runHuntingQuery'
    $headers = @{ Authorization = "Bearer $Token" }
    $bodyJson = @{ Query = $Kql } | ConvertTo-Json -Depth 5

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -ContentType 'application/json'
            if ($null -eq $resp.results) { return @() }
            return @($resp.results)
        }
        catch {
            $status = $null
            $retryAfter = $null
            try {
                if ($_.Exception.Response) {
                    $status = [int]$_.Exception.Response.StatusCode
                    $ra = $_.Exception.Response.Headers['Retry-After']
                    if ($ra) { $retryAfter = [int]$ra }
                }
            }
            catch { }

            $isRetryable = ($status -eq 429) -or ($status -ge 500 -and $status -le 599)
            if (-not $isRetryable -or $attempt -eq $MaxAttempts) {
                throw "Advanced Hunting query failed (HTTP $status, attempt $attempt/$MaxAttempts): $($_.Exception.Message)"
            }

            $delay = if ($retryAfter) { $retryAfter } else { [Math]::Min(60, [Math]::Pow(2, $attempt)) }
            Write-Progress-Log "  [RETRY] HTTP $status on attempt $attempt/$MaxAttempts - waiting $delay s" ([ConsoleColor]::Yellow)
            Start-Sleep -Seconds $delay
        }
    }
    return @()
}

function Get-RowTimestamp {
    # Best-effort parse of a row's time column into a [datetime]. Returns $null on failure.
    param($Row, [string]$Column)
    if ($null -eq $Row) { return $null }
    $val = $null
    try { $val = $Row.$Column } catch { return $null }
    if ($null -eq $val) { return $null }
    if ($val -is [datetime]) { return $val }
    [datetime]$parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$val, [ref]$parsed)) { return $parsed }
    return $null
}

# ----------------------------------------------------------------------------
# Validate & resolve executor
# ----------------------------------------------------------------------------

if ($EndDate -le $StartDate) {
    throw "EndDate ($EndDate) must be greater than StartDate ($StartDate)."
}

# Fail fast if the template is malformed, before doing any work / auth.
[void](Build-Kql -Template $Query -Column $TimeColumn -WindowStart $StartDate -WindowEnd $EndDate)

# User-hash bucketing is a Month-mode-only saturation safeguard.
if ($UserBucketColumn) {
    if ($PartitionMode -ne 'Month') {
        throw "-UserBucketColumn is only supported with -PartitionMode Month (it is the Month-mode saturation safeguard)."
    }
    if ($MaxUserBuckets -lt 2) {
        throw "-MaxUserBuckets must be >= 2 when -UserBucketColumn is supplied (got $MaxUserBuckets)."
    }
    if ($Query -notmatch '\{USERFILTER\}') {
        throw "The -Query must contain the literal token '{USERFILTER}' when -UserBucketColumn is supplied. Add it to the where clause, e.g. | where {TIMEFILTER} and {USERFILTER}"
    }
}

$useMock = $null -ne $QueryExecutor
$resolvedToken = $null

if (-not $useMock) {
    if ($AccessToken) {
        $resolvedToken = $AccessToken
    }
    elseif ($TenantId -and $ClientId -and $ClientSecret) {
        Write-Progress-Log "Acquiring Microsoft Graph token via client credentials..." ([ConsoleColor]::Cyan)
        $resolvedToken = Get-GraphToken -Tenant $TenantId -Client $ClientId -Secret $ClientSecret
    }
    else {
        throw "No credentials supplied. Provide -AccessToken, OR -TenantId + -ClientId + -ClientSecret (app registration with Graph ThreatHunting.Read.All), OR a -QueryExecutor mock for testing."
    }
}

# Unified execution seam: returns an array of rows for a given window.
$executeWindow = {
    param([datetime]$WStart, [datetime]$WEnd, [string]$BucketColumn = '', [int]$BucketCount = 0, [int]$BucketIndex = 0)
    $kql = Build-Kql -Template $Query -Column $TimeColumn -WindowStart $WStart -WindowEnd $WEnd -BucketColumn $BucketColumn -BucketCount $BucketCount -BucketIndex $BucketIndex
    if ($useMock) {
        $ctx = [PSCustomObject]@{ Kql = $kql; Start = $WStart; End = $WEnd; BucketColumn = $BucketColumn; BucketCount = $BucketCount; BucketIndex = $BucketIndex }
        $rows = & $QueryExecutor $ctx
    }
    else {
        $rows = Invoke-GraphHuntingQuery -Kql $kql -Token $resolvedToken
    }
    if ($null -eq $rows) { return @() }
    return @($rows)
}

# ----------------------------------------------------------------------------
# Build initial partition queue (half-open [start, end))
# ----------------------------------------------------------------------------

$totalHours = ($EndDate - $StartDate).TotalHours
$queue = [System.Collections.Generic.Queue[object]]::new()

if ($PartitionMode -eq 'Month') {
    # MONTH mode: one half-open partition per calendar month, clamped to
    # [StartDate, EndDate). NO sub-month subdivision and NO MaxPartitions cap,
    # so a single user's month is never split across windows (keeps monthly
    # distinct counts exact for aggregated queries).
    $cursor = $StartDate
    while ($cursor -lt $EndDate) {
        $firstOfNextMonth = [datetime]::new($cursor.Year, $cursor.Month, 1, 0, 0, 0, $cursor.Kind).AddMonths(1)
        $next = if ($firstOfNextMonth -gt $EndDate) { $EndDate } else { $firstOfNextMonth }
        $queue.Enqueue([PSCustomObject]@{ Start = $cursor; End = $next; Level = 0 })
        $cursor = $next
    }

    Write-Progress-Log "Export range: $($StartDate.ToString('u')) to $($EndDate.ToString('u')) ($([Math]::Round($totalHours,2))h)" ([ConsoleColor]::White)
    Write-Progress-Log "PartitionMode=Month; calendar-month partitions queued: $($queue.Count) (NO sub-month subdivision)" ([ConsoleColor]::White)
}
else {
    $partitionHours = $InitialPartitionHours

    $initialCount = [Math]::Ceiling($totalHours / $partitionHours)
    if ($initialCount -gt $MaxPartitions) {
        # Mirror PAX: recompute equal partition size so we stay within MaxPartitions.
        $partitionHours = $totalHours / $MaxPartitions
        $initialCount = $MaxPartitions
        Write-Progress-Log "Initial partition count capped at MaxPartitions=$MaxPartitions; recomputed partition size to $([Math]::Round($partitionHours,3))h" ([ConsoleColor]::Cyan)
    }

    $cursor = $StartDate
    while ($cursor -lt $EndDate) {
        $next = $cursor.AddHours($partitionHours)
        if ($next -gt $EndDate) { $next = $EndDate }
        $queue.Enqueue([PSCustomObject]@{ Start = $cursor; End = $next; Level = 0 })
        $cursor = $next
    }

    Write-Progress-Log "Export range: $($StartDate.ToString('u')) to $($EndDate.ToString('u')) ($([Math]::Round($totalHours,2))h)" ([ConsoleColor]::White)
    Write-Progress-Log "Initial partitions queued: $($queue.Count) (~$([Math]::Round($partitionHours,3))h each)" ([ConsoleColor]::White)
}

# ----------------------------------------------------------------------------
# Process queue with adaptive subdivision (mirrors PAX)
# ----------------------------------------------------------------------------

$minWindowHours = $MinWindowMinutes / 60.0
$results = [System.Collections.Generic.List[object]]::new()
$partitionsExecuted = 0
$subdivisionEvents = 0
$minWindowHit = $false
$saturatedWindowHit = $false
$maxUserBucketsUsed = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while ($queue.Count -gt 0) {
    $part = $queue.Dequeue()
    $windowHours = ($part.End - $part.Start).TotalHours

    $rows = @(& $executeWindow $part.Start $part.End)
    $count = $rows.Count
    $partitionsExecuted++

    if ($count -ge $RowCap) {
        # SATURATED — this window very likely truncated rows.
        if ($PartitionMode -eq 'Month') {
            # MONTH mode: NEVER subdivide by TIME (splitting a calendar month
            # corrupts per-month distinct counts). If a user-hash bucket column
            # is configured, re-run this month split into hash buckets so every
            # event for a given user lands in exactly ONE bucket (dcounts stay
            # exact). Otherwise keep the (possibly truncated) rows and warn.
            if ($UserBucketColumn) {
                $bucketCount = 2
                $bucketRows = $null
                $bucketSaturated = $true
                $lastAttempt = $null
                while ($bucketCount -le $MaxUserBuckets) {
                    $tmp = [System.Collections.Generic.List[object]]::new()
                    $anySaturated = $false
                    for ($b = 0; $b -lt $bucketCount; $b++) {
                        $brows = @(& $executeWindow $part.Start $part.End $UserBucketColumn $bucketCount $b)
                        if ($brows.Count -ge $RowCap) { $anySaturated = $true }
                        foreach ($r in $brows) { $tmp.Add($r) }
                    }
                    $partitionsExecuted += $bucketCount
                    $lastAttempt = $tmp
                    if (-not $anySaturated) {
                        $bucketRows = $tmp
                        $bucketSaturated = $false
                        break
                    }
                    Write-Progress-Log "  [USER-BUCKET] month $($part.Start.ToString('u')) still saturated at $bucketCount buckets; doubling." ([ConsoleColor]::Yellow)
                    $bucketCount *= 2
                }
                $bucketsUsed = [Math]::Min($bucketCount, $MaxUserBuckets)
                if ($bucketsUsed -gt $maxUserBucketsUsed) { $maxUserBucketsUsed = $bucketsUsed }
                if ($bucketSaturated) {
                    # Even at MaxUserBuckets a bucket still saturates: genuine
                    # per-user volume beyond the API cap. Keep the last attempt.
                    $saturatedWindowHit = $true
                    Write-Warning "Calendar-month window $($part.Start.ToString('u')) -> $($part.End.ToString('u')) still returned a saturated hash bucket at MaxUserBuckets=$MaxUserBuckets. Its monthly aggregates may be truncated by the API. Keeping all bucketed rows from the final attempt."
                    foreach ($r in $lastAttempt) { $results.Add($r) }
                }
                else {
                    Write-Progress-Log "[ACCEPT-BUCKETED] month $($part.Start.ToString('u')) -> $($part.End.ToString('u')) split into $bucketCount user-hash buckets; $($bucketRows.Count) rows (total=$($results.Count + $bucketRows.Count))" ([ConsoleColor]::Green)
                    foreach ($r in $bucketRows) { $results.Add($r) }
                }
                continue
            }

            # No bucketing configured: keep the (possibly API-truncated) rows and warn.
            $saturatedWindowHit = $true
            Write-Warning "Calendar-month window $($part.Start.ToString('u')) -> $($part.End.ToString('u')) returned >= RowCap ($count). Its monthly aggregates may be truncated by the API. Configure -UserBucketColumn (with a {USERFILTER} token in the query) to bucket users within saturated months and keep dcounts exact. Keeping $count returned rows without subdivision."
            foreach ($r in $rows) { $results.Add($r) }
            continue
        }

        $atFloor = $windowHours -le ($minWindowHours + 1e-9)
        if ($atFloor) {
            # Cannot subdivide further; keep what we got and warn (true API limitation).
            $minWindowHit = $true
            Write-Warning "Minimal window $($part.Start.ToString('u')) -> $($part.End.ToString('u')) (~$([Math]::Round($windowHours*60,2)) min) still returned >= RowCap ($count). Records within this window may be truncated by the API; keeping $count returned rows."
            foreach ($r in $rows) { $results.Add($r) }
            continue
        }

        # SMART SUBDIVISION (mirror PAX): target ~TargetRowsPerWindow rows/window.
        $subdivisionFactor = 2
        try {
            $timestamps = @()
            foreach ($r in $rows) {
                $ts = Get-RowTimestamp -Row $r -Column $TimeColumn
                if ($ts) { $timestamps += $ts }
            }
            if ($timestamps.Count -gt 100) {
                $sorted = $timestamps | Sort-Object
                $coveredSpan = ($sorted[-1] - $sorted[0]).TotalHours
                if ($coveredSpan -gt 0 -and $coveredSpan -lt $windowHours) {
                    $recordsPerHour = $RowCap / $coveredSpan
                    $targetHours = $TargetRowsPerWindow / $recordsPerHour
                    if ($targetHours -ge $minWindowHours) {
                        $subdivisionFactor = [Math]::Max(2, [int][Math]::Ceiling($windowHours / $targetHours))
                        Write-Progress-Log "  [SMART SUBDIVISION] covered $([Math]::Round($coveredSpan,3))h of $([Math]::Round($windowHours,3))h; ~$([Math]::Round($recordsPerHour,0)) rec/h -> factor $subdivisionFactor" ([ConsoleColor]::Cyan)
                    }
                }
            }
        }
        catch {
            Write-Progress-Log "  [SMART SUBDIVISION] timestamp analysis failed; using factor 2: $_" ([ConsoleColor]::Yellow)
            $subdivisionFactor = 2
        }

        # Do not create sub-windows below the floor: clamp the factor.
        $maxFactorByFloor = [int][Math]::Floor($windowHours / $minWindowHours)
        if ($maxFactorByFloor -lt 2) { $maxFactorByFloor = 2 }
        if ($subdivisionFactor -gt $maxFactorByFloor) { $subdivisionFactor = $maxFactorByFloor }

        $subHours = $windowHours / $subdivisionFactor
        $subStart = $part.Start
        for ($i = 0; $i -lt $subdivisionFactor; $i++) {
            $subEnd = if ($i -eq ($subdivisionFactor - 1)) { $part.End } else { $part.Start.AddHours(($i + 1) * $subHours) }
            $queue.Enqueue([PSCustomObject]@{ Start = $subStart; End = $subEnd; Level = $part.Level + 1 })
            $subStart = $subEnd
        }

        $subdivisionEvents++
        Write-Progress-Log "[SUBDIVIDE] $($part.Start.ToString('u')) -> $($part.End.ToString('u')) ($([Math]::Round($windowHours,3))h) returned $count >= cap; split into $subdivisionFactor. Queue=$($queue.Count)" ([ConsoleColor]::Yellow)
    }
    else {
        # ACCEPTED
        foreach ($r in $rows) { $results.Add($r) }
        Write-Progress-Log "[ACCEPT] $($part.Start.ToString('u')) -> $($part.End.ToString('u')) : $count rows (total=$($results.Count), executed=$partitionsExecuted, queue=$($queue.Count))" ([ConsoleColor]::Green)
    }
}

$sw.Stop()

# ----------------------------------------------------------------------------
# Optional dedupe & output
# ----------------------------------------------------------------------------

$finalRows = $results
if ($DedupeKey -and $DedupeKey.Count -gt 0) {
    $before = $finalRows.Count
    $finalRows = $finalRows | Sort-Object -Property $DedupeKey -Unique
    Write-Progress-Log "Dedupe by [$($DedupeKey -join ', ')]: $before -> $($finalRows.Count) rows" ([ConsoleColor]::Cyan)
}

if ($OutputColumns -and $OutputColumns.Count -gt 0) {
    $invalidColumns = @($OutputColumns | Where-Object { [string]::IsNullOrWhiteSpace($_) })
    if ($invalidColumns.Count -gt 0) {
        throw 'OutputColumns cannot contain blank names.'
    }
    if (@($finalRows).Count -gt 0) {
        $availableColumns = @($finalRows[0].PSObject.Properties.Name)
        $missingColumns = @($OutputColumns | Where-Object { $_ -notin $availableColumns })
        if ($missingColumns.Count -gt 0) {
            throw "Query result is missing expected output column(s): $($missingColumns -join ', ')."
        }
        $finalRows = @($finalRows | Select-Object -Property $OutputColumns)
    }
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if (@($finalRows).Count -gt 0) {
    $finalRows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
}
else {
    $header = if ($OutputColumns -and $OutputColumns.Count -gt 0) {
        $headerObject = [ordered]@{}
        foreach ($column in $OutputColumns) {
            $headerObject[[string]$column] = $null
        }
        [string](
            [PSCustomObject]$headerObject |
                ConvertTo-Csv -NoTypeInformation |
                Select-Object -First 1
        )
    }
    else {
        ''
    }
    [System.IO.File]::WriteAllText($OutputPath, $header + "`n")
}

$summary = [PSCustomObject]@{
    TotalRows          = @($finalRows).Count
    PartitionsExecuted = $partitionsExecuted
    SubdivisionEvents  = $subdivisionEvents
    MinWindowHit       = $minWindowHit
    PartitionMode      = $PartitionMode
    SaturatedWindowHit = $saturatedWindowHit
    MaxUserBucketsUsed = $maxUserBucketsUsed
    ElapsedSeconds     = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
    OutputPath         = $OutputPath
}

Write-Progress-Log "" 
Write-Progress-Log "==== EXPORT SUMMARY ====" ([ConsoleColor]::White)
Write-Progress-Log "TotalRows          : $($summary.TotalRows)" ([ConsoleColor]::White)
Write-Progress-Log "PartitionsExecuted : $($summary.PartitionsExecuted)" ([ConsoleColor]::White)
Write-Progress-Log "SubdivisionEvents  : $($summary.SubdivisionEvents)" ([ConsoleColor]::White)
Write-Progress-Log "MinWindowHit       : $($summary.MinWindowHit)" ([ConsoleColor]::White)
Write-Progress-Log "PartitionMode      : $($summary.PartitionMode)" ([ConsoleColor]::White)
Write-Progress-Log "SaturatedWindowHit : $($summary.SaturatedWindowHit)" ([ConsoleColor]::White)
Write-Progress-Log "ElapsedSeconds     : $($summary.ElapsedSeconds)" ([ConsoleColor]::White)
Write-Progress-Log "OutputPath         : $($summary.OutputPath)" ([ConsoleColor]::White)

return $summary
