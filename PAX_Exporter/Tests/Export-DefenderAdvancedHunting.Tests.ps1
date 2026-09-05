<#
    Export-DefenderAdvancedHunting.Tests.ps1

    CREDENTIAL-FREE, deterministic test proving the exporter recovers ALL rows
    beyond the conservative 10,000-row partition threshold via adaptive time-slicing.

    Strategy:
      * Build a synthetic 25,000-row dataset with unique Ids and non-uniform
        Timestamps, including a dense burst so subdivision is forced.
      * Inject a -QueryExecutor mock that filters to the half-open window and
        returns AT MOST RowCap rows ordered by Timestamp, simulating a threshold-
        reaching response so the algorithm is forced to subdivide.
      * Assert all 25,000 unique Ids are recovered, none duplicated, at least
        one subdivision occurred, and no partition was truncated at the floor.

    Uses Pester if available; otherwise falls back to plain assertions.
    Exits 0 on success, non-zero on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\Export-DefenderAdvancedHunting.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

# ---------------------------------------------------------------------------
# Synthetic dataset (25,000 rows)
# ---------------------------------------------------------------------------
$rangeStart = [datetime]'2026-06-01T00:00:00Z'
$rangeEnd   = [datetime]'2026-06-08T00:00:00Z'   # 7-day half-open range
$rowCap     = 10000

$dataset = [System.Collections.Generic.List[object]]::new()
$id = 0

# 10,000 rows spread uniformly across the whole 7-day range.
$spreadCount = 10000
$totalSeconds = ($rangeEnd - $rangeStart).TotalSeconds
for ($i = 0; $i -lt $spreadCount; $i++) {
    $id++
    $offset = ($totalSeconds * $i) / $spreadCount
    $dataset.Add([PSCustomObject]@{
        Id        = $id
        Timestamp = $rangeStart.AddSeconds($offset)
        Payload   = "spread-$id"
    })
}

# 15,000 rows packed into a dense 2-hour burst -> forces repeated subdivision.
$burstStart = [datetime]'2026-06-03T10:00:00Z'
$burstSpanSeconds = 2 * 3600
$burstCount = 15000
for ($i = 0; $i -lt $burstCount; $i++) {
    $id++
    $offset = ($burstSpanSeconds * $i) / $burstCount
    $dataset.Add([PSCustomObject]@{
        Id        = $id
        Timestamp = $burstStart.AddSeconds($offset)
        Payload   = "burst-$id"
    })
}

$expectedTotal = $dataset.Count   # 25000

# ---------------------------------------------------------------------------
# Mock executor: half-open filter + hard RowCap truncation (earliest rows).
# ---------------------------------------------------------------------------
$mock = {
    param($ctx)
    $window = $dataset | Where-Object { $_.Timestamp -ge $ctx.Start -and $_.Timestamp -lt $ctx.End }
    $ordered = $window | Sort-Object Timestamp
    return @($ordered | Select-Object -First $rowCap)
}.GetNewClosure()

# ---------------------------------------------------------------------------
# Run the exporter over the full range with the mock.
# ---------------------------------------------------------------------------
$outCsv = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_export_test_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

$summary = & $scriptPath `
    -Query 'CloudAppEvents | where {TIMEFILTER} | project Timestamp, Id, Payload' `
    -StartDate $rangeStart `
    -EndDate   $rangeEnd `
    -TimeColumn 'Timestamp' `
    -OutputPath $outCsv `
    -InitialPartitionHours 12 `
    -RowCap $rowCap `
    -TargetRowsPerWindow 8000 `
    -MinWindowMinutes 1 `
    -QueryExecutor $mock

# ---------------------------------------------------------------------------
# Read back the CSV and compute verification facts.
# ---------------------------------------------------------------------------
$csvRows = @(Import-Csv -Path $outCsv)
$ids = $csvRows | ForEach-Object { $_.Id }
$uniqueIds = $ids | Sort-Object -Unique
$uniqueCount = @($uniqueIds).Count
$csvCount = $csvRows.Count
$dupCount = $csvCount - $uniqueCount

# ---------------------------------------------------------------------------
# Checks (name -> boolean)
# ---------------------------------------------------------------------------
$checks = @(
    @{ Name = "All $expectedTotal unique Ids recovered";        Pass = ($uniqueCount -eq $expectedTotal) }
    @{ Name = "No duplicate Ids in output";                     Pass = ($dupCount -eq 0) }
    @{ Name = "At least one subdivision event occurred";        Pass = ($summary.SubdivisionEvents -ge 1) }
    @{ Name = "No accepted/kept partition truncated at floor";  Pass = ($summary.MinWindowHit -eq $false) }
    @{ Name = "Summary TotalRows equals expected";              Pass = ($summary.TotalRows -eq $expectedTotal) }
)

Write-Host ""
Write-Host "==== TEST RESULTS ===="
Write-Host ("Expected total rows : {0}" -f $expectedTotal)
Write-Host ("CSV row count       : {0}" -f $csvCount)
Write-Host ("Unique Id count     : {0}" -f $uniqueCount)
Write-Host ("Duplicate count     : {0}" -f $dupCount)
Write-Host ("PartitionsExecuted  : {0}" -f $summary.PartitionsExecuted)
Write-Host ("SubdivisionEvents   : {0}" -f $summary.SubdivisionEvents)
Write-Host ("MinWindowHit        : {0}" -f $summary.MinWindowHit)
Write-Host ""

# Only use the Pester path when Pester 5+ (New-PesterConfiguration API) is present.
$pester5 = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.0.0' } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($pester5) {
    # Attempt the Pester 5 path, but only trust it if the v5 config API is
    # genuinely loaded. Legacy Pester (3.x shipped in System32) can shadow the
    # import; on any failure we fall through to the reliable plain assertions.
    $usePester = $false
    try {
        Remove-Module Pester -Force -ErrorAction SilentlyContinue
        Import-Module Pester -MinimumVersion 5.0.0 -Force -ErrorAction Stop
        if (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue) {
            $usePester = $true
        }
    }
    catch {
        $usePester = $false
    }

    if ($usePester) {
        $localChecks = $checks
        $container = {
            Describe 'Export-DefenderAdvancedHunting adaptive time-slicing' {
                It '<Name>' -ForEach $localChecks {
                    $Pass | Should -BeTrue
                }
            }
        }
        $config = New-PesterConfiguration
        $config.Run.ScriptBlock = $container
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Detailed'
        $result = Invoke-Pester -Configuration $config
        if ($result.FailedCount -gt 0) {
            Write-Host "OVERALL: FAIL ($($result.FailedCount) failed)" -ForegroundColor Red
            Remove-Item $outCsv -ErrorAction SilentlyContinue
            exit 1
        }
        Write-Host "OVERALL: PASS (Pester, $($result.PassedCount) passed)" -ForegroundColor Green
        Remove-Item $outCsv -ErrorAction SilentlyContinue
        exit 0
    }
    else {
        Write-Host "(Pester 5+ import unusable - using plain-PowerShell assertions)" -ForegroundColor Yellow
    }
}

# Plain-PowerShell assertion fallback (also used when Pester 5 is unusable).
Write-Host "(Running plain-PowerShell assertions)" -ForegroundColor Yellow
$failed = 0
foreach ($c in $checks) {
    if ($c.Pass) {
        Write-Host ("PASS: {0}" -f $c.Name) -ForegroundColor Green
    }
    else {
        Write-Host ("FAIL: {0}" -f $c.Name) -ForegroundColor Red
        $failed++
    }
}
Remove-Item $outCsv -ErrorAction SilentlyContinue
if ($failed -gt 0) {
    Write-Host ("OVERALL: FAIL ({0} failed)" -f $failed) -ForegroundColor Red
    exit 1
}
Write-Host "OVERALL: PASS (plain assertions, all checks green)" -ForegroundColor Green
exit 0
