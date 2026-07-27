<#
    Export-DefenderAdvancedHunting.MonthMode.Tests.ps1

    CREDENTIAL-FREE suite for the -PartitionMode Month feature (slice A1) of
    Export-DefenderAdvancedHunting.ps1.

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Follows the SAME plain-
    PowerShell assertion style as Export-DefenderAdvancedHunting.EdgeCases.Tests.ps1
    (run, assert, print PASS/FAIL per case, exit non-zero if ANY case fails,
    fixed Get-Random -SetSeed).

    Month mode contract (verified by reading the script):
      * Initial queue = one half-open [start, end) partition per calendar month,
        clamped to [StartDate, EndDate). NO MaxPartitions cap.
      * A calendar-month window that returns >= RowCap is KEPT as-is (rows added,
        SaturatedWindowHit = $true) and is NEVER subdivided
        (SubdivisionEvents stays 0).
      * Summary carries PartitionMode and SaturatedWindowHit alongside the
        existing fields (TotalRows, PartitionsExecuted, SubdivisionEvents,
        MinWindowHit, ElapsedSeconds, OutputPath).

    Cases:
      m1. One partition per calendar month for a range NOT starting on the 1st.
      m2. Month mode NEVER subdivides even when a month saturates.
      m3. Row totals equal the sum of per-window mock rows (boundary correctness).
      m4. Summary carries PartitionMode == 'Month'.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed (dataset construction below is index/time-based and
# deterministic on its own; this satisfies the fixed-seed requirement and
# guards any incidental Get-Random use).
$null = Get-Random -SetSeed 20260601

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$rowCap = 10000

# Per-case results collected here; each entry: @{ Name; Pass; Detail }
$caseResults = [System.Collections.Generic.List[object]]::new()

function New-TempCsvPath {
    param([string]$Tag)
    return Join-Path ([System.IO.Path]::GetTempPath()) ("ah_month_{0}_{1}.csv" -f $Tag, ([guid]::NewGuid().ToString('N')))
}

function Add-CaseResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $caseResults.Add([PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

# ===========================================================================
# CASE m1. One partition per calendar month for a range NOT starting on the 1st.
#   StartDate 2026-05-15, EndDate 2026-08-01 => calendar-month partitions:
#     [2026-05-15, 2026-06-01), [2026-06-01, 2026-07-01), [2026-07-01, 2026-08-01)
#   = 3 partitions. With a mock that returns a small (< RowCap) set per window,
#   every partition is ACCEPTED and none is subdivided.
#   Assert PartitionsExecuted == 3 AND SubdivisionEvents == 0.
# ===========================================================================
Write-Host ""
Write-Host "---- Case m1: one partition per calendar month (range not on the 1st) ----" -ForegroundColor Cyan
try {
    # NOTE: datetime literals are LOCAL (no 'Z') so partition boundaries land on
    # true calendar-month starts regardless of the test runner's timezone. A
    # 'Z' literal would be converted to local time and could shift a month-start
    # into the previous calendar month, creating an extra sliver partition.
    $m1Start = [datetime]'2026-05-15T00:00:00'
    $m1End   = [datetime]'2026-08-01T00:00:00'

    # A handful of rows scattered so each month window returns a few (< RowCap).
    $m1Data = [System.Collections.Generic.List[object]]::new()
    $m1Times = @(
        [datetime]'2026-05-20T03:00:00',
        [datetime]'2026-05-28T18:00:00',
        [datetime]'2026-06-05T09:00:00',
        [datetime]'2026-06-19T22:00:00',
        [datetime]'2026-07-02T01:00:00',
        [datetime]'2026-07-30T12:00:00'
    )
    $mid = 0
    foreach ($t in $m1Times) {
        $mid++
        $m1Data.Add([PSCustomObject]@{ Id = $mid; Timestamp = $t; Payload = "m1-$mid" })
    }

    $m1Mock = {
        param($ctx)
        $window = $m1Data | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
        return @($window)
    }.GetNewClosure()

    $outM1 = New-TempCsvPath 'm1'
    $summaryM1 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $m1Start -EndDate $m1End -TimeColumn 'Timestamp' `
        -OutputPath $outM1 -PartitionMode 'Month' -RowCap $rowCap `
        -QueryExecutor $m1Mock

    $passM1 = ($summaryM1.PartitionsExecuted -eq 3) -and ($summaryM1.SubdivisionEvents -eq 0)
    Add-CaseResult -Name 'm1. one partition per calendar month (PartitionsExecuted==3, SubdivisionEvents==0)' -Pass $passM1 `
        -Detail ("PartitionsExecuted={0}; SubdivisionEvents={1}; TotalRows={2}" -f $summaryM1.PartitionsExecuted, $summaryM1.SubdivisionEvents, $summaryM1.TotalRows)
    Remove-Item $outM1 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'm1. one partition per calendar month (PartitionsExecuted==3, SubdivisionEvents==0)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE m2. Month mode NEVER subdivides even when a month saturates.
#   Mock returns EXACTLY RowCap rows for the June window (crammed into a small
#   span so Adaptive would have subdivided), and a few rows for other months.
#   Assert: SubdivisionEvents == 0, SaturatedWindowHit == True, and the
#   saturated month's RowCap rows are ALL kept (TotalRows includes them).
# ===========================================================================
Write-Host ""
Write-Host "---- Case m2: month mode never subdivides on saturation ----" -ForegroundColor Cyan
try {
    # LOCAL literals (no 'Z') -> clean calendar-month partitions: May, Jun, Jul.
    $m2Start = [datetime]'2026-05-01T00:00:00'
    $m2End   = [datetime]'2026-08-01T00:00:00'   # May, June, July = 3 months

    # RowCap rows crammed into a dense June span (would force Adaptive subdivision).
    $juneBurstStart = [datetime]'2026-06-10T10:00:00'
    $juneBurst = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $rowCap; $i++) {
        $juneBurst.Add([PSCustomObject]@{ Id = "june-$i"; Timestamp = $juneBurstStart.AddSeconds($i); Payload = "june-$i" })
    }
    # A few sparse rows in May and July.
    $mayRows  = @(
        [PSCustomObject]@{ Id = 'may-1';  Timestamp = [datetime]'2026-05-05T00:00:00'; Payload = 'may-1' },
        [PSCustomObject]@{ Id = 'may-2';  Timestamp = [datetime]'2026-05-20T00:00:00'; Payload = 'may-2' }
    )
    $julyRows = @(
        [PSCustomObject]@{ Id = 'july-1'; Timestamp = [datetime]'2026-07-11T00:00:00'; Payload = 'july-1' }
    )

    $m2Mock = {
        param($ctx)
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $mayRows)   { if ($r.Timestamp -ge $ctx.Start -and $r.Timestamp -lt $ctx.End) { $rows.Add($r) } }
        foreach ($r in $juneBurst) { if ($r.Timestamp -ge $ctx.Start -and $r.Timestamp -lt $ctx.End) { $rows.Add($r) } }
        foreach ($r in $julyRows)  { if ($r.Timestamp -ge $ctx.Start -and $r.Timestamp -lt $ctx.End) { $rows.Add($r) } }
        # Emulate the real API's hard cap: truncate to RowCap earliest rows.
        $ordered = $rows | Sort-Object Timestamp
        return @($ordered | Select-Object -First $rowCap)
    }.GetNewClosure()

    $outM2 = New-TempCsvPath 'm2'
    $summaryM2 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $m2Start -EndDate $m2End -TimeColumn 'Timestamp' `
        -OutputPath $outM2 -PartitionMode 'Month' -RowCap $rowCap `
        -QueryExecutor $m2Mock `
        -WarningAction SilentlyContinue

    # Expected kept rows: May(2) + June(RowCap) + July(1) = RowCap + 3.
    # With local literals the range is exactly 3 calendar months (May, Jun, Jul).
    $expectedM2 = $rowCap + 3
    $passM2 = ($summaryM2.SubdivisionEvents -eq 0) -and ($summaryM2.SaturatedWindowHit -eq $true) -and ($summaryM2.TotalRows -eq $expectedM2) -and ($summaryM2.PartitionsExecuted -eq 3)
    Add-CaseResult -Name 'm2. month mode never subdivides on saturation (SubdivisionEvents==0, SaturatedWindowHit==True, rows kept)' -Pass $passM2 `
        -Detail ("SubdivisionEvents={0}; SaturatedWindowHit={1}; TotalRows={2} (expected {3}); PartitionsExecuted={4}" -f $summaryM2.SubdivisionEvents, $summaryM2.SaturatedWindowHit, $summaryM2.TotalRows, $expectedM2, $summaryM2.PartitionsExecuted)
    Remove-Item $outM2 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'm2. month mode never subdivides on saturation (SubdivisionEvents==0, SaturatedWindowHit==True, rows kept)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE m3. Row totals equal the sum of per-window mock rows (no double count).
#   Each row falls in exactly one calendar month; half-open contiguous
#   partitions mean no boundary double-counting. Assert TotalRows == dataset
#   size and every unique Id appears exactly once.
# ===========================================================================
Write-Host ""
Write-Host "---- Case m3: row totals equal sum of per-window rows ----" -ForegroundColor Cyan
try {
    # LOCAL literals (no 'Z') so month boundaries are exact and tz-independent.
    $m3Start = [datetime]'2026-05-15T00:00:00'
    $m3End   = [datetime]'2026-08-01T00:00:00'

    $m3Data = [System.Collections.Generic.List[object]]::new()
    $m3id = 0
    # Rows at month boundaries and interiors within the range.
    $m3Times = @(
        [datetime]'2026-05-15T00:00:00',   # == range start (belongs to May window)
        [datetime]'2026-05-31T23:59:59',
        [datetime]'2026-06-01T00:00:00',   # exact month boundary -> June window
        [datetime]'2026-06-15T12:00:00',
        [datetime]'2026-06-30T23:00:00',
        [datetime]'2026-07-01T00:00:00',   # exact month boundary -> July window
        [datetime]'2026-07-15T06:00:00',
        [datetime]'2026-07-31T23:59:59'
    )
    foreach ($t in $m3Times) {
        $m3id++
        $m3Data.Add([PSCustomObject]@{ Id = $m3id; Timestamp = $t; Payload = "m3-$m3id" })
    }
    $expectedM3 = $m3Data.Count

    $m3Mock = {
        param($ctx)
        $window = $m3Data | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
        return @($window)
    }.GetNewClosure()

    $outM3 = New-TempCsvPath 'm3'
    $summaryM3 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $m3Start -EndDate $m3End -TimeColumn 'Timestamp' `
        -OutputPath $outM3 -PartitionMode 'Month' -RowCap $rowCap `
        -QueryExecutor $m3Mock

    $csvM3 = @(Import-Csv -Path $outM3)
    $uniqueM3 = @($csvM3 | ForEach-Object { $_.Id } | Sort-Object -Unique).Count
    $countM3 = $csvM3.Count
    $passM3 = ($summaryM3.TotalRows -eq $expectedM3) -and ($countM3 -eq $expectedM3) -and ($uniqueM3 -eq $expectedM3)
    Add-CaseResult -Name 'm3. row totals equal sum of per-window rows (no double count)' -Pass $passM3 `
        -Detail ("expected={0}; TotalRows={1}; csvCount={2}; unique={3}" -f $expectedM3, $summaryM3.TotalRows, $countM3, $uniqueM3)
    Remove-Item $outM3 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'm3. row totals equal sum of per-window rows (no double count)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE m4. Summary carries PartitionMode == 'Month'.
# ===========================================================================
Write-Host ""
Write-Host "---- Case m4: summary carries PartitionMode == 'Month' ----" -ForegroundColor Cyan
try {
    $m4Start = [datetime]'2026-06-01T00:00:00'
    $m4End   = [datetime]'2026-07-01T00:00:00'
    $m4Mock  = { param($ctx) return @() }

    $outM4 = New-TempCsvPath 'm4'
    $summaryM4 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $m4Start -EndDate $m4End -TimeColumn 'Timestamp' `
        -OutputPath $outM4 -PartitionMode 'Month' -RowCap $rowCap `
        -QueryExecutor $m4Mock

    $hasField = ($summaryM4.PSObject.Properties.Name -contains 'PartitionMode')
    $passM4 = $hasField -and ($summaryM4.PartitionMode -eq 'Month')
    Add-CaseResult -Name "m4. summary carries PartitionMode == 'Month'" -Pass $passM4 `
        -Detail ("hasField={0}; PartitionMode='{1}'" -f $hasField, $summaryM4.PartitionMode)
    Remove-Item $outM4 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name "m4. summary carries PartitionMode == 'Month'" -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== MONTH-MODE RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} month-mode cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
