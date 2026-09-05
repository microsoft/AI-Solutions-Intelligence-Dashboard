<#
    Credential-free regression checks for the duplicated manual collection path.

    The PAX presets are the source of truth for Defender AI app/domain catalogs.
    The manual query pack and inline setup queries must retain the same catalogs,
    while the Graph examples must match the Graph collector's shared keywords.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$manualPath = Join-Path $repoRoot 'kql_queries_v22_E5V3.kql'
$instructionsPath = Join-Path $repoRoot 'INSTRUCTIONS_v26.md'
$collectorPath = Join-Path $repoRoot 'PAX_Exporter\Collect-AISolutionsGraph.ps1'
$presetRoot = Join-Path $repoRoot 'PAX_Exporter\presets'

$manual = Get-Content -LiteralPath $manualPath -Raw
$instructions = Get-Content -LiteralPath $instructionsPath -Raw
$collector = Get-Content -LiteralPath $collectorPath -Raw

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Name, [bool]$Pass, [string]$Detail)
    $results.Add([pscustomobject]@{ Name = $Name; Pass = $Pass; Detail = $Detail })
    $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("{0}: {1} -- {2}" -f $tag, $Name, $Detail) -ForegroundColor $color
}

function Get-Section {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$StartMarker,
        [Parameter(Mandatory)] [string]$EndMarker
    )
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Start marker not found: $StartMarker" }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($end -lt 0) { throw "End marker not found after '$StartMarker': $EndMarker" }
    return $Text.Substring($start, $end - $start)
}

function Get-QuotedValues {
    param([Parameter(Mandatory)] [string]$Text)
    $pattern = "[`"'](?<value>[^`"']+)[`"']"
    return @([regex]::Matches($Text, $pattern) | ForEach-Object { $_.Groups['value'].Value })
}

function Get-DynamicList {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Name
    )
    $pattern = 'let\s+' + [regex]::Escape($Name) + '\s*=\s*dynamic\(\[(?<body>.*?)\]\);'
    $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { throw "KQL dynamic list not found: $Name" }
    return @(Get-QuotedValues -Text $match.Groups['body'].Value)
}

function Get-PowerShellArray {
    param(
        [Parameter(Mandatory)] [string]$Text,
        [Parameter(Mandatory)] [string]$Name
    )
    $pattern = '\$' + [regex]::Escape($Name) + '\s*=\s*@\((?<body>.*?)\)'
    $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) { throw "PowerShell array not found: $Name" }
    return @(Get-QuotedValues -Text $match.Groups['body'].Value)
}

function Get-EmbeddedPowerShell {
    param([Parameter(Mandatory)] [string]$Section)
    $block = Get-Section -Text $Section -StartMarker '<powershell>' -EndMarker '</powershell>'
    $lines = $block -split "\r?\n" |
        Where-Object { $_ -notmatch '</?powershell>' } |
        ForEach-Object { $_ -replace '^\s*// ?', '' }
    return $lines -join [Environment]::NewLine
}

function Add-ListComparison {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string[]]$Expected,
        [Parameter(Mandatory)] [string[]]$Actual
    )
    $expectedKey = $Expected -join [char]0
    $actualKey = $Actual -join [char]0
    $pass = ($Expected.Count -eq $Actual.Count) -and ($expectedKey -ceq $actualKey)
    Add-Result -Name $Name -Pass $pass -Detail ("expected={0}; actual={1}" -f $Expected.Count, $Actual.Count)
}

$activityPreset = Get-Content -LiteralPath (Join-Path $presetRoot 'CloudAppEvents_ai_activity_sessions.kql') -Raw
$offHoursPreset = Get-Content -LiteralPath (Join-Path $presetRoot 'EntraIdSignInEvents_ai_offhours_geo.kql') -Raw
$filePreset = Get-Content -LiteralPath (Join-Path $presetRoot 'DeviceNetworkEvents_ai_file_proximity.kql') -Raw
$channelPreset = Get-Content -LiteralPath (Join-Path $presetRoot 'DeviceNetworkEvents_ai_client_channel.kql') -Raw

$canonicalApps = Get-DynamicList -Text $activityPreset -Name 'AIAppNames'
$canonicalDomains = Get-DynamicList -Text $filePreset -Name 'AIDomains'

Add-ListComparison -Name 'PAX app-name presets stay synchronized' -Expected $canonicalApps `
    -Actual (Get-DynamicList -Text $offHoursPreset -Name 'AIAppNames')
Add-ListComparison -Name 'PAX domain presets stay synchronized' -Expected $canonicalDomains `
    -Actual (Get-DynamicList -Text $channelPreset -Name 'AIDomains')

$manualAppSections = [ordered]@{
    'query pack B2 activity sessions' = Get-Section $manual 'SECTION B2' 'SECTION B3'
    'query pack B4 off-hours geo' = Get-Section $manual 'SECTION B4' 'SECTION B5'
    'query pack B6 app governance' = Get-Section $manual 'SECTION B6' 'SECTION B7'
    'query pack B8 MDA sessions' = Get-Section $manual 'SECTION B8' 'END OF QUERY PACK'
    'instructions 1.3 activity sessions' = Get-Section $instructions '### 1.3' '### 1.4'
    'instructions 1.7 off-hours geo' = Get-Section $instructions '### 1.7' '### 1.8'
    'instructions 3.1 app governance' = Get-Section $instructions '### 3.1' '### 3.2'
    'instructions 3.3 MDA sessions' = Get-Section $instructions '### 3.3' '## Step 4'
}
foreach ($entry in $manualAppSections.GetEnumerator()) {
    Add-ListComparison -Name "$($entry.Key) matches PAX app catalog" -Expected $canonicalApps `
        -Actual (Get-DynamicList -Text $entry.Value -Name 'AIAppNames')
}

$manualDomainSections = [ordered]@{
    'query pack B3 file proximity' = Get-Section $manual 'SECTION B3' 'SECTION B4'
    'query pack B5 client channel' = Get-Section $manual 'SECTION B5' 'SECTION B6'
    'instructions 1.6 file proximity' = Get-Section $instructions '### 1.6' '### 1.7'
    'instructions 1.9 client channel' = Get-Section $instructions '### 1.9' '## Step 2'
}
foreach ($entry in $manualDomainSections.GetEnumerator()) {
    Add-ListComparison -Name "$($entry.Key) matches PAX domain catalog" -Expected $canonicalDomains `
        -Actual (Get-DynamicList -Text $entry.Value -Name 'AIDomains')
}

$manualA3 = Get-Section $manual 'SECTION A3' 'SECTION A4'
$manualA4 = Get-Section $manual 'SECTION A4' 'SECTION A5'
$collectorKeywords = Get-PowerShellArray -Text $collector -Name 'aiKeywords'
Add-ListComparison -Name 'query pack A3 keywords match Graph collector' -Expected $collectorKeywords `
    -Actual (Get-PowerShellArray -Text $manualA3 -Name 'aiKeywords')
Add-ListComparison -Name 'query pack A4 keywords match Graph collector' -Expected $collectorKeywords `
    -Actual (Get-PowerShellArray -Text $manualA4 -Name 'aiKeywords')

$manualB2 = $manualAppSections['query pack B2 activity sessions']
$instructionsB2 = $manualAppSections['instructions 1.3 activity sessions']
$fallbackPattern = '(?m)^\s*Application\s*(?://[^\r\n]*)?\r?\n\s*\)'
Add-Result -Name 'query pack B2 preserves allowlisted fallback' `
    -Pass ([regex]::IsMatch($manualB2, $fallbackPattern)) -Detail 'fallback=Application'
Add-Result -Name 'instructions 1.3 preserves allowlisted fallback' `
    -Pass ([regex]::IsMatch($instructionsB2, $fallbackPattern)) -Detail 'fallback=Application'

$caGroupPass = $manualA4.Contains('Group-Object UPN, App, YearMonth, HasCA') -and
    $manualA4.Contains('HasConditionalAccess = $grp[0].HasCA')
Add-Result -Name 'query pack A4 keeps CA states in separate aggregates' `
    -Pass $caGroupPass -Detail 'group keys include HasCA'

$manualB7 = Get-Section $manual 'SECTION B7' 'SECTION B8'
$cloudVariants = @(
    'Get-CloudDiscoveryValue', '"App domain", "Domain"', '"Score", "Risk score"',
    '"Upload (bytes)", "Upload traffic (Bytes)"',
    '"Download (bytes)", "Download traffic (Bytes)"',
    '"Transactions", "Total transactions"', '"Users", "Total users"',
    '"Tag", "Sanction status", "App status"'
)
$missingVariants = @($cloudVariants | Where-Object { -not $manualB7.Contains($_) })
Add-Result -Name 'query pack B7 handles known Cloud Discovery columns' `
    -Pass ($missingVariants.Count -eq 0) `
    -Detail $(if ($missingVariants.Count -eq 0) { 'all variants present' } else { 'missing: ' + ($missingVariants -join '; ') })

$embeddedScripts = [ordered]@{
    'query pack A3 PowerShell parses' = Get-EmbeddedPowerShell -Section $manualA3
    'query pack A4 PowerShell parses' = Get-EmbeddedPowerShell -Section $manualA4
    'query pack B7 PowerShell parses' = Get-EmbeddedPowerShell -Section $manualB7
}
foreach ($entry in $embeddedScripts.GetEnumerator()) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput(
        $entry.Value,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Result -Name $entry.Key -Pass ($parseErrors.Count -eq 0) `
        -Detail $(if ($parseErrors.Count -eq 0) { 'parseErrors=0' } else { ($parseErrors.Message -join '; ') })
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ai_manual_b7_{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$previousLocation = Get-Location
try {
    $rawPath = Join-Path $tempDir 'DiscoveredApps_export.csv'
    [pscustomobject]@{
        Domain = 'deepseek.com'
        'App category' = 'Generative AI'
        Month = '2026-08'
        'Risk score' = 4
        'Upload traffic (Bytes)' = 1048576
        'Download traffic (Bytes)' = 2097152
        'Total transactions' = 7
        'Total users' = 3
        'App status' = 'Unsanctioned'
    } | Export-Csv -LiteralPath $rawPath -NoTypeInformation

    Set-Location $tempDir
    & ([scriptblock]::Create($embeddedScripts['query pack B7 PowerShell parses'])) | Out-Null
    $row = Import-Csv -LiteralPath (Join-Path $tempDir 'ai_cloud_discovery.csv')
    $variantPass = ($row.AIDomain -eq 'deepseek.com') -and
        ($row.AppCategory -eq 'Generative AI') -and
        ($row.YearMonth -eq '2026-08') -and
        ([double]$row.UploadVolumeMB -eq 1) -and
        ([double]$row.DownloadVolumeMB -eq 2) -and
        ([int]$row.TransactionCount -eq 7) -and
        ([int]$row.DistinctUsers -eq 3) -and
        ($row.SanctionStatus -eq 'Unsanctioned')
    Add-Result -Name 'query pack B7 reshapes alternate portal columns' -Pass $variantPass `
        -Detail ("domain={0}; month={1}; uploadMB={2}; downloadMB={3}" -f $row.AIDomain, $row.YearMonth, $row.UploadVolumeMB, $row.DownloadVolumeMB)
}
finally {
    Set-Location $previousLocation
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$failed = @($results | Where-Object { -not $_.Pass })
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ("OVERALL: FAIL ({0} of {1} checks failed)" -f $failed.Count, $results.Count) -ForegroundColor Red
    exit 1
}
Write-Host ("OVERALL: PASS (all {0} manual-path parity checks green)" -f $results.Count) -ForegroundColor Green
exit 0
