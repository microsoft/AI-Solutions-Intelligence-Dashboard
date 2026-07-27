<#
    Preset.ActivitySessions.Tests.ps1

    CREDENTIAL-FREE substitution smoke test for the
    presets/CloudAppEvents_ai_activity_sessions.kql preset (slice B1).

    Verifies that the preset carries the EXACT dashboard aggregate schema
    (Section B2 of kql_queries_v22_E5V3.kql) and that it substitutes correctly
    through Export-DefenderAdvancedHunting.ps1 in Month mode -- both without
    user-hash bucketing ({USERFILTER} -> 'true') and with -UserBucketColumn UPN
    ({USERFILTER} -> hash(UPN, N) == b).

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Follows the SAME plain-
    PowerShell assertion style as Export-DefenderAdvancedHunting.MonthMode.Tests.ps1
    (run, assert, print PASS/FAIL per case, exit non-zero if ANY case fails,
    fixed Get-Random -SetSeed).

    Cases:
      p1. Both {TIMEFILTER} and {USERFILTER} tokens are present in the preset.
      p2. Exact aggregate schema: project column list, group-by keys, and the
          dcount/countif aggregations match the B2 contract.
      p3. {USERFILTER} appears AFTER `extend UPN = tolower(AccountObjectId)` so
          the hash(UPN, ...) bucket predicate is valid at the filter point.
      p4. Non-bucket substitution: Month mode, no -UserBucketColumn -> the built
          KQL has NO leftover tokens, carries a real time predicate, and
          {USERFILTER} was replaced with the literal 'true'.
      p5. Bucket substitution: Month mode + -UserBucketColumn UPN over a
          saturated month -> at least one built KQL carries a hash(UPN, ...)
          predicate and NO leftover {USERFILTER} token.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed (dataset construction is index/time-based and
# deterministic on its own; this satisfies the fixed-seed requirement).
$null = Get-Random -SetSeed 20260603

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$presetPath = Join-Path $PSScriptRoot '..\presets\CloudAppEvents_ai_activity_sessions.kql'
$presetPath = (Resolve-Path $presetPath).Path
$presetRaw  = Get-Content -LiteralPath $presetPath -Raw

$rowCap = 10000

# Per-case results collected here; each entry: @{ Name; Pass; Detail }
$caseResults = [System.Collections.Generic.List[object]]::new()

function New-TempCsvPath {
    param([string]$Tag)
    return Join-Path ([System.IO.Path]::GetTempPath()) ("ah_preset_{0}_{1}.csv" -f $Tag, ([guid]::NewGuid().ToString('N')))
}

function Add-CaseResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $caseResults.Add([PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

# The p4/p5 capturing mocks record every fully-substituted KQL string the
# exporter builds into a per-case List captured via .GetNewClosure() (a
# reference-type List, so the closure and the test share the SAME object). The
# scriptblock is invoked by the exporter with `& $QueryExecutor`, so a $script:
# lookup would resolve against the EXPORTER's scope; a closure over a local List
# keeps the capture bound to THIS test. Returned rows are synthetic
# PSCustomObjects with the 9 aggregate columns; row math is irrelevant -- these
# cases inspect only the built KQL string and the exit status.

# ===========================================================================
# CASE p1. Both {TIMEFILTER} and {USERFILTER} tokens are present.
# ===========================================================================
Write-Host ""
Write-Host "---- Case p1: preset carries both {TIMEFILTER} and {USERFILTER} ----" -ForegroundColor Cyan
try {
    $hasTime = $presetRaw.Contains('{TIMEFILTER}')
    $hasUser = $presetRaw.Contains('{USERFILTER}')
    $passP1 = $hasTime -and $hasUser
    Add-CaseResult -Name 'p1. preset contains both {TIMEFILTER} and {USERFILTER}' -Pass $passP1 `
        -Detail ("hasTIMEFILTER={0}; hasUSERFILTER={1}" -f $hasTime, $hasUser)
}
catch {
    Add-CaseResult -Name 'p1. preset contains both {TIMEFILTER} and {USERFILTER}' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE p2. Exact aggregate schema (B2 contract).
#   - The | project line lists exactly, in order:
#       UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts,
#       DistinctDevices, Category, RiskTier
#   - Group-by keys `by UPN, AISolution, YearMonth`
#   - Aggregations: dcount(bin(Timestamp, 1d)), dcount(DeviceType), countif(
# ===========================================================================
Write-Host ""
Write-Host "---- Case p2: exact aggregate schema (project + group-by + aggregations) ----" -ForegroundColor Cyan
try {
    $expectedProject = '| project UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts, DistinctDevices, Category, RiskTier'
    $hasProject   = $presetRaw.Contains($expectedProject)
    $hasGroupBy   = $presetRaw.Contains('by UPN, AISolution, YearMonth')
    $hasActiveDay = $presetRaw.Contains('dcount(bin(Timestamp, 1d))')
    $hasDevices   = $presetRaw.Contains('dcount(DeviceType)')
    $hasCountif   = $presetRaw.Contains('countif(')
    $passP2 = $hasProject -and $hasGroupBy -and $hasActiveDay -and $hasDevices -and $hasCountif
    Add-CaseResult -Name 'p2. exact aggregate schema (project column list + group-by + dcount/countif)' -Pass $passP2 `
        -Detail ("project={0}; groupBy={1}; activeDays={2}; devices={3}; countif={4}" -f $hasProject, $hasGroupBy, $hasActiveDay, $hasDevices, $hasCountif)
}
catch {
    Add-CaseResult -Name 'p2. exact aggregate schema (project column list + group-by + dcount/countif)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE p3. {USERFILTER} appears AFTER `extend UPN = tolower(coalesce(AccountUpn, AccountObjectId))`.
#   The hash(UPN, ...) bucket predicate must be valid at the {USERFILTER}
#   point, which requires UPN to already be defined. Assert the character index
#   of the UPN extend is LESS than the index of {USERFILTER}.
# ===========================================================================
Write-Host ""
Write-Host "---- Case p3: {USERFILTER} appears after `extend UPN = tolower(coalesce(AccountUpn, AccountObjectId))` ----" -ForegroundColor Cyan
try {
    # NOTE: {USERFILTER} also appears in the header comment, so match the BODY
    # occurrence via the `| where {USERFILTER}` line specifically.
    $idxUpn  = $presetRaw.IndexOf('extend UPN = tolower(coalesce(AccountUpn, AccountObjectId))')
    $idxUser = $presetRaw.IndexOf('| where {USERFILTER}')
    $passP3 = ($idxUpn -ge 0) -and ($idxUser -ge 0) -and ($idxUpn -lt $idxUser)
    Add-CaseResult -Name 'p3. {USERFILTER} positioned after UPN definition (hash(UPN,...) valid)' -Pass $passP3 `
        -Detail ("idxUPN={0}; idxUSERFILTER={1}" -f $idxUpn, $idxUser)
}
catch {
    Add-CaseResult -Name 'p3. {USERFILTER} positioned after UPN definition (hash(UPN,...) valid)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE p4. Non-bucket substitution (Month mode, no -UserBucketColumn).
#   The FIRST built KQL must contain NO leftover {TIMEFILTER}/{USERFILTER}
#   tokens, carry a real time predicate (Timestamp >= datetime(), and have
#   {USERFILTER} replaced with the literal 'true' (i.e. contains `where true`).
# ===========================================================================
Write-Host ""
Write-Host "---- Case p4: non-bucket substitution ({USERFILTER} -> true, time predicate present) ----" -ForegroundColor Cyan
try {
    # LOCAL datetime literals (no 'Z') so the range is exactly one calendar-month
    # partition regardless of the test runner's timezone.
    $p4Start = [datetime]'2026-05-01T00:00:00'
    $p4End   = [datetime]'2026-06-01T00:00:00'

    $capturedP4 = [System.Collections.Generic.List[string]]::new()
    $p4Mock = {
        param($ctx)
        $capturedP4.Add([string]$ctx.Kql)
        # Small (< RowCap) synthetic set of aggregate rows (9 columns).
        return @(
            [PSCustomObject]@{ UPN='alice@contoso.com'; AISolution='ChatGPT'; YearMonth='2026-05'; Sessions=4; ActiveDays=3; EstimatedPrompts=5; DistinctDevices=1; Category='General AI'; RiskTier='Conditional' },
            [PSCustomObject]@{ UPN='bob@contoso.com';   AISolution='Claude';  YearMonth='2026-05'; Sessions=2; ActiveDays=2; EstimatedPrompts=1; DistinctDevices=1; Category='General AI'; RiskTier='Unsanctioned' }
        )
    }.GetNewClosure()

    $outP4 = New-TempCsvPath 'p4'
    $threwP4 = $false
    try {
        & $scriptPath `
            -Query $presetRaw `
            -StartDate $p4Start -EndDate $p4End -TimeColumn 'Timestamp' `
            -OutputPath $outP4 -PartitionMode 'Month' -RowCap $rowCap `
            -QueryExecutor $p4Mock `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwP4 = $true
    }

    $firstKql = if ($capturedP4.Count -gt 0) { $capturedP4[0] } else { '' }
    $noTimeTok = -not $firstKql.Contains('{TIMEFILTER}')
    $noUserTok = -not $firstKql.Contains('{USERFILTER}')
    $hasTimePred = $firstKql.Contains('Timestamp >= datetime(')
    $hasWhereTrue = $firstKql.Contains('where true')
    $passP4 = (-not $threwP4) -and ($capturedP4.Count -gt 0) -and $noTimeTok -and $noUserTok -and $hasTimePred -and $hasWhereTrue
    Add-CaseResult -Name 'p4. non-bucket substitution ({USERFILTER}->true, no leftover tokens, time predicate present)' -Pass $passP4 `
        -Detail ("threw={0}; captured={1}; noTimeTok={2}; noUserTok={3}; hasTimePred={4}; hasWhereTrue={5}" -f $threwP4, $capturedP4.Count, $noTimeTok, $noUserTok, $hasTimePred, $hasWhereTrue)
    Remove-Item $outP4 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'p4. non-bucket substitution ({USERFILTER}->true, no leftover tokens, time predicate present)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE p5. Bucket substitution (Month mode + -UserBucketColumn UPN).
#   Force saturation: the initial non-bucket call (BucketCount==0) returns
#   >= RowCap rows, so the exporter re-runs the month split into hash buckets.
#   Bucket calls (BucketCount>0) return a small (< RowCap) set. Assert at least
#   one built KQL carries a hash(UPN, ...) predicate and NO leftover
#   {USERFILTER} token, and the run does not throw.
# ===========================================================================
Write-Host ""
Write-Host "---- Case p5: bucket substitution ({USERFILTER} -> hash(UPN, N) == b) ----" -ForegroundColor Cyan
try {
    $p5Start = [datetime]'2026-05-01T00:00:00'
    $p5End   = [datetime]'2026-06-01T00:00:00'

    $capturedP5 = [System.Collections.Generic.List[string]]::new()
    $p5Mock = {
        param($ctx)
        $capturedP5.Add([string]$ctx.Kql)
        if ($ctx.BucketCount -eq 0) {
            # Initial detection call: return >= RowCap rows to force saturation.
            $rows = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $rowCap; $i++) {
                $rows.Add([PSCustomObject]@{ UPN=("user{0}@contoso.com" -f $i); AISolution='ChatGPT'; YearMonth='2026-05'; Sessions=1; ActiveDays=1; EstimatedPrompts=1; DistinctDevices=1; Category='General AI'; RiskTier='Conditional' })
            }
            return @($rows)
        }
        # Bucket call: small (< RowCap) set so bucketing resolves.
        return @(
            [PSCustomObject]@{ UPN='alice@contoso.com'; AISolution='ChatGPT'; YearMonth='2026-05'; Sessions=3; ActiveDays=2; EstimatedPrompts=2; DistinctDevices=1; Category='General AI'; RiskTier='Conditional' }
        )
    }.GetNewClosure()

    $outP5 = New-TempCsvPath 'p5'
    $threwP5 = $false
    try {
        & $scriptPath `
            -Query $presetRaw `
            -StartDate $p5Start -EndDate $p5End -TimeColumn 'Timestamp' `
            -OutputPath $outP5 -PartitionMode 'Month' -RowCap $rowCap `
            -UserBucketColumn 'UPN' -MaxUserBuckets 4 `
            -QueryExecutor $p5Mock `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwP5 = $true
    }

    # Discriminate the SUBSTITUTED body predicate ("| where hash(UPN, N) == b")
    # from the preset's descriptive header comment ("replaces it with hash(UPN, <N>)")
    # by requiring the 'where hash(UPN,' body form, which the comment never contains.
    $bucketKqls = @($capturedP5 | Where-Object { $_.Contains('where hash(UPN,') })
    $anyHash = $bucketKqls.Count -gt 0
    # The initial detection call (BucketCount==0) is captured FIRST and must have
    # {USERFILTER} -> 'true' (NOT a hash predicate), proving the match is bucket-specific.
    $detectionKql = if ($capturedP5.Count -gt 0) { $capturedP5[0] } else { '' }
    $detectionIsTrue = $detectionKql.Contains('where true') -and -not $detectionKql.Contains('where hash(UPN,')
    $noLeftoverUser = -not (@($capturedP5 | Where-Object { $_.Contains('{USERFILTER}') }).Count -gt 0)
    $passP5 = (-not $threwP5) -and $anyHash -and $detectionIsTrue -and $noLeftoverUser
    Add-CaseResult -Name 'p5. bucket substitution ({USERFILTER}->hash(UPN,...), no leftover token)' -Pass $passP5 `
        -Detail ("threw={0}; captured={1}; bodyHashKqls={2}; detectionIsTrue={3}; noLeftoverUser={4}" -f $threwP5, $capturedP5.Count, $bucketKqls.Count, $detectionIsTrue, $noLeftoverUser)
    Remove-Item $outP5 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'p5. bucket substitution ({USERFILTER}->hash(UPN,...), no leftover token)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== PRESET ACTIVITY-SESSIONS RESULTS ====" -ForegroundColor White
$failed = 0
foreach ($c in $caseResults) {
    $tag = if ($c.Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($c.Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("  {0}: {1}" -f $tag, $c.Name) -ForegroundColor $color
    if (-not $c.Pass) { $failed++ }
}
Write-Host ""

if ($failed -gt 0) {
    Write-Host ("OVERALL: FAIL ({0} of {1} cases failed)" -f $failed, $caseResults.Count) -ForegroundColor Red
    exit 1
}
Write-Host ("OVERALL: PASS (all {0} preset cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
