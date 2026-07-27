<#
    Collect-AICopilotUsage.Tests.ps1

    CREDENTIAL-FREE test for the Section-A A2 Purview collector
    Collect-AICopilotUsage.ps1 (ai_copilot_usage_graph.csv).

    Exercises the collector through the injectable -SearchExecutor mock seam, so
    NO Exchange Online connection, ExchangeOnlineManagement module, tenant,
    token, or network access is required. Follows the SAME plain-PowerShell
    assertion style as Collect-AISolutionsGraph.Tests.ps1 (run, assert, print
    PASS/FAIL per case, exit non-zero if ANY case fails, fixed
    Get-Random -SetSeed).

    Each mock scriptblock is captured via .GetNewClosure() over LOCAL
    List[object] fixtures (reference-type Lists shared with the closure). The
    mock serves audit records PER PAGE keyed off $ctx.Page, and each record's
    .AuditData is a JSON STRING (built via ConvertTo-Json -Compress) so the real
    ConvertFrom-Json parse path in the collector is exercised.

    Cases:
      c1. Header byte-exact -- 2 users aggregated; assert the CSV first line
          EQUALS the exact 11-column header and the row count.
      c2. Workload mapping -- one user/month across MicrosoftTeams, Word, Excel,
          Outlook, PowerPoint, Bing, M365Chat, Microsoft365 + unknown 'Loop';
          assert per-surface sums (Bing+M365Chat+Microsoft365 fold into Chat) and
          that 'Loop' is excluded from every surface AND from TotalPrompts.
      c3. Prompt counting -- Prompts present (Count used) vs absent (defaults to
          1); assert per-surface sum and TotalPrompts reflect Count-or-1.
      c4. Month + activity aggregation -- one user, two dates same month + a
          record in a different month; assert 2 rows, ActiveDays = distinct-date
          count, LastActivityDate = max date (yyyy-MM-dd).
      c5. Pagination -- -PageSize 2; page0=2 records, page1=1 record, else empty;
          assert EventsParsed=3 and the loop terminated.
      c6. Zero events -- empty mock; assert the file exists, its only line is the
          byte-exact header, and summary RowCount=0.
      c7. Auth guard -- no -SearchExecutor -> THROWS (Search-UnifiedAuditLog
          absent / not connected).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed.
$null = Get-Random -SetSeed 20260724

$scriptPath = Join-Path $PSScriptRoot '..\Collect-AICopilotUsage.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

# Exact expected byte-for-byte 11-column header.
$expectedHeader = 'UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate'

# Per-case results collected here; each entry: @{ Name; Pass; Detail }
$caseResults = [System.Collections.Generic.List[object]]::new()

function Add-CaseResult {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $caseResults.Add([PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1}{2}" -f $tag, $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

function New-TempOutDir {
    param([string]$Tag)
    $dir = Join-Path $env:TEMP ("ah_cu_{0}_{1}" -f $Tag, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function New-CuRec {
    # Build a single audit record whose .AuditData is a JSON STRING (so the
    # collector's real ConvertFrom-Json path is exercised). $Prompts $null ->
    # omit CopilotEventData entirely (collector defaults the count to 1).
    param(
        [string]$UserId,
        [string]$CreationDate,
        [string]$Workload,
        [object]$Prompts = $null
    )
    $ht = [ordered]@{ UserId = $UserId; CreationDate = $CreationDate; Workload = $Workload }
    if ($null -ne $Prompts) { $ht['CopilotEventData'] = @{ Prompts = $Prompts } }
    $json = ([pscustomobject]$ht) | ConvertTo-Json -Compress -Depth 5
    return [pscustomobject]@{ AuditData = $json }
}

# ===========================================================================
# CASE c1. Header byte-exact + row count (2 users aggregated).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c1: header byte-exact + row count ----" -ForegroundColor Cyan
try {
    $c1Recs = [System.Collections.Generic.List[object]]::new()
    $c1Recs.Add((New-CuRec -UserId 'a@x' -CreationDate '2026-05-04T10:00:00Z' -Workload 'Word'  -Prompts @(1, 2)))
    $c1Recs.Add((New-CuRec -UserId 'a@x' -CreationDate '2026-05-06T10:00:00Z' -Workload 'Word'))
    $c1Recs.Add((New-CuRec -UserId 'b@x' -CreationDate '2026-05-07T10:00:00Z' -Workload 'Teams' -Prompts @(1)))
    $c1Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c1Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC1 = New-TempOutDir 'c1'
    & $scriptPath -OutputDirectory $outC1 -SearchExecutor $c1Mock -WarningAction SilentlyContinue | Out-Null

    $path = Join-Path $outC1 'ai_copilot_usage_graph.csv'
    $firstLine = (Get-Content -LiteralPath $path)[0]
    $rows = @(Import-Csv -LiteralPath $path)
    $passC1 = ($firstLine -ceq $expectedHeader) -and ($rows.Count -eq 2)
    Add-CaseResult -Name 'c1. header byte-exact + 2 aggregated rows' -Pass $passC1 `
        -Detail ("headerMatch={0}; rows={1}" -f ($firstLine -ceq $expectedHeader), $rows.Count)
}
catch {
    Add-CaseResult -Name 'c1. header byte-exact + 2 aggregated rows' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c2. Workload mapping (Bing+M365Chat+Microsoft365 -> Chat; Loop excluded).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c2: workload mapping + unknown exclusion ----" -ForegroundColor Cyan
try {
    $c2Recs = [System.Collections.Generic.List[object]]::new()
    foreach ($wl in @('MicrosoftTeams', 'Word', 'Excel', 'Outlook', 'PowerPoint', 'Bing', 'M365Chat', 'Microsoft365', 'Loop')) {
        $c2Recs.Add((New-CuRec -UserId 'c2@x' -CreationDate '2026-05-04T10:00:00Z' -Workload $wl))
    }
    $c2Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c2Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC2 = New-TempOutDir 'c2'
    & $scriptPath -OutputDirectory $outC2 -SearchExecutor $c2Mock -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outC2 'ai_copilot_usage_graph.csv'))
    $row = $rows | Where-Object { $_.UserPrincipalName -eq 'c2@x' }
    # Each record = 1 prompt (no CopilotEventData). Chat = Bing+M365Chat+Microsoft365 = 3.
    # Total = Teams1+Word1+Excel1+Outlook1+PowerPoint1+Chat3 = 8 (Loop excluded).
    $passC2 = ($rows.Count -eq 1) -and ($null -ne $row) -and `
              ([int]$row.TeamsPrompts -eq 1) -and ([int]$row.WordPrompts -eq 1) -and `
              ([int]$row.ExcelPrompts -eq 1) -and ([int]$row.OutlookPrompts -eq 1) -and `
              ([int]$row.PowerPointPrompts -eq 1) -and ([int]$row.ChatPrompts -eq 3) -and `
              ([int]$row.TotalPrompts -eq 8)
    Add-CaseResult -Name 'c2. workload mapping + Loop excluded from surfaces and Total' -Pass $passC2 `
        -Detail ("teams={0};word={1};excel={2};outlook={3};ppt={4};chat={5};total={6}" -f `
            $(if ($row) { $row.TeamsPrompts } else { 'n/a' }), $(if ($row) { $row.WordPrompts } else { 'n/a' }), `
            $(if ($row) { $row.ExcelPrompts } else { 'n/a' }), $(if ($row) { $row.OutlookPrompts } else { 'n/a' }), `
            $(if ($row) { $row.PowerPointPrompts } else { 'n/a' }), $(if ($row) { $row.ChatPrompts } else { 'n/a' }), `
            $(if ($row) { $row.TotalPrompts } else { 'n/a' }))
}
catch {
    Add-CaseResult -Name 'c2. workload mapping + Loop excluded from surfaces and Total' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c3. Prompt counting (Count used when present; defaults to 1 when absent).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c3: prompt counting (Count-or-1) ----" -ForegroundColor Cyan
try {
    $c3Recs = [System.Collections.Generic.List[object]]::new()
    $c3Recs.Add((New-CuRec -UserId 'c3@x' -CreationDate '2026-05-04T10:00:00Z' -Workload 'Word' -Prompts @(1, 2, 3)))  # 3
    $c3Recs.Add((New-CuRec -UserId 'c3@x' -CreationDate '2026-05-05T10:00:00Z' -Workload 'Word'))                       # 1
    $c3Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c3Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC3 = New-TempOutDir 'c3'
    & $scriptPath -OutputDirectory $outC3 -SearchExecutor $c3Mock -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outC3 'ai_copilot_usage_graph.csv'))
    $row = $rows | Where-Object { $_.UserPrincipalName -eq 'c3@x' }
    # WordPrompts = 3 + 1 = 4; Total = 4.
    $passC3 = ($null -ne $row) -and ([int]$row.WordPrompts -eq 4) -and ([int]$row.TotalPrompts -eq 4)
    Add-CaseResult -Name 'c3. prompt counting reflects Count-or-1 (Word=4, Total=4)' -Pass $passC3 `
        -Detail ("word={0}; total={1}" -f $(if ($row) { $row.WordPrompts } else { 'n/a' }), $(if ($row) { $row.TotalPrompts } else { 'n/a' }))
}
catch {
    Add-CaseResult -Name 'c3. prompt counting reflects Count-or-1 (Word=4, Total=4)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c4. Month + activity aggregation.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c4: month + activity aggregation ----" -ForegroundColor Cyan
try {
    $c4Recs = [System.Collections.Generic.List[object]]::new()
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationDate '2026-05-04T10:00:00Z' -Workload 'Word'))
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationDate '2026-05-10T14:00:00Z' -Workload 'Word'))
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationDate '2026-06-02T09:00:00Z' -Workload 'Word'))
    $c4Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c4Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC4 = New-TempOutDir 'c4'
    & $scriptPath -OutputDirectory $outC4 -SearchExecutor $c4Mock -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outC4 'ai_copilot_usage_graph.csv'))
    $mayRow = $rows | Where-Object { $_.YearMonth -eq '2026-05' }
    $junRow = $rows | Where-Object { $_.YearMonth -eq '2026-06' }
    $passC4 = ($rows.Count -eq 2) -and ($null -ne $mayRow) -and ($null -ne $junRow) -and `
              ([int]$mayRow.ActiveDays -eq 2) -and ($mayRow.LastActivityDate -eq '2026-05-10') -and `
              ([int]$junRow.ActiveDays -eq 1) -and ($junRow.LastActivityDate -eq '2026-06-02')
    Add-CaseResult -Name 'c4. 2 month rows; ActiveDays distinct; LastActivityDate max' -Pass $passC4 `
        -Detail ("rows={0}; may(days={1},last={2}); jun(days={3},last={4})" -f $rows.Count, `
            $(if ($mayRow) { $mayRow.ActiveDays } else { 'n/a' }), $(if ($mayRow) { $mayRow.LastActivityDate } else { 'n/a' }), `
            $(if ($junRow) { $junRow.ActiveDays } else { 'n/a' }), $(if ($junRow) { $junRow.LastActivityDate } else { 'n/a' }))
}
catch {
    Add-CaseResult -Name 'c4. 2 month rows; ActiveDays distinct; LastActivityDate max' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c5. Pagination (-PageSize 2; page0=2, page1=1, else empty).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c5: pagination over pages via `$ctx.Page ----" -ForegroundColor Cyan
try {
    $c5Page0 = [System.Collections.Generic.List[object]]::new()
    $c5Page0.Add((New-CuRec -UserId 'p0a@x' -CreationDate '2026-05-04T10:00:00Z' -Workload 'Word'))
    $c5Page0.Add((New-CuRec -UserId 'p0b@x' -CreationDate '2026-05-05T10:00:00Z' -Workload 'Word'))
    $c5Page1 = [System.Collections.Generic.List[object]]::new()
    $c5Page1.Add((New-CuRec -UserId 'p1a@x' -CreationDate '2026-05-06T10:00:00Z' -Workload 'Word'))
    $c5Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c5Page0.ToArray() }
        elseif ($ctx.Page -eq 1) { return $c5Page1.ToArray() }
        return @()
    }.GetNewClosure()

    $outC5 = New-TempOutDir 'c5'
    $summary = & $scriptPath -OutputDirectory $outC5 -SearchExecutor $c5Mock -PageSize 2 -WarningAction SilentlyContinue
    $rows = @(Import-Csv -LiteralPath (Join-Path $outC5 'ai_copilot_usage_graph.csv'))
    $passC5 = ([int]$summary.CopilotUsage.EventsParsed -eq 3) -and ($rows.Count -eq 3)
    Add-CaseResult -Name 'c5. pagination parses all 3 events across pages' -Pass $passC5 `
        -Detail ("eventsParsed={0}; rows={1}" -f $summary.CopilotUsage.EventsParsed, $rows.Count)
}
catch {
    Add-CaseResult -Name 'c5. pagination parses all 3 events across pages' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c6. Zero events -> header-only file, RowCount=0.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c6: zero events -> header-only file ----" -ForegroundColor Cyan
try {
    $c6Mock = {
        param($ctx)
        return @()
    }.GetNewClosure()

    $outC6 = New-TempOutDir 'c6'
    $summary = & $scriptPath -OutputDirectory $outC6 -SearchExecutor $c6Mock -WarningAction SilentlyContinue
    $path = Join-Path $outC6 'ai_copilot_usage_graph.csv'
    $exists = Test-Path $path
    $lines = @(Get-Content -LiteralPath $path | Where-Object { $_.Trim().Length -gt 0 })
    $passC6 = $exists -and ($lines.Count -eq 1) -and ($lines[0] -ceq $expectedHeader) -and `
              ([int]$summary.CopilotUsage.RowCount -eq 0)
    Add-CaseResult -Name 'c6. zero events -> header-only file, RowCount=0' -Pass $passC6 `
        -Detail ("exists={0}; lines={1}; headerOk={2}; rowCount={3}" -f $exists, $lines.Count, ($lines.Count -ge 1 -and $lines[0] -ceq $expectedHeader), $summary.CopilotUsage.RowCount)
}
catch {
    Add-CaseResult -Name 'c6. zero events -> header-only file, RowCount=0' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c7. Auth guard (no -SearchExecutor -> throws).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c7: auth guard (no executor -> throws) ----" -ForegroundColor Cyan
try {
    $outC7 = New-TempOutDir 'c7'
    $threwC7 = $false
    try {
        & $scriptPath -OutputDirectory $outC7 -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwC7 = $true
    }
    Add-CaseResult -Name 'c7. auth guard throws without -SearchExecutor' -Pass $threwC7 `
        -Detail ("threw={0}" -f $threwC7)
}
catch {
    Add-CaseResult -Name 'c7. auth guard throws without -SearchExecutor' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== COLLECT AI-COPILOT-USAGE RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} collector cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
