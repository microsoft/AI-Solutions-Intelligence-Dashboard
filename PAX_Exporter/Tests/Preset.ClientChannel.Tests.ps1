<#
    Preset.ClientChannel.Tests.ps1

    CREDENTIAL-FREE substitution smoke test for the
    presets/DeviceNetworkEvents_ai_client_channel.kql preset (slice B2b).

    Verifies that the preset carries the EXACT dashboard aggregate schema
    (Section B5 of kql_queries_v22_E5V3.kql) and that it substitutes correctly
    through Export-DefenderAdvancedHunting.ps1 in Month mode WITHOUT user-hash
    bucketing. This is the MONTHLY-AGGREGATED client/channel query: it groups by
    AISite/Channel/YearMonth with NO user dimension, so it carries ONLY the
    {TIMEFILTER} token and is EXEMPT from {USERFILTER} bucketing.

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Follows the SAME plain-
    PowerShell assertion style as Preset.OffHoursGeo.Tests.ps1 (run, assert,
    print PASS/FAIL per case, exit non-zero if ANY case fails, fixed
    Get-Random -SetSeed).

    Cases:
      c1. {TIMEFILTER} is present AND {USERFILTER} is ABSENT (this preset must
          NOT carry a user filter -- no bucketing).
      c2. Exact aggregate schema: the summarize group-by line
          `summarize EventCount = count() by AISite, Channel, YearMonth` and the
          order-by `order by AISite asc, YearMonth asc, Channel asc` match B5.
      c3. Non-bucket substitution: Month mode, no -UserBucketColumn -> the first
          built KQL has NO leftover {TIMEFILTER}/{USERFILTER} tokens and carries
          a real time predicate (Timestamp >= datetime(). There is no
          `where true`/hash assertion -- this preset has no {USERFILTER}.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed (dataset construction is index/time-based and
# deterministic on its own; this satisfies the fixed-seed requirement).
$null = Get-Random -SetSeed 20260603

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$presetPath = Join-Path $PSScriptRoot '..\presets\DeviceNetworkEvents_ai_client_channel.kql'
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

# The c3 capturing mock records every fully-substituted KQL string the exporter
# builds into a per-case List captured via .GetNewClosure() (a reference-type
# List, so the closure and the test share the SAME object). The scriptblock is
# invoked by the exporter with `& $QueryExecutor`, so a $script: lookup would
# resolve against the EXPORTER's scope; a closure over a local List keeps the
# capture bound to THIS test. Returned rows are synthetic PSCustomObjects with
# the 4 aggregate columns; row math is irrelevant -- these cases inspect only
# the built KQL string and the exit status.

# ===========================================================================
# CASE c1. Single token: {TIMEFILTER} present, {USERFILTER} absent.
#   This preset aggregates with no user dimension, so it must NOT carry a
#   {USERFILTER} token (no user-hash bucketing).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c1: preset carries {TIMEFILTER} and NOT {USERFILTER} ----" -ForegroundColor Cyan
try {
    $hasTime = $presetRaw.Contains('{TIMEFILTER}')
    $hasUser = $presetRaw.Contains('{USERFILTER}')
    $passC1 = $hasTime -and (-not $hasUser)
    Add-CaseResult -Name 'c1. preset contains {TIMEFILTER} and NOT {USERFILTER}' -Pass $passC1 `
        -Detail ("hasTIMEFILTER={0}; hasUSERFILTER={1}" -f $hasTime, $hasUser)
}
catch {
    Add-CaseResult -Name 'c1. preset contains {TIMEFILTER} and NOT {USERFILTER}' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c2. Exact aggregate schema (B5 contract).
#   - The summarize group-by line:
#       summarize EventCount = count() by AISite, Channel, YearMonth
#   - The order-by line:
#       order by AISite asc, YearMonth asc, Channel asc
# ===========================================================================
Write-Host ""
Write-Host "---- Case c2: exact aggregate schema (summarize group-by + order-by) ----" -ForegroundColor Cyan
try {
    $summarizeLine = 'summarize EventCount = count() by AISite, Channel, YearMonth'
    $orderByLine   = 'order by AISite asc, YearMonth asc, Channel asc'
    $hasSummarize = $presetRaw.Contains($summarizeLine)
    $hasOrderBy   = $presetRaw.Contains($orderByLine)
    $passC2 = $hasSummarize -and $hasOrderBy
    Add-CaseResult -Name 'c2. exact aggregate schema (summarize by AISite,Channel,YearMonth + order-by)' -Pass $passC2 `
        -Detail ("summarize={0}; orderBy={1}" -f $hasSummarize, $hasOrderBy)
}
catch {
    Add-CaseResult -Name 'c2. exact aggregate schema (summarize by AISite,Channel,YearMonth + order-by)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c3. Non-bucket substitution (Month mode, no -UserBucketColumn).
#   The FIRST built KQL must contain NO leftover {TIMEFILTER}/{USERFILTER}
#   tokens and carry a real time predicate (Timestamp >= datetime(). There is
#   no {USERFILTER} in this preset, so there is no `where true`/hash assertion.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c3: non-bucket substitution (no leftover tokens, time predicate present) ----" -ForegroundColor Cyan
try {
    # LOCAL datetime literals (no 'Z') so the range is exactly one calendar-month
    # partition regardless of the test runner's timezone.
    $c3Start = [datetime]'2026-05-01T00:00:00'
    $c3End   = [datetime]'2026-06-01T00:00:00'

    $capturedC3 = [System.Collections.Generic.List[string]]::new()
    $c3Mock = {
        param($ctx)
        $capturedC3.Add([string]$ctx.Kql)
        # Small (< RowCap) synthetic set of aggregate rows (4 columns).
        return @(
            [PSCustomObject]@{ AISite='chatgpt.com';            Channel='Browser'; YearMonth='2026-05'; EventCount=42 },
            [PSCustomObject]@{ AISite='copilot.microsoft.com';  Channel='Desktop'; YearMonth='2026-05'; EventCount=17 },
            [PSCustomObject]@{ AISite='claude.ai';              Channel='API';     YearMonth='2026-05'; EventCount=5 }
        )
    }.GetNewClosure()

    $outC3 = New-TempCsvPath 'c3'
    $threwC3 = $false
    try {
        & $scriptPath `
            -Query $presetRaw `
            -StartDate $c3Start -EndDate $c3End -TimeColumn 'Timestamp' `
            -OutputPath $outC3 -PartitionMode 'Month' -RowCap $rowCap `
            -QueryExecutor $c3Mock `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwC3 = $true
    }

    $firstKql = if ($capturedC3.Count -gt 0) { $capturedC3[0] } else { '' }
    $noTimeTok = -not $firstKql.Contains('{TIMEFILTER}')
    $noUserTok = -not $firstKql.Contains('{USERFILTER}')
    $hasTimePred = $firstKql.Contains('Timestamp >= datetime(')
    $passC3 = (-not $threwC3) -and ($capturedC3.Count -gt 0) -and $noTimeTok -and $noUserTok -and $hasTimePred
    Add-CaseResult -Name 'c3. non-bucket substitution (no leftover tokens, time predicate present)' -Pass $passC3 `
        -Detail ("threw={0}; captured={1}; noTimeTok={2}; noUserTok={3}; hasTimePred={4}" -f $threwC3, $capturedC3.Count, $noTimeTok, $noUserTok, $hasTimePred)
    Remove-Item $outC3 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'c3. non-bucket substitution (no leftover tokens, time predicate present)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== PRESET CLIENT-CHANNEL RESULTS ====" -ForegroundColor White
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
