<#
    Preset.FileProximity.Tests.ps1

    CREDENTIAL-FREE substitution smoke test for the
    presets/DeviceNetworkEvents_ai_file_proximity.kql preset (slice B2c).

    Verifies that the preset carries the EXACT row-grain dashboard schema
    (Section B3 of kql_queries_v22_E5V3.kql) and that it substitutes correctly
    through Export-DefenderAdvancedHunting.ps1 in ADAPTIVE mode WITHOUT user-hash
    bucketing. This is the ROW-GRAIN file-proximity correlation query: it joins
    DeviceNetworkEvents (AI visits) to DeviceFileEvents (file activity) and emits
    one row per file touched within 5 minutes of an AI visit. It carries ONLY the
    {TIMEFILTER} token (bound to the AIVisits anchor) and is EXEMPT from user
    bucketing; the DeviceFileEvents side deliberately keeps its own ago(90d)
    window so join-boundary files are not lost.

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Follows the SAME plain-
    PowerShell assertion style as Preset.ClientChannel.Tests.ps1 (run, assert,
    print PASS/FAIL per case, exit non-zero if ANY case fails, fixed
    Get-Random -SetSeed).

    Cases:
      c1. {TIMEFILTER} is present AND {USERFILTER} is ABSENT (no bucketing).
      c2. Exact row-grain schema: the multi-line project list and the order-by
          `order by Timestamp asc`.
      c3. Adaptive substitution: Adaptive mode, no -UserBucketColumn -> the first
          built KQL has NO leftover {TIMEFILTER}/{USERFILTER} tokens and carries
          a real time predicate (Timestamp >= datetime().
      c4. Join-boundary window preserved: the DeviceFileEvents side STILL carries
          a literal `where Timestamp > ago(90d)` and the 5-minute inner-join
          window is intact -- proving {TIMEFILTER} replaced ONLY the AIVisits
          anchor, not the file side.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$null = Get-Random -SetSeed 20260604

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$presetPath = Join-Path $PSScriptRoot '..\presets\DeviceNetworkEvents_ai_file_proximity.kql'
$presetPath = (Resolve-Path $presetPath).Path
$presetRaw  = Get-Content -LiteralPath $presetPath -Raw

$rowCap = 10000

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

# ===========================================================================
# CASE c1. Single token: {TIMEFILTER} present, {USERFILTER} absent.
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
# CASE c2. Exact row-grain schema (B3 contract).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c2: exact row-grain schema (project list + order-by) ----" -ForegroundColor Cyan
try {
    $projStart = 'project Timestamp = AITimestamp, UPN, AISolution, YearMonth, FileName,'
    $projMid   = 'FolderCategory, FolderPath, SecondsToAI,'
    $projEnd   = 'NameMatchesSensitivePattern, FolderMatchesSensitive'
    $orderByLine = 'order by Timestamp asc'
    $hasProjStart = $presetRaw.Contains($projStart)
    $hasProjMid   = $presetRaw.Contains($projMid)
    $hasProjEnd   = $presetRaw.Contains($projEnd)
    $hasOrderBy   = $presetRaw.Contains($orderByLine)
    $passC2 = $hasProjStart -and $hasProjMid -and $hasProjEnd -and $hasOrderBy
    Add-CaseResult -Name 'c2. exact row-grain schema (project 10 cols + order by Timestamp asc)' -Pass $passC2 `
        -Detail ("projStart={0}; projMid={1}; projEnd={2}; orderBy={3}" -f $hasProjStart, $hasProjMid, $hasProjEnd, $hasOrderBy)
}
catch {
    Add-CaseResult -Name 'c2. exact row-grain schema (project 10 cols + order by Timestamp asc)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c3. Adaptive substitution (Adaptive mode, no -UserBucketColumn).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c3: adaptive substitution (no leftover tokens, time predicate present) ----" -ForegroundColor Cyan
try {
    $c3Start = [datetime]'2026-05-01T00:00:00'
    $c3End   = [datetime]'2026-05-02T00:00:00'

    $capturedC3 = [System.Collections.Generic.List[string]]::new()
    $c3Mock = {
        param($ctx)
        $capturedC3.Add([string]$ctx.Kql)
        return @(
            [PSCustomObject]@{ Timestamp=[datetime]'2026-05-01T09:00:00'; UPN='a@x.com'; AISolution='ChatGPT'; YearMonth='2026-05'; FileName='notes.docx'; FolderCategory='Documents'; FolderPath='C:\Users\a\Documents'; SecondsToAI=42; NameMatchesSensitivePattern=0; FolderMatchesSensitive=0 },
            [PSCustomObject]@{ Timestamp=[datetime]'2026-05-01T10:00:00'; UPN='b@x.com'; AISolution='Claude'; YearMonth='2026-05'; FileName='budget.xlsx'; FolderCategory='OneDrive'; FolderPath='C:\Users\b\OneDrive\Finance'; SecondsToAI=88; NameMatchesSensitivePattern=1; FolderMatchesSensitive=1 }
        )
    }.GetNewClosure()

    $outC3 = New-TempCsvPath 'c3'
    $threwC3 = $false
    try {
        & $scriptPath `
            -Query $presetRaw `
            -StartDate $c3Start -EndDate $c3End -TimeColumn 'Timestamp' `
            -OutputPath $outC3 -PartitionMode 'Adaptive' -RowCap $rowCap `
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
    Add-CaseResult -Name 'c3. adaptive substitution (no leftover tokens, time predicate present)' -Pass $passC3 `
        -Detail ("threw={0}; captured={1}; noTimeTok={2}; noUserTok={3}; hasTimePred={4}" -f $threwC3, $capturedC3.Count, $noTimeTok, $noUserTok, $hasTimePred)
    Remove-Item $outC3 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'c3. adaptive substitution (no leftover tokens, time predicate present)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c4. Join-boundary window preserved (single-delta invariant).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c4: DeviceFileEvents ago(90d) window + 5-min join preserved ----" -ForegroundColor Cyan
try {
    $fileAgoPresent = $presetRaw.Contains('| where Timestamp > ago(90d)')
    $joinWindow = $presetRaw.Contains('where FileTimestamp between (AITimestamp .. (AITimestamp + 5m))')
    $anchorTokenized = $presetRaw.Contains('DeviceNetworkEvents') -and $presetRaw.Contains('| where {TIMEFILTER}')
    $passC4 = $fileAgoPresent -and $joinWindow -and $anchorTokenized
    Add-CaseResult -Name 'c4. join-boundary window preserved (file-side ago(90d) + 5m join + anchor tokenized)' -Pass $passC4 `
        -Detail ("fileAgo={0}; joinWindow={1}; anchorTokenized={2}" -f $fileAgoPresent, $joinWindow, $anchorTokenized)
}
catch {
    Add-CaseResult -Name 'c4. join-boundary window preserved (file-side ago(90d) + 5m join + anchor tokenized)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== PRESET FILE-PROXIMITY RESULTS ====" -ForegroundColor White
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
