<#
    Export-DefenderAdvancedHunting.EdgeCases.Tests.ps1

    CREDENTIAL-FREE edge-case suite for Export-DefenderAdvancedHunting.ps1.

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Assertions match the real
    tool's summary field names and behavior (verified by reading the script):

        Summary fields : TotalRows, PartitionsExecuted, SubdivisionEvents,
                         MinWindowHit, ElapsedSeconds, OutputPath
        Empty output   : an empty file is written via Set-Content '' (file
                         exists, Import-Csv yields 0 rows)
        DedupeKey      : [string[]] -> Sort-Object -Property $DedupeKey -Unique
        Floor behavior : a window at/below MinWindowMinutes that still returns
                         >= RowCap sets MinWindowHit = $true, keeps the rows,
                         and does NOT subdivide further (no infinite loop)

    Pester 5 is NOT available here (a legacy Pester 3 ships in System32), so
    this suite follows the same plain-PowerShell assertion style as the
    existing Export-DefenderAdvancedHunting.Tests.ps1: run, assert, print
    PASS/FAIL per case, and exit non-zero if ANY case fails.

    Cases:
      a. Empty / zero-row export
      b. Exact partition-boundary correctness (half-open [start, end))
      c. Floor saturation - terminates (no infinite loop), MinWindowHit == True
      d. DedupeKey behavior (off by default vs. -DedupeKey Id)
      e. Multi-level subdivision recovery (15,000 rows with a dense burst)
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed (dataset construction below is index-based and
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
    return Join-Path ([System.IO.Path]::GetTempPath()) ("ah_edge_{0}_{1}.csv" -f $Tag, ([guid]::NewGuid().ToString('N')))
}

function Add-CaseResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $caseResults.Add([PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

# ===========================================================================
# CASE a. Empty / zero-row export -- REAL tool behavior on a fully-empty window.
#   Mock returns 0 rows for EVERY window. This exercises a code path the 25k
#   test never reaches (that dataset has rows in every partition).
#
#   VERIFIED tool behavior (NOT an assumption): a window that returns no rows
#   causes the exporter's internal $executeWindow scriptblock to return an
#   empty array, which the call site now re-wraps with @(...) so an empty
#   window yields an empty array ($rows.Count == 0) instead of unrolling to
#   $null. The queue drains cleanly, and the output stage writes a header-only
#   CSV when -OutputColumns is supplied. The real
#   Microsoft Graph executor returns @() on no results too, so this is the
#   tool's genuine empty-window behavior on the live path as well.
#
#   Per the audit instruction, this case asserts what the script ACTUALLY does
#   after the fix: it does NOT throw, returns a summary with TotalRows == 0,
#   executes at least one partition, and leaves an empty CSV artifact at the
#   output path.
# ===========================================================================
Write-Host ""
Write-Host "---- Case a: empty / zero-row export (clean no-throw, TotalRows==0) ----" -ForegroundColor Cyan
$emptyMock = { param($ctx) return @() }
$outA = New-TempCsvPath 'empty'
$threwA = $false
$msgA = ''
$summaryA = $null
try {
    $summaryA = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate ([datetime]'2026-06-01T00:00:00Z') `
        -EndDate   ([datetime]'2026-06-02T00:00:00Z') `
        -TimeColumn 'Timestamp' `
        -OutputPath $outA `
        -OutputColumns @('Timestamp','Id','Payload') `
        -RowCap $rowCap `
        -QueryExecutor $emptyMock
}
catch {
    $threwA = $true
    $msgA = $_.Exception.Message
}
$artifactA = Test-Path $outA
$totalRowsA = if ($summaryA) { $summaryA.TotalRows } else { -1 }
$partsA = if ($summaryA) { $summaryA.PartitionsExecuted } else { -1 }
$csvRowsA = if ($artifactA) { @(Import-Csv -Path $outA).Count } else { -1 }
$headerA = if ($artifactA) { @(Get-Content -LiteralPath $outA)[0] } else { '' }
# Reality after fix: no throw; summary TotalRows == 0; at least one partition
# executed; an (empty) CSV artifact exists at the output path with 0 data rows.
$passA = (-not $threwA) -and ($null -ne $summaryA) -and ($totalRowsA -eq 0) -and ($partsA -ge 1) -and $artifactA -and ($csvRowsA -eq 0) -and ($headerA -ceq '"Timestamp","Id","Payload"')
Add-CaseResult -Name 'a. empty/zero-row export (no throw; TotalRows==0; header-only CSV written)' -Pass $passA `
    -Detail ("threw={0}; TotalRows={1}; PartitionsExecuted={2}; artifact={3}; csvRows={4}; header='{5}'; msg='{6}'" -f $threwA, $totalRowsA, $partsA, $artifactA, $csvRowsA, $headerA, $msgA)
Remove-Item $outA -ErrorAction SilentlyContinue

# ===========================================================================
# CASE b. Exact partition-boundary correctness (half-open [start, end)).
#   Several rows sit EXACTLY on 12h partition boundaries. With half-open
#   intervals, a boundary row at T belongs to the window starting at T
#   (>= T), never the window ending at T (< T). Assert every unique id
#   appears EXACTLY once and output count == synthetic count.
# ===========================================================================
Write-Host ""
Write-Host "---- Case b: exact partition-boundary correctness ----" -ForegroundColor Cyan
try {
    $bStart = [datetime]'2026-06-01T00:00:00Z'
    $bEnd   = [datetime]'2026-06-04T00:00:00Z'   # 72h -> 12h partitions at every 00:00 and 12:00
    $bData  = [System.Collections.Generic.List[object]]::new()
    $bid = 0

    # Rows placed EXACTLY on internal 12h boundaries within [start, end).
    # (The exclusive end boundary 2026-06-04T00:00 is intentionally omitted.)
    $boundaryTimes = @(
        [datetime]'2026-06-01T00:00:00Z',   # == range start
        [datetime]'2026-06-01T12:00:00Z',
        [datetime]'2026-06-02T00:00:00Z',
        [datetime]'2026-06-02T12:00:00Z',
        [datetime]'2026-06-03T00:00:00Z',
        [datetime]'2026-06-03T12:00:00Z'
    )
    foreach ($t in $boundaryTimes) {
        $bid++
        $bData.Add([PSCustomObject]@{ Id = $bid; Timestamp = $t; Payload = "boundary-$bid" })
    }

    # A handful of interior (non-boundary) rows so the set is not all-boundaries.
    $interiorOffsetsHours = @(3, 7, 15, 27, 39, 51, 63, 70)
    foreach ($h in $interiorOffsetsHours) {
        $bid++
        $bData.Add([PSCustomObject]@{ Id = $bid; Timestamp = $bStart.AddHours($h); Payload = "interior-$bid" })
    }

    $bExpected = $bData.Count
    $bMock = {
        param($ctx)
        $window  = $bData | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
        $ordered = $window | Sort-Object Timestamp
        return @($ordered | Select-Object -First $rowCap)
    }.GetNewClosure()

    $outB = New-TempCsvPath 'boundary'
    $summaryB = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $bStart -EndDate $bEnd -TimeColumn 'Timestamp' `
        -OutputPath $outB -InitialPartitionHours 12 -RowCap $rowCap `
        -QueryExecutor $bMock

    $csvB = @(Import-Csv -Path $outB)
    $uniqueB = @($csvB | ForEach-Object { $_.Id } | Sort-Object -Unique).Count
    $countB = $csvB.Count
    $passB = ($countB -eq $bExpected) -and ($uniqueB -eq $bExpected) -and ($summaryB.TotalRows -eq $bExpected)
    Add-CaseResult -Name 'b. exact partition-boundary correctness (each boundary row exactly once)' -Pass $passB `
        -Detail ("expected={0}; csvCount={1}; unique={2}; TotalRows={3}" -f $bExpected, $countB, $uniqueB, $summaryB.TotalRows)
    Remove-Item $outB -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'b. exact partition-boundary correctness (each boundary row exactly once)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c. Floor saturation - proves the MinWindowMinutes floor stops recursion.
#   A mock returns EXACTLY RowCap rows for EVERY window no matter how small.
#   Run inside a background job guarded by a 60s wall-clock timeout so a
#   regression that reintroduced infinite subdivision would FAIL rather than
#   hang the suite. RowCap is lowered to 50 to keep the (bounded) binary
#   subdivision tree tiny; the tool honors -RowCap so behavior is identical.
#   Assert: run terminates, MinWindowHit == True, floor-window rows kept.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c: floor saturation (no infinite loop) ----" -ForegroundColor Cyan
try {
    $floorRowCap = 50
    $timeoutSec = 60

    $job = Start-Job -ScriptBlock {
        param($scriptPath, $floorRowCap)
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # Every window returns EXACTLY $floorRowCap rows, all crammed into a
        # sub-second span, regardless of the window's size -> perpetual
        # saturation that only the floor can stop.
        $crammed = 1..$floorRowCap | ForEach-Object {
            [PSCustomObject]@{ Id = $_; Timestamp = [datetime]'2026-06-01T00:00:00Z'; Payload = "cram-$_" }
        }
        $mock = { param($ctx) return @($crammed) }.GetNewClosure()

        $out = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_edge_floor_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
        $summary = & $scriptPath `
            -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
            -StartDate ([datetime]'2026-06-01T00:00:00Z') `
            -EndDate   ([datetime]'2026-06-01T00:04:00Z') `
            -TimeColumn 'Timestamp' `
            -OutputPath $out `
            -InitialPartitionHours 12 `
            -MinWindowMinutes 1 `
            -RowCap $floorRowCap `
            -QueryExecutor $mock `
            -WarningAction SilentlyContinue

        Remove-Item $out -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            TotalRows          = $summary.TotalRows
            MinWindowHit       = $summary.MinWindowHit
            PartitionsExecuted = $summary.PartitionsExecuted
        }
    } -ArgumentList $scriptPath, $floorRowCap

    $completed = Wait-Job -Job $job -Timeout $timeoutSec
    if ($null -eq $completed) {
        # Timed out -> potential infinite loop. Stop the job and FAIL the case.
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Add-CaseResult -Name 'c. floor saturation terminates (no infinite loop) + MinWindowHit==True' -Pass $false `
            -Detail ("did not terminate within {0}s (possible infinite subdivision)" -f $timeoutSec)
    }
    else {
        $r = Receive-Job -Job $job
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $passC = ($r.MinWindowHit -eq $true) -and ($r.TotalRows -gt 0)
        Add-CaseResult -Name 'c. floor saturation terminates (no infinite loop) + MinWindowHit==True' -Pass $passC `
            -Detail ("terminated; MinWindowHit={0}; TotalRows={1}; PartitionsExecuted={2}" -f $r.MinWindowHit, $r.TotalRows, $r.PartitionsExecuted)
    }
}
catch {
    Add-CaseResult -Name 'c. floor saturation terminates (no infinite loop) + MinWindowHit==True' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE d. DedupeKey behavior.
#   The mock returns the in-window unique rows PLUS one constant duplicate row
#   (same Id) in EVERY window, so the merged set contains duplicates. Run once
#   WITHOUT -DedupeKey (duplicates present) and once WITH -DedupeKey Id
#   (duplicates collapsed). Counts kept small so no subdivision occurs.
# ===========================================================================
Write-Host ""
Write-Host "---- Case d: DedupeKey behavior ----" -ForegroundColor Cyan
try {
    $dStart = [datetime]'2026-06-01T00:00:00Z'
    $dEnd   = [datetime]'2026-06-02T00:00:00Z'   # 24h -> 2 partitions of 12h
    $dupId  = 999999

    $dUnique = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt 10; $i++) {
        $dUnique.Add([PSCustomObject]@{ Id = ($i + 1); Timestamp = $dStart.AddHours($i * 2 + 1); Payload = "u-$($i + 1)" })
    }
    $constantRow = [PSCustomObject]@{ Id = $dupId; Timestamp = $dStart.AddHours(6); Payload = 'CONSTANT-DUP' }

    $dMock = {
        param($ctx)
        $window = $dUnique | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
        # Append the constant duplicate to EVERY window's result.
        return @(@($window) + @($constantRow))
    }.GetNewClosure()

    # --- run 1: no dedup ---
    $outD1 = New-TempCsvPath 'dedupe_off'
    $summaryD1 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $dStart -EndDate $dEnd -TimeColumn 'Timestamp' `
        -OutputPath $outD1 -InitialPartitionHours 12 -RowCap $rowCap `
        -QueryExecutor $dMock
    $csvD1 = @(Import-Csv -Path $outD1)
    $dupCopiesOff = @($csvD1 | Where-Object { $_.Id -eq "$dupId" }).Count

    # --- run 2: dedup by Id ---
    $outD2 = New-TempCsvPath 'dedupe_on'
    $summaryD2 = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $dStart -EndDate $dEnd -TimeColumn 'Timestamp' `
        -OutputPath $outD2 -InitialPartitionHours 12 -RowCap $rowCap `
        -DedupeKey 'Id' `
        -QueryExecutor $dMock
    $csvD2 = @(Import-Csv -Path $outD2)
    $dupCopiesOn = @($csvD2 | Where-Object { $_.Id -eq "$dupId" }).Count
    $uniqueOn = @($csvD2 | ForEach-Object { $_.Id } | Sort-Object -Unique).Count
    $totalOn = $csvD2.Count

    $passD = ($dupCopiesOff -ge 2) -and ($dupCopiesOn -eq 1) -and ($uniqueOn -eq $totalOn)
    Add-CaseResult -Name 'd. DedupeKey behavior (dupes present without key, collapsed with -DedupeKey Id)' -Pass $passD `
        -Detail ("dupCopies(off)={0}; dupCopies(on)={1}; unique(on)={2}; total(on)={3}" -f $dupCopiesOff, $dupCopiesOn, $uniqueOn, $totalOn)
    Remove-Item $outD1 -ErrorAction SilentlyContinue
    Remove-Item $outD2 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'd. DedupeKey behavior (dupes present without key, collapsed with -DedupeKey Id)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE e. Multi-level subdivision recovery.
#   A smaller variant of the 25k test: 15,000 rows with a dense burst that
#   forces subdivision. Assert all unique ids recovered, 0 duplicates, and
#   SubdivisionEvents >= 1. Mock truncates to RowCap earliest rows exactly as
#   the real API does.
# ===========================================================================
Write-Host ""
Write-Host "---- Case e: multi-level subdivision recovery (15,000 rows) ----" -ForegroundColor Cyan
try {
    $eStart = [datetime]'2026-06-01T00:00:00Z'
    $eEnd   = [datetime]'2026-06-04T00:00:00Z'   # 3-day half-open range
    $eData  = [System.Collections.Generic.List[object]]::new()
    $eid = 0

    # 5,000 rows spread uniformly across the whole range.
    $spreadCount = 5000
    $totalSeconds = ($eEnd - $eStart).TotalSeconds
    for ($i = 0; $i -lt $spreadCount; $i++) {
        $eid++
        $offset = ($totalSeconds * $i) / $spreadCount
        $eData.Add([PSCustomObject]@{ Id = $eid; Timestamp = $eStart.AddSeconds($offset); Payload = "spread-$eid" })
    }

    # 10,000 rows packed into a dense 1-hour burst -> forces repeated subdivision.
    $burstStart = [datetime]'2026-06-02T10:00:00Z'
    $burstSpanSeconds = 1 * 3600
    $burstCount = 10000
    for ($i = 0; $i -lt $burstCount; $i++) {
        $eid++
        $offset = ($burstSpanSeconds * $i) / $burstCount
        $eData.Add([PSCustomObject]@{ Id = $eid; Timestamp = $burstStart.AddSeconds($offset); Payload = "burst-$eid" })
    }

    $eExpected = $eData.Count   # 15000
    $eMock = {
        param($ctx)
        $window  = $eData | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
        $ordered = $window | Sort-Object Timestamp
        return @($ordered | Select-Object -First $rowCap)
    }.GetNewClosure()

    $outE = New-TempCsvPath 'subdivide'
    $summaryE = & $scriptPath `
        -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
        -StartDate $eStart -EndDate $eEnd -TimeColumn 'Timestamp' `
        -OutputPath $outE -InitialPartitionHours 12 -RowCap $rowCap -TargetRowsPerWindow 8000 -MinWindowMinutes 1 `
        -QueryExecutor $eMock

    $csvE = @(Import-Csv -Path $outE)
    $uniqueE = @($csvE | ForEach-Object { $_.Id } | Sort-Object -Unique).Count
    $countE = $csvE.Count
    $dupE = $countE - $uniqueE
    $passE = ($uniqueE -eq $eExpected) -and ($dupE -eq 0) -and ($summaryE.SubdivisionEvents -ge 1) -and ($summaryE.TotalRows -eq $eExpected)
    Add-CaseResult -Name 'e. multi-level subdivision recovery (all unique ids, 0 dupes, SubdivisionEvents>=1)' -Pass $passE `
        -Detail ("expected={0}; csvCount={1}; unique={2}; dupes={3}; SubdivisionEvents={4}" -f $eExpected, $countE, $uniqueE, $dupE, $summaryE.SubdivisionEvents)
    Remove-Item $outE -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'e. multi-level subdivision recovery (all unique ids, 0 dupes, SubdivisionEvents>=1)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== EDGE-CASE RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} edge cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
