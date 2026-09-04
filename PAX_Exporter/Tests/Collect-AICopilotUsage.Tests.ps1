<#
    Collect-AICopilotUsage.Tests.ps1

    CREDENTIAL-FREE test for the Section-A A2 Purview collector
    Collect-AICopilotUsage.ps1 (ai_copilot_usage_graph.csv and
    ai_copilot_surface_usage.csv).

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
      c1. Headers byte-exact -- 2 users aggregated; assert both CSV first lines
          and row counts.
      c2. Workload mapping -- one user/month across MicrosoftTeams, Word, Excel,
          Outlook, PowerPoint, Bing, M365Chat, Microsoft365 + unknown 'Loop';
          assert per-surface sums (Bing+M365Chat+Microsoft365 fold into Chat) and
          that 'Loop' is retained dynamically and included in TotalPrompts.
      c3. Prompt counting -- Prompts present (Count used) vs absent (defaults to
          1); assert per-surface sum and TotalPrompts reflect Count-or-1.
      c4. Month + activity aggregation -- one user, two dates same month + a
          record in a different month; assert 2 rows, ActiveDays = distinct-date
          count, LastActivityDate = max date (yyyy-MM-dd).
      c5. Pagination -- -PageSize 2; page0 is short, page1 still has records,
          then an empty page; assert no records are truncated.
      c6. Zero events -- empty mock; assert the file exists, its only line is the
          byte-exact header, and summary RowCount=0.
      c7. Saturation splitting -- simulated ReturnLargeSet ceiling causes a
          split; assert every event is returned once across half-open windows.
      c8. Auth guard -- no -SearchExecutor -> THROWS (Search-UnifiedAuditLog
          absent / not connected).
      c9. Real 50,000 ceiling -- collect 50,001 mocked records and assert all
          records survive adaptive splitting without truncation.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed.
$null = Get-Random -SetSeed 20260724

$scriptPath = Join-Path $PSScriptRoot '..\Collect-AICopilotUsage.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

# Exact expected byte-for-byte 11-column header.
$expectedHeader = 'UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate'
$expectedSurfaceHeader = 'UserPrincipalName,YearMonth,Surface,SourceWorkload,SourceAppHost,PromptCount,ActiveDays,LastActivityDate'

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
    # collector's real ConvertFrom-Json path is exercised).
    param(
        [string]$UserId,
        [string]$CreationTime,
        [string]$Workload,
        [string]$AppHost = '',
        [object]$Prompts = $null,
        [switch]$UseOuterCreationDate
    )
    $ht = [ordered]@{ UserId = $UserId; Workload = $Workload }
    if (-not $UseOuterCreationDate) { $ht['CreationTime'] = $CreationTime }
    $eventData = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($AppHost)) { $eventData['AppHost'] = $AppHost }
    if ($null -ne $Prompts) { $eventData['Prompts'] = $Prompts }
    if ($eventData.Count -gt 0) { $ht['CopilotEventData'] = $eventData }
    $json = ([pscustomobject]$ht) | ConvertTo-Json -Compress -Depth 5
    if ($UseOuterCreationDate) {
        return [pscustomobject]@{ AuditData = $json; CreationDate = $CreationTime }
    }
    return [pscustomobject]@{ AuditData = $json }
}

# ===========================================================================
# CASE c1. Header byte-exact + row count (2 users aggregated).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c1: header byte-exact + row count ----" -ForegroundColor Cyan
try {
    $c1Recs = [System.Collections.Generic.List[object]]::new()
    $c1Recs.Add((New-CuRec -UserId 'a@x' -CreationTime '2026-05-04T10:00:00Z' -Workload 'Word'  -Prompts @(1, 2)))
    $c1Recs.Add((New-CuRec -UserId 'a@x' -CreationTime '2026-05-06T10:00:00Z' -Workload 'Word'))
    $c1Recs.Add((New-CuRec -UserId 'b@x' -CreationTime '2026-05-07T10:00:00Z' -Workload 'Teams' -Prompts @(1) -UseOuterCreationDate))
    $c1Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c1Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC1 = New-TempOutDir 'c1'
    & $scriptPath -OutputDirectory $outC1 -SearchExecutor $c1Mock -WarningAction SilentlyContinue | Out-Null

    $path = Join-Path $outC1 'ai_copilot_usage_graph.csv'
    $surfacePath = Join-Path $outC1 'ai_copilot_surface_usage.csv'
    $firstLine = (Get-Content -LiteralPath $path)[0]
    $surfaceFirstLine = (Get-Content -LiteralPath $surfacePath)[0]
    $rows = @(Import-Csv -LiteralPath $path)
    $surfaceRows = @(Import-Csv -LiteralPath $surfacePath)
    $passC1 = ($firstLine -ceq $expectedHeader) -and `
              ($surfaceFirstLine -ceq $expectedSurfaceHeader) -and `
              ($rows.Count -eq 2) -and ($surfaceRows.Count -eq 2)
    Add-CaseResult -Name 'c1. both headers byte-exact + expected row counts' -Pass $passC1 `
        -Detail ("legacyHeader={0}; surfaceHeader={1}; legacyRows={2}; surfaceRows={3}" -f `
            ($firstLine -ceq $expectedHeader), ($surfaceFirstLine -ceq $expectedSurfaceHeader), `
            $rows.Count, $surfaceRows.Count)
}
catch {
    Add-CaseResult -Name 'c1. both headers byte-exact + expected row counts' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c2. Nested AppHost mapping and dynamic retention.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c2: nested AppHost mapping + dynamic retention ----" -ForegroundColor Cyan
try {
    $c2Recs = [System.Collections.Generic.List[object]]::new()
    foreach ($appHostValue in @('MicrosoftTeams', 'Word', 'Excel', 'Outlook', 'PowerPoint', 'BizChat', 'Bing', 'Office', 'M365App', 'Loop', 'Edge')) {
        $c2Recs.Add((New-CuRec -UserId 'c2@x' -CreationTime '2026-05-04T10:00:00Z' -Workload 'Copilot' -AppHost $appHostValue))
    }
    $c2Mock = {
        param($ctx)
        if ($ctx.Page -eq 0) { return $c2Recs.ToArray() }
        return @()
    }.GetNewClosure()

    $outC2 = New-TempOutDir 'c2'
    & $scriptPath -OutputDirectory $outC2 -SearchExecutor $c2Mock -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outC2 'ai_copilot_usage_graph.csv'))
    $surfaceRows = @(Import-Csv -LiteralPath (Join-Path $outC2 'ai_copilot_surface_usage.csv'))
    $row = $rows | Where-Object { $_.UserPrincipalName -eq 'c2@x' }
    $loopRow = $surfaceRows | Where-Object { $_.Surface -eq 'Loop' }
    $officeRow = $surfaceRows | Where-Object { $_.SourceAppHost -eq 'Office' }
    $m365AppRow = $surfaceRows | Where-Object { $_.SourceAppHost -eq 'M365App' }
    # Each record defaults to one prompt. Chat consolidates the four documented
    # chat hosts; legacy Total also includes the dynamically retained surfaces.
    $passC2 = ($rows.Count -eq 1) -and ($null -ne $row) -and `
              ([int]$row.TeamsPrompts -eq 1) -and ([int]$row.WordPrompts -eq 1) -and `
              ([int]$row.ExcelPrompts -eq 1) -and ([int]$row.OutlookPrompts -eq 1) -and `
              ([int]$row.PowerPointPrompts -eq 1) -and ([int]$row.ChatPrompts -eq 4) -and `
              ([int]$row.TotalPrompts -eq 11) -and ($surfaceRows.Count -eq 11) -and `
              ($null -ne $loopRow) -and ([int]$loopRow.PromptCount -eq 1) -and `
              ($loopRow.SourceWorkload -eq 'Copilot') -and ($loopRow.SourceAppHost -eq 'Loop') -and `
              ($officeRow.Surface -eq 'Chat') -and ($m365AppRow.Surface -eq 'Chat')
    Add-CaseResult -Name 'c2. nested AppHost mapping + raw fields + dynamic surfaces' -Pass $passC2 `
        -Detail ("teams={0};word={1};excel={2};outlook={3};ppt={4};chat={5};total={6};loop={7}" -f `
            $(if ($row) { $row.TeamsPrompts } else { 'n/a' }), $(if ($row) { $row.WordPrompts } else { 'n/a' }), `
            $(if ($row) { $row.ExcelPrompts } else { 'n/a' }), $(if ($row) { $row.OutlookPrompts } else { 'n/a' }), `
            $(if ($row) { $row.PowerPointPrompts } else { 'n/a' }), $(if ($row) { $row.ChatPrompts } else { 'n/a' }), `
            $(if ($row) { $row.TotalPrompts } else { 'n/a' }), $(if ($loopRow) { $loopRow.PromptCount } else { 'n/a' }))
}
catch {
    Add-CaseResult -Name 'c2. nested AppHost mapping + raw fields + dynamic surfaces' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c3. Prompt counting (Count used when present; defaults to 1 when absent).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c3: prompt counting (Count-or-1) ----" -ForegroundColor Cyan
try {
    $c3Recs = [System.Collections.Generic.List[object]]::new()
    $c3Recs.Add((New-CuRec -UserId 'c3@x' -CreationTime '2026-05-04T10:00:00Z' -Workload 'Word' -Prompts @(1, 2, 3)))  # 3
    $c3Recs.Add((New-CuRec -UserId 'c3@x' -CreationTime '2026-05-05T10:00:00Z' -Workload 'Word'))                       # 1
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
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationTime '2026-05-04T10:00:00Z' -Workload 'Word'))
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationTime '2026-05-10T14:00:00Z' -Workload 'Word'))
    $c4Recs.Add((New-CuRec -UserId 'c4@x' -CreationTime '2026-06-02T09:00:00Z' -Workload 'Word'))
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
# CASE c5. Pagination (-PageSize 2; a short page is followed by more records).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c5: pagination over pages via `$ctx.Page ----" -ForegroundColor Cyan
try {
    $c5Page0 = [System.Collections.Generic.List[object]]::new()
    $c5Page0.Add((New-CuRec -UserId 'p0a@x' -CreationTime '2026-05-04T10:00:00Z' -Workload 'Word'))
    $c5Page1 = [System.Collections.Generic.List[object]]::new()
    $c5Page1.Add((New-CuRec -UserId 'p1a@x' -CreationTime '2026-05-05T10:00:00Z' -Workload 'Word'))
    $c5Page1.Add((New-CuRec -UserId 'p1b@x' -CreationTime '2026-05-06T10:00:00Z' -Workload 'Word'))
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
    Add-CaseResult -Name 'c5. pagination continues after a short intermediate page' -Pass $passC5 `
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
    $surfacePath = Join-Path $outC6 'ai_copilot_surface_usage.csv'
    $exists = Test-Path $path
    $surfaceExists = Test-Path $surfacePath
    $lines = @(Get-Content -LiteralPath $path | Where-Object { $_.Trim().Length -gt 0 })
    $surfaceLines = @(Get-Content -LiteralPath $surfacePath | Where-Object { $_.Trim().Length -gt 0 })
    $passC6 = $exists -and ($lines.Count -eq 1) -and ($lines[0] -ceq $expectedHeader) -and `
              $surfaceExists -and ($surfaceLines.Count -eq 1) -and `
              ($surfaceLines[0] -ceq $expectedSurfaceHeader) -and `
              ([int]$summary.CopilotUsage.RowCount -eq 0) -and `
              ([int]$summary.SurfaceUsage.RowCount -eq 0)
    Add-CaseResult -Name 'c6. zero events -> both header-only files, RowCount=0' -Pass $passC6 `
        -Detail ("legacyHeader={0}; surfaceHeader={1}; legacyRows={2}; surfaceRows={3}" -f `
            ($lines.Count -ge 1 -and $lines[0] -ceq $expectedHeader), `
            ($surfaceLines.Count -ge 1 -and $surfaceLines[0] -ceq $expectedSurfaceHeader), `
            $summary.CopilotUsage.RowCount, $summary.SurfaceUsage.RowCount)
}
catch {
    Add-CaseResult -Name 'c6. zero events -> both header-only files, RowCount=0' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c7. Saturated ReturnLargeSet windows are split without boundary doubles.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c7: 50k-cap simulation splits saturated windows ----" -ForegroundColor Cyan
try {
    $c7Start = [datetime]::SpecifyKind([datetime]'2026-05-01T00:00:00', [System.DateTimeKind]::Utc)
    $c7Midnight = [datetime]::SpecifyKind([datetime]'2026-05-02T00:00:00', [System.DateTimeKind]::Utc)
    $c7End = [datetime]::SpecifyKind([datetime]'2026-05-03T00:00:00', [System.DateTimeKind]::Utc)
    $c7Data = @(
        [pscustomobject]@{ When=$c7Start.AddHours(1); Record=(New-CuRec -UserId 's1@x' -CreationTime '2026-05-01T01:00:00Z' -Workload 'Word') },
        [pscustomobject]@{ When=$c7Start.AddHours(12); Record=(New-CuRec -UserId 's2@x' -CreationTime '2026-05-01T12:00:00Z' -Workload 'Word') },
        [pscustomobject]@{ When=$c7Midnight; Record=(New-CuRec -UserId 's3@x' -CreationTime '2026-05-02T00:00:00Z' -Workload 'Word') },
        [pscustomobject]@{ When=$c7Midnight.AddHours(8); Record=(New-CuRec -UserId 's4@x' -CreationTime '2026-05-02T08:00:00Z' -Workload 'Word') },
        [pscustomobject]@{ When=$c7Midnight.AddHours(20); Record=(New-CuRec -UserId 's5@x' -CreationTime '2026-05-02T20:00:00Z' -Workload 'Word') }
    )
    $c7Calls = [System.Collections.Generic.List[object]]::new()
    $c7Mock = {
        param($ctx)
        $c7Calls.Add([pscustomobject]@{ Start=$ctx.StartDate; End=$ctx.EndDate; Page=$ctx.Page })
        $eligible = @($c7Data | Where-Object { $_.When -ge $ctx.StartDate -and $_.When -le $ctx.EndDate })
        return @($eligible | Select-Object -Skip ($ctx.Page * $ctx.ResultSize) -First $ctx.ResultSize | ForEach-Object { $_.Record })
    }.GetNewClosure()

    $outC7 = New-TempOutDir 'c7'
    $summary = & $scriptPath -OutputDirectory $outC7 -SearchExecutor $c7Mock `
        -StartDate $c7Start -EndDate $c7End `
        -PageSize 2 -MaxRecordsPerWindow 4 -WarningAction SilentlyContinue
    $rows = @(Import-Csv -LiteralPath (Join-Path $outC7 'ai_copilot_usage_graph.csv'))
    $windows = @($c7Calls | ForEach-Object { "$($_.Start.ToString('o'))|$($_.End.ToString('o'))" } | Select-Object -Unique)
    $passC7 = ([int]$summary.CopilotUsage.EventsParsed -eq 5) -and ($rows.Count -eq 5) -and ($windows.Count -ge 3)
    Add-CaseResult -Name 'c7. saturated window splits and returns all 5 events once' -Pass $passC7 `
        -Detail ("eventsParsed={0}; rows={1}; windows={2}" -f $summary.CopilotUsage.EventsParsed, $rows.Count, $windows.Count)
}
catch {
    Add-CaseResult -Name 'c7. saturated window splits and returns all 5 events once' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c8. Auth guard (no -SearchExecutor -> throws).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c8: auth guard (no executor -> throws) ----" -ForegroundColor Cyan
try {
    $outC8 = New-TempOutDir 'c8'
    $threwC8 = $false
    try {
        & $scriptPath -OutputDirectory $outC8 -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwC8 = $true
    }
    Add-CaseResult -Name 'c8. auth guard throws without -SearchExecutor' -Pass $threwC8 `
        -Detail ("threw={0}" -f $threwC8)
}
catch {
    Add-CaseResult -Name 'c8. auth guard throws without -SearchExecutor' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c9. The real 50,000-record session ceiling is exceeded without loss.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c9: collect 50,001 records across adaptive splits ----" -ForegroundColor Cyan
try {
    $c9Start = [datetime]::SpecifyKind([datetime]'2026-05-01T00:00:00', [System.DateTimeKind]::Utc)
    $c9End = $c9Start.AddDays(2)
    $c9Data = [System.Collections.Generic.List[object]]::new(50001)
    for ($i = 0; $i -lt 50001; $i++) {
        $when = $c9Start.AddSeconds($i)
        $record = New-CuRec -UserId 'over50k@x' -CreationTime $when.ToString('o') -Workload 'Word'
        $c9Data.Add([pscustomobject]@{ When = $when; Record = $record })
    }
    $c9Mock = {
        param($ctx)
        $eligible = @($c9Data | Where-Object { $_.When -ge $ctx.StartDate -and $_.When -le $ctx.EndDate })
        return @($eligible | Select-Object -Skip ($ctx.Page * $ctx.ResultSize) -First $ctx.ResultSize | ForEach-Object { $_.Record })
    }.GetNewClosure()

    $outC9 = New-TempOutDir 'c9'
    $summary = & $scriptPath -OutputDirectory $outC9 -SearchExecutor $c9Mock `
        -StartDate $c9Start -EndDate $c9End -PageSize 5000 -MaxRecordsPerWindow 50000 `
        -WarningAction SilentlyContinue
    $legacyRows = @(Import-Csv -LiteralPath (Join-Path $outC9 'ai_copilot_usage_graph.csv'))
    $surfaceRows = @(Import-Csv -LiteralPath (Join-Path $outC9 'ai_copilot_surface_usage.csv'))
    $passC9 = ([int]$summary.CopilotUsage.EventsParsed -eq 50001) -and `
              ($legacyRows.Count -eq 1) -and ([int]$legacyRows[0].TotalPrompts -eq 50001) -and `
              ($surfaceRows.Count -eq 1) -and ([int]$surfaceRows[0].PromptCount -eq 50001)
    Add-CaseResult -Name 'c9. adaptive splitting returns all 50,001 records' -Pass $passC9 `
        -Detail ("events={0}; legacyTotal={1}; surfaceTotal={2}" -f `
            $summary.CopilotUsage.EventsParsed, $legacyRows[0].TotalPrompts, $surfaceRows[0].PromptCount)
}
catch {
    Add-CaseResult -Name 'c9. adaptive splitting returns all 50,001 records' -Pass $false -Detail "threw: $($_.Exception.Message)"
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
