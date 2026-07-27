<#
    Export-DefenderAdvancedHunting.UserBucket.Tests.ps1

    CREDENTIAL-FREE suite for the -UserBucketColumn Month-mode saturation
    safeguard (slice A2) of Export-DefenderAdvancedHunting.ps1.

    Uses ONLY the injectable -QueryExecutor mock seam, so NO tenant, token,
    app-registration, or network access is required. Follows the SAME plain-
    PowerShell assertion style as Export-DefenderAdvancedHunting.MonthMode.Tests.ps1
    (run, assert, print PASS/FAIL per case, exit non-zero if ANY case fails,
    fixed Get-Random -SetSeed).

    A2 contract (verified by reading the script):
      * -UserBucketColumn is a Month-mode-ONLY saturation safeguard. When a
        calendar month returns >= RowCap on its unbucketed pass, the month is
        RE-RUN split into 2, then 4, 8, ... hash buckets (doubling) until every
        bucket is under RowCap or -MaxUserBuckets is reached.
      * The mock reproduces KQL hash()'s stable-per-user property with
        bucketOf(UserId, count) = UserId % count, so every event for a given
        user lands in exactly ONE bucket (per-month dcounts stay exact).
      * Summary carries the new MaxUserBucketsUsed field alongside the existing
        A1/adaptive fields (incl. SaturatedWindowHit, PartitionMode).
      * Adaptive behaviour and the no-bucketing Month path (A1) are unchanged.

    Cases:
      u1. Bucketing keeps every row and resolves at 2 buckets (dcount exact).
      u2. Doubling to 4 buckets when 2 still saturate.
      u3. Exhaustion: a genuine mega-user keeps SaturatedWindowHit and terminates.
      u4. A1 behaviour preserved when no -UserBucketColumn is supplied.
      u5. Validation: -UserBucketColumn without a {USERFILTER} token throws.
      u6. Validation: -UserBucketColumn with -PartitionMode Adaptive throws.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed. Dataset construction below is index-based and
# deterministic on its own; this satisfies the fixed-seed requirement.
$null = Get-Random -SetSeed 20260602

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$rowCap = 10000

# Single calendar month, LOCAL literals (no 'Z') so the range is exactly one
# calendar-month partition regardless of the test runner's timezone. A 'Z'
# literal would shift into the previous month and create a sliver partition.
$monthStart = [datetime]'2026-06-01T00:00:00'
$monthEnd   = [datetime]'2026-07-01T00:00:00'
$baseJune   = [datetime]'2026-06-01T00:00:00'

# Query carrying BOTH tokens (time predicate + per-user hash bucket predicate).
$bucketQuery = 'MyTable | where {TIMEFILTER} and {USERFILTER} | project Timestamp, UserId, RowId'

# Per-case results collected here.
$caseResults = [System.Collections.Generic.List[object]]::new()

function New-TempCsvPath {
    param([string]$Tag)
    return Join-Path ([System.IO.Path]::GetTempPath()) ("ah_ubkt_{0}_{1}.csv" -f $Tag, ([guid]::NewGuid().ToString('N')))
}

function Add-CaseResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $caseResults.Add([PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

# Mock executor: reproduces the time window AND the deterministic, stable-per-
# user hash bucketing. It does NOT truncate to RowCap -- the saturation SIGNAL
# is (returned count >= RowCap), which fires whether or not rows are dropped, so
# leaving rows intact lets the tests assert exact row totals (no drops/dupes).
function New-BucketMock {
    param([System.Collections.Generic.List[object]]$Data)
    return {
        param($ctx)
        $out = [System.Collections.Generic.List[object]]::new()
        foreach ($r in $Data) {
            if ($r.Timestamp -ge $ctx.Start -and $r.Timestamp -lt $ctx.End) {
                if ($ctx.BucketCount -gt 0) {
                    if (($r.UserId % $ctx.BucketCount) -eq $ctx.BucketIndex) { $out.Add($r) }
                }
                else {
                    $out.Add($r)
                }
            }
        }
        return @($out)
    }.GetNewClosure()
}

# ===========================================================================
# CASE u1. Bucketing keeps every row and resolves at 2 buckets (dcount exact).
#   12000 rows across 2000 users (6 rows each). Unbucketed month = 12000
#   (>= RowCap) -> saturated. Split into 2 hash buckets: users %2 partitions
#   into 1000 + 1000 users = 6000 + 6000 rows, each < RowCap -> ACCEPT.
#   Assert SaturatedWindowHit==False, MaxUserBucketsUsed==2, TotalRows==12000,
#   and every user in exactly one bucket (unique RowId==12000, unique UserId==2000).
# ===========================================================================
Write-Host ""
Write-Host "---- Case u1: bucketing keeps all rows, resolves at 2 buckets ----" -ForegroundColor Cyan
try {
    $u1Data = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt 12000; $i++) {
        $u1Data.Add([PSCustomObject]@{ RowId = $i; UserId = ($i % 2000); Timestamp = $baseJune.AddMinutes($i) })
    }
    $u1Mock = New-BucketMock -Data $u1Data

    $outU1 = New-TempCsvPath 'u1'
    $summaryU1 = & $scriptPath `
        -Query $bucketQuery `
        -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
        -OutputPath $outU1 -PartitionMode 'Month' -RowCap $rowCap `
        -UserBucketColumn 'UserId' `
        -QueryExecutor $u1Mock `
        -WarningAction SilentlyContinue

    $csvU1 = @(Import-Csv -Path $outU1)
    $uniqueRowU1  = @($csvU1 | ForEach-Object { $_.RowId }  | Sort-Object -Unique).Count
    $uniqueUserU1 = @($csvU1 | ForEach-Object { $_.UserId } | Sort-Object -Unique).Count
    $passU1 = ($summaryU1.SaturatedWindowHit -eq $false) -and ($summaryU1.MaxUserBucketsUsed -eq 2) `
        -and ($summaryU1.TotalRows -eq 12000) -and ($uniqueRowU1 -eq 12000) -and ($uniqueUserU1 -eq 2000)
    Add-CaseResult -Name 'u1. bucketing keeps all rows, resolves at 2 buckets (Saturated==False, MaxUserBucketsUsed==2, no drops)' -Pass $passU1 `
        -Detail ("SaturatedWindowHit={0}; MaxUserBucketsUsed={1}; TotalRows={2}; uniqueRowId={3}; uniqueUserId={4}" -f $summaryU1.SaturatedWindowHit, $summaryU1.MaxUserBucketsUsed, $summaryU1.TotalRows, $uniqueRowU1, $uniqueUserU1)
    Remove-Item $outU1 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u1. bucketing keeps all rows, resolves at 2 buckets (Saturated==False, MaxUserBucketsUsed==2, no drops)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE u2. Doubling to 4 buckets when 2 still saturate.
#   Skewed data: even users (UserId in {0,2}) contribute 13000 rows, odd users
#   (UserId in {1,3}) contribute 6000 rows (total 19000).
#     * 2 buckets: bucket %2==0 = 13000 (>= RowCap) -> still saturated -> double.
#     * 4 buckets: %4 in {0:6500, 1:3000, 2:6500, 3:3000} -> all < RowCap -> ACCEPT.
#   Assert MaxUserBucketsUsed==4, SaturatedWindowHit==False, TotalRows==19000.
# ===========================================================================
Write-Host ""
Write-Host "---- Case u2: doubling to 4 buckets when 2 still saturate ----" -ForegroundColor Cyan
try {
    $u2Data = [System.Collections.Generic.List[object]]::new()
    $rid = 0
    # Even-heavy group: 13000 rows, UserId alternating 0 / 2 (both %2==0).
    for ($i = 0; $i -lt 13000; $i++) {
        $u2Data.Add([PSCustomObject]@{ RowId = $rid; UserId = (($i % 2) * 2); Timestamp = $baseJune.AddMinutes($i) })
        $rid++
    }
    # Odd group: 6000 rows, UserId alternating 1 / 3 (both %2==1).
    for ($j = 0; $j -lt 6000; $j++) {
        $u2Data.Add([PSCustomObject]@{ RowId = $rid; UserId = (1 + ($j % 2) * 2); Timestamp = $baseJune.AddMinutes(13000 + $j) })
        $rid++
    }
    $u2Mock = New-BucketMock -Data $u2Data

    $outU2 = New-TempCsvPath 'u2'
    $summaryU2 = & $scriptPath `
        -Query $bucketQuery `
        -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
        -OutputPath $outU2 -PartitionMode 'Month' -RowCap $rowCap `
        -UserBucketColumn 'UserId' `
        -QueryExecutor $u2Mock `
        -WarningAction SilentlyContinue

    $passU2 = ($summaryU2.MaxUserBucketsUsed -eq 4) -and ($summaryU2.SaturatedWindowHit -eq $false) -and ($summaryU2.TotalRows -eq 19000)
    Add-CaseResult -Name 'u2. doubling to 4 buckets when 2 still saturate (MaxUserBucketsUsed==4, Saturated==False, TotalRows==19000)' -Pass $passU2 `
        -Detail ("MaxUserBucketsUsed={0}; SaturatedWindowHit={1}; TotalRows={2}" -f $summaryU2.MaxUserBucketsUsed, $summaryU2.SaturatedWindowHit, $summaryU2.TotalRows)
    Remove-Item $outU2 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u2. doubling to 4 buckets when 2 still saturate (MaxUserBucketsUsed==4, Saturated==False, TotalRows==19000)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE u3. Exhaustion: a genuine mega-user keeps SaturatedWindowHit + terminates.
#   ONE user (UserId 7) with 11000 rows -> that user's bucket is >= RowCap at
#   EVERY bucket count. With -MaxUserBuckets 4 the doubling runs 2, 4, then
#   exceeds the ceiling and STOPS (no infinite loop). Rows are kept from the
#   final attempt. Assert SaturatedWindowHit==True, TotalRows==11000 (kept),
#   MaxUserBucketsUsed==4, and the run terminates.
# ===========================================================================
Write-Host ""
Write-Host "---- Case u3: exhaustion (mega-user) keeps Saturated + terminates ----" -ForegroundColor Cyan
try {
    $u3Data = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt 11000; $i++) {
        $u3Data.Add([PSCustomObject]@{ RowId = $i; UserId = 7; Timestamp = $baseJune.AddMinutes($i) })
    }
    $u3Mock = New-BucketMock -Data $u3Data

    $outU3 = New-TempCsvPath 'u3'
    $summaryU3 = & $scriptPath `
        -Query $bucketQuery `
        -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
        -OutputPath $outU3 -PartitionMode 'Month' -RowCap $rowCap `
        -UserBucketColumn 'UserId' -MaxUserBuckets 4 `
        -QueryExecutor $u3Mock `
        -WarningAction SilentlyContinue

    $passU3 = ($summaryU3.SaturatedWindowHit -eq $true) -and ($summaryU3.TotalRows -eq 11000) -and ($summaryU3.MaxUserBucketsUsed -eq 4)
    Add-CaseResult -Name 'u3. exhaustion mega-user keeps Saturated + terminates (Saturated==True, rows kept, MaxUserBucketsUsed==4)' -Pass $passU3 `
        -Detail ("SaturatedWindowHit={0}; TotalRows={1}; MaxUserBucketsUsed={2}" -f $summaryU3.SaturatedWindowHit, $summaryU3.TotalRows, $summaryU3.MaxUserBucketsUsed)
    Remove-Item $outU3 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u3. exhaustion mega-user keeps Saturated + terminates (Saturated==True, rows kept, MaxUserBucketsUsed==4)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE u4. A1 behaviour preserved when no -UserBucketColumn is supplied.
#   Same 12000-row saturated month as u1 but WITHOUT -UserBucketColumn. The
#   Month path keeps the (possibly truncated) rows and sets SaturatedWindowHit,
#   exactly like slice A1. Assert SaturatedWindowHit==True, MaxUserBucketsUsed==0,
#   rows kept (TotalRows==12000). {USERFILTER} in the query is replaced with 'true'.
# ===========================================================================
Write-Host ""
Write-Host "---- Case u4: A1 behaviour preserved without -UserBucketColumn ----" -ForegroundColor Cyan
try {
    $u4Data = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt 12000; $i++) {
        $u4Data.Add([PSCustomObject]@{ RowId = $i; UserId = ($i % 2000); Timestamp = $baseJune.AddMinutes($i) })
    }
    $u4Mock = New-BucketMock -Data $u4Data

    $outU4 = New-TempCsvPath 'u4'
    $summaryU4 = & $scriptPath `
        -Query $bucketQuery `
        -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
        -OutputPath $outU4 -PartitionMode 'Month' -RowCap $rowCap `
        -QueryExecutor $u4Mock `
        -WarningAction SilentlyContinue

    $passU4 = ($summaryU4.SaturatedWindowHit -eq $true) -and ($summaryU4.MaxUserBucketsUsed -eq 0) -and ($summaryU4.TotalRows -eq 12000)
    Add-CaseResult -Name 'u4. A1 behaviour preserved without -UserBucketColumn (Saturated==True, MaxUserBucketsUsed==0, rows kept)' -Pass $passU4 `
        -Detail ("SaturatedWindowHit={0}; MaxUserBucketsUsed={1}; TotalRows={2}" -f $summaryU4.SaturatedWindowHit, $summaryU4.MaxUserBucketsUsed, $summaryU4.TotalRows)
    Remove-Item $outU4 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u4. A1 behaviour preserved without -UserBucketColumn (Saturated==True, MaxUserBucketsUsed==0, rows kept)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE u5. Validation: -UserBucketColumn without a {USERFILTER} token throws.
# ===========================================================================
Write-Host ""
Write-Host "---- Case u5: -UserBucketColumn without {USERFILTER} throws ----" -ForegroundColor Cyan
try {
    $u5Mock = { param($ctx) return @() }
    $outU5 = New-TempCsvPath 'u5'
    $threwU5 = $false
    try {
        & $scriptPath `
            -Query 'MyTable | where {TIMEFILTER} | project Timestamp, UserId, RowId' `
            -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
            -OutputPath $outU5 -PartitionMode 'Month' -RowCap $rowCap `
            -UserBucketColumn 'UserId' `
            -QueryExecutor $u5Mock `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwU5 = $true
    }
    Add-CaseResult -Name 'u5. -UserBucketColumn without {USERFILTER} throws' -Pass $threwU5 `
        -Detail ("threw={0}" -f $threwU5)
    Remove-Item $outU5 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u5. -UserBucketColumn without {USERFILTER} throws' -Pass $false -Detail "harness error: $($_.Exception.Message)"
}

# ===========================================================================
# CASE u6. Validation: -UserBucketColumn with -PartitionMode Adaptive throws.
# ===========================================================================
Write-Host ""
Write-Host "---- Case u6: -UserBucketColumn with -PartitionMode Adaptive throws ----" -ForegroundColor Cyan
try {
    $u6Mock = { param($ctx) return @() }
    $outU6 = New-TempCsvPath 'u6'
    $threwU6 = $false
    try {
        & $scriptPath `
            -Query $bucketQuery `
            -StartDate $monthStart -EndDate $monthEnd -TimeColumn 'Timestamp' `
            -OutputPath $outU6 -PartitionMode 'Adaptive' -RowCap $rowCap `
            -UserBucketColumn 'UserId' `
            -QueryExecutor $u6Mock `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwU6 = $true
    }
    Add-CaseResult -Name 'u6. -UserBucketColumn with -PartitionMode Adaptive throws' -Pass $threwU6 `
        -Detail ("threw={0}" -f $threwU6)
    Remove-Item $outU6 -ErrorAction SilentlyContinue
}
catch {
    Add-CaseResult -Name 'u6. -UserBucketColumn with -PartitionMode Adaptive throws' -Pass $false -Detail "harness error: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== USER-BUCKET RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} user-bucket cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
