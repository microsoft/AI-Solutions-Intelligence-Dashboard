<#
.SYNOPSIS
    Orchestrates the AI Solutions dashboard export: runs the available Defender
    Advanced Hunting presets, creates required fallback stubs, and optionally
    adds the six Section-A Graph/Purview artifacts.

.DESCRIPTION
    The AI Solutions dashboard (pbit) imports thirteen CSVs. FOUR of them are
    produced by Defender Advanced Hunting via Export-DefenderAdvancedHunting.ps1
    and the bundled KQL presets:

        ai_activity_sessions.csv   <- CloudAppEvents_ai_activity_sessions.kql   (Month,  bucket UPN)
        ai_offhours_geo.csv        <- EntraIdSignInEvents_ai_offhours_geo.kql   (Month,  bucket UPN)
        ai_client_channel.csv      <- DeviceNetworkEvents_ai_client_channel.kql (Month,  no bucket)
        ai_file_proximity.csv      <- DeviceNetworkEvents_ai_file_proximity.kql (Adaptive)

    THREE of them (ai_appgov_alerts, ai_cloud_discovery, ai_mda_sessions) come
    from Microsoft Defender for Cloud Apps (MDA), NOT from Defender Advanced
    Hunting. When MDA data is unavailable the dashboard's own documentation
    sanctions header-only STUB CSVs for these three "to avoid Power Query errors
    when MDA CSVs are missing." This orchestrator writes those stubs
    CREATE-IF-MISSING: if a real MDA CSV is already present in -OutputDirectory
    it is left untouched (never clobbered by a header-only stub).

    CloudAppEvents also depends on MDA. For a tenant without that table, use
    -SkipActivitySessions to skip only that preset and create a header-only
    ai_activity_sessions.csv. The other three Advanced Hunting presets continue.

    With -IncludeSectionA, the orchestrator also runs the bundled Graph and
    Purview collectors to produce the remaining six CSVs, for all thirteen
    dashboard artifacts in one command. This path requires the additional Graph
    permissions plus an active Connect-ExchangeOnline session.

    Each preset is run through the existing Export-DefenderAdvancedHunting.ps1
    using the SAME invocation contract as Invoke-SmokeTest.ps1 (a splat
    hashtable with Query / StartDate / EndDate / TimeColumn / OutputPath and
    per-preset PartitionMode / UserBucketColumn). Authentication is passed by
    reference only: EITHER a pre-acquired -AccessToken, OR the
    -TenantId/-ClientId/-ClientSecret app-registration trio, OR (for tests) an
    injected -QueryExecutor mock seam. NO secret, token, tenant id, or client id
    value is ever hardcoded or logged.

    Failures propagate as thrown exceptions (fail-fast), except for a source the
    caller explicitly skips with -SkipActivitySessions.

.PARAMETER StartDate
    Inclusive start of the export window (half-open interval start), passed
    straight through to every preset run.

.PARAMETER EndDate
    Exclusive end of the export window (half-open interval end), passed straight
    through to every preset run.

.PARAMETER OutputDirectory
    Directory that receives all produced CSVs: seven baseline artifacts, plus
    six Section-A artifacts when -IncludeSectionA is set. Created if missing.

.PARAMETER TimeColumn
    Time column used for filtering / subdivision by every preset. Defaults to
    'Timestamp' (correct for all four presets).

.PARAMETER AccessToken
    A pre-acquired Microsoft Graph bearer token. Never logged. Use this OR the
    -TenantId/-ClientId/-ClientSecret trio OR -QueryExecutor.

.PARAMETER TenantId
    Azure AD tenant id for client-credentials auth. Used only when -AccessToken
    and -QueryExecutor are not supplied.

.PARAMETER ClientId
    App registration (client) id for client-credentials auth.

.PARAMETER ClientSecret
    App registration client secret as a SecureString. Never logged.

.PARAMETER QueryExecutor
    INJECTION SEAM FOR TESTING. A scriptblock passed straight through to the
    exporter's -QueryExecutor parameter. When supplied, NO credentials are
    required and Microsoft Graph is never called. Takes precedence over
    -AccessToken and the app-registration trio.

.PARAMETER SkipActivitySessions
    Skips the CloudAppEvents preset and creates ai_activity_sessions.csv with
    its exact header if the file does not already exist. Use this for tenants
    without Defender for Cloud Apps or the CloudAppEvents table. The remaining
    three Advanced Hunting presets still run.

.PARAMETER SkipStubs
    When set, the three header-only MDA stub CSVs are NOT written. The four real
    Defender AH artifacts are still produced.

.PARAMETER IncludeSectionA
    Produces the six Graph/Purview/Entra Section-A artifacts in addition to the
    seven baseline artifacts, yielding the complete 13-file dashboard package.

.PARAMETER GraphQueryExecutor
    INJECTION SEAM FOR TESTING the Section-A Graph collector.

.PARAMETER PurviewSearchExecutor
    INJECTION SEAM FOR TESTING the Section-A Purview collector.

.EXAMPLE
    # Full export with a pre-acquired token over a retained-data window.
    Connect-ExchangeOnline
    .\Invoke-AISolutionsExport.ps1 -AccessToken $env:GRAPH_TOKEN `
        -StartDate '2026-01-01' -EndDate '2026-07-01' `
        -OutputDirectory .\dashboard_data -IncludeSectionA

.EXAMPLE
    # Full export with an app registration (client credentials).
    Connect-ExchangeOnline
    $secret = Read-Host -AsSecureString 'Client secret'
    .\Invoke-AISolutionsExport.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret `
        -StartDate '2026-01-01' -EndDate '2026-07-01' `
        -OutputDirectory .\dashboard_data -IncludeSectionA

.EXAMPLE
    # Credential-free run using an injected mock executor (unit testing).
    $mock = { param($ctx) @([PSCustomObject]@{ Col1='a'; Col2=1 }) }
    .\Invoke-AISolutionsExport.ps1 -QueryExecutor $mock `
        -StartDate '2026-05-01' -EndDate '2026-06-01' `
        -OutputDirectory $tempDir

.NOTES
    Requires PowerShell 7+. For real (non-mock) execution the identity used must
    have admin-consented Microsoft Graph permission ThreatHunting.Read.All. A
    full Section-A run also requires User.Read.All, LicenseAssignment.Read.All,
    AuditLog.Read.All, and an active Exchange Online session. Returns a summary
    PSCustomObject (does NOT call exit). Let failures throw.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [datetime]$StartDate,

    [Parameter(Mandatory)]
    [datetime]$EndDate,

    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [string]$TimeColumn = 'Timestamp',

    [string]$AccessToken,

    [string]$TenantId,

    [string]$ClientId,

    [securestring]$ClientSecret,

    [scriptblock]$QueryExecutor,

    [switch]$SkipActivitySessions,

    [switch]$SkipStubs,

    [switch]$IncludeSectionA,

    [scriptblock]$GraphQueryExecutor,

    [scriptblock]$PurviewSearchExecutor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Preset manifest (authoritative per-preset run configuration).
# Order is the run order. UserBucketColumn is $null for non-bucketed presets.
# ---------------------------------------------------------------------------
$presetManifest = @(
    [PSCustomObject]@{
        Artifact = 'ai_activity_sessions.csv'; PresetFile = 'CloudAppEvents_ai_activity_sessions.kql'
        PartitionMode = 'Month'; UserBucketColumn = 'UPN'
        OutputColumns = @('UPN','AISolution','YearMonth','Sessions','ActiveDays','EstimatedPrompts','DistinctDevices','Category','RiskTier')
    }
    [PSCustomObject]@{
        Artifact = 'ai_offhours_geo.csv'; PresetFile = 'EntraIdSignInEvents_ai_offhours_geo.kql'
        PartitionMode = 'Month'; UserBucketColumn = 'UPN'
        OutputColumns = @('UPN','YearMonth','TotalSessions','OffHoursSessions','OffHoursPct','DistinctCountries','AnomalousCountryCount','AnomalousCountries')
    }
    [PSCustomObject]@{
        Artifact = 'ai_client_channel.csv'; PresetFile = 'DeviceNetworkEvents_ai_client_channel.kql'
        PartitionMode = 'Month'; UserBucketColumn = $null
        OutputColumns = @('AISite','Channel','YearMonth','EventCount')
    }
    [PSCustomObject]@{
        Artifact = 'ai_file_proximity.csv'; PresetFile = 'DeviceNetworkEvents_ai_file_proximity.kql'
        PartitionMode = 'Adaptive'; UserBucketColumn = $null
        OutputColumns = @('Timestamp','UPN','AISolution','YearMonth','FileName','FolderCategory','FolderPath','SecondsToAI','NameMatchesSensitivePattern','FolderMatchesSensitive')
    }
)

# ---------------------------------------------------------------------------
# Stub manifest (byte-exact header strings for the three MDA artifacts).
# ---------------------------------------------------------------------------
$stubManifest = [ordered]@{
    'ai_appgov_alerts.csv'   = 'Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description'
    'ai_cloud_discovery.csv' = 'AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus'
    'ai_mda_sessions.csv'    = 'Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount'
}

# ---------------------------------------------------------------------------
# Pre-flight validation (fail fast; do NOT swallow errors).
# ---------------------------------------------------------------------------
$exporter = Join-Path $PSScriptRoot 'Export-DefenderAdvancedHunting.ps1'
if (-not (Test-Path $exporter)) {
    throw "Exporter not found at '$exporter'."
}

$presetsDir = Join-Path $PSScriptRoot 'presets'
foreach ($p in $presetManifest) {
    $probe = Join-Path $presetsDir $p.PresetFile
    if (-not (Test-Path $probe)) {
        throw "Required preset not found at '$probe'."
    }
}

$hasExecutor = ($null -ne $QueryExecutor)
$hasToken    = -not [string]::IsNullOrWhiteSpace($AccessToken)
$hasAppReg   = (-not [string]::IsNullOrWhiteSpace($TenantId)) -and
               (-not [string]::IsNullOrWhiteSpace($ClientId)) -and
               ($null -ne $ClientSecret)
if (-not ($hasExecutor -or $hasToken -or $hasAppReg)) {
    throw "No credentials or test seam supplied. Provide -QueryExecutor (test), OR -AccessToken, OR -TenantId + -ClientId + -ClientSecret."
}

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Section-A pre-flight (only when -IncludeSectionA). The two Section-A
# collectors must sit next to this orchestrator, and Graph auth must exist.
# ---------------------------------------------------------------------------
$graphCollector   = Join-Path $PSScriptRoot 'Collect-AISolutionsGraph.ps1'
$copilotCollector = Join-Path $PSScriptRoot 'Collect-AICopilotUsage.ps1'
if ($IncludeSectionA) {
    if (-not (Test-Path $graphCollector))   { throw "Section-A collector not found at '$graphCollector'." }
    if (-not (Test-Path $copilotCollector)) { throw "Section-A collector not found at '$copilotCollector'." }

    $hasGraphExecutor = ($null -ne $GraphQueryExecutor)
    if (-not ($hasGraphExecutor -or $hasToken -or $hasAppReg)) {
        throw "Section-A requested but no Graph auth supplied. Provide -GraphQueryExecutor (test), OR -AccessToken, OR -TenantId + -ClientId + -ClientSecret."
    }
}

# ---------------------------------------------------------------------------
# Per-preset run loop (manifest order).
# ---------------------------------------------------------------------------
$presetResults = [System.Collections.Generic.List[object]]::new()

foreach ($p in $presetManifest) {
    $presetPath = Join-Path $presetsDir $p.PresetFile
    $kql = Get-Content -LiteralPath $presetPath -Raw
    if ($kql -notmatch '\{TIMEFILTER\}') {
        throw "Preset '$presetPath' does not contain the required {TIMEFILTER} token."
    }

    $outPath = Join-Path $OutputDirectory $p.Artifact

    if ($SkipActivitySessions -and $p.Artifact -eq 'ai_activity_sessions.csv') {
        if (Test-Path $outPath) {
            $status = 'SkippedExisting'
        }
        else {
            [System.IO.File]::WriteAllText(
                $outPath,
                (($p.OutputColumns -join ',') + "`n")
            )
            $status = 'StubCreated'
        }
        $presetResults.Add([PSCustomObject]@{
            Artifact         = $p.Artifact
            Path             = $outPath
            PartitionMode    = $p.PartitionMode
            UserBucketColumn = $p.UserBucketColumn
            TotalRows        = 0
            Status           = $status
        })
        Write-Host ("  preset {0}: {1}" -f $status, $p.Artifact) -ForegroundColor Cyan
        continue
    }

    $exporterArgs = @{
        Query         = $kql
        StartDate     = $StartDate
        EndDate       = $EndDate
        TimeColumn    = $TimeColumn
        OutputPath    = $outPath
        OutputColumns = $p.OutputColumns
        PartitionMode = $p.PartitionMode
    }
    if ($p.UserBucketColumn) {
        $exporterArgs['UserBucketColumn'] = $p.UserBucketColumn
    }

    # Auth precedence: executor (test) first so tests never need credentials.
    if ($hasExecutor) {
        $exporterArgs['QueryExecutor'] = $QueryExecutor
    }
    elseif ($hasToken) {
        $exporterArgs['AccessToken'] = $AccessToken
    }
    else {
        $exporterArgs['TenantId']     = $TenantId
        $exporterArgs['ClientId']     = $ClientId
        $exporterArgs['ClientSecret'] = $ClientSecret
    }

    $summary = & $exporter @exporterArgs

    $rows = 'unknown'
    try { $rows = $summary.TotalRows } catch { }

    $bucketLabel = if ($p.UserBucketColumn) { $p.UserBucketColumn } else { '' }
    $presetResults.Add([PSCustomObject]@{
        Artifact         = $p.Artifact
        Path             = $outPath
        PartitionMode    = $p.PartitionMode
        UserBucketColumn = $bucketLabel
        TotalRows        = $rows
        Status           = 'OK'
    })

    Write-Host ("  preset OK: {0} ({1} rows)" -f $p.Artifact, $rows) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# MDA stubs (create-if-missing; skip entirely when -SkipStubs).
# ---------------------------------------------------------------------------
$stubResults = [System.Collections.Generic.List[object]]::new()

if (-not $SkipStubs) {
    foreach ($name in $stubManifest.Keys) {
        $header = $stubManifest[$name]
        $stubPath = Join-Path $OutputDirectory $name
        if (Test-Path $stubPath) {
            $status = 'SkippedExists'
        }
        else {
            # UTF-8 without BOM (PS7 default for WriteAllText), single LF-terminated header line.
            [System.IO.File]::WriteAllText($stubPath, $header + "`n")
            $status = 'Created'
        }
        $stubResults.Add([PSCustomObject]@{
            Name   = $name
            Path   = $stubPath
            Status = $status
        })
        Write-Host ("  stub {0}: {1}" -f $status, $name) -ForegroundColor Cyan
    }
}

# ---------------------------------------------------------------------------
# Section-A collectors (only when -IncludeSectionA). Emits the six Section-A
# CSVs so a single run produces all thirteen dashboard artifacts. Auth is passed
# by reference only (seam > token > app-reg); nothing is logged.
# ---------------------------------------------------------------------------
$sectionA = $null
if ($IncludeSectionA) {
    # A1/A3/A4/A5 via the Graph collector (all four; no -Skip* switches).
    $graphArgs = @{ OutputDirectory = $OutputDirectory; StartDate = $StartDate; EndDate = $EndDate }
    if ($null -ne $GraphQueryExecutor) {
        $graphArgs['QueryExecutor'] = $GraphQueryExecutor
    }
    elseif ($hasToken) {
        $graphArgs['AccessToken'] = $AccessToken
    }
    else {
        $graphArgs['TenantId']     = $TenantId
        $graphArgs['ClientId']     = $ClientId
        $graphArgs['ClientSecret'] = $ClientSecret
    }
    $graphResult = & $graphCollector @graphArgs

    # A2 via the Purview collector (seam in test mode; ambient EXO otherwise).
    $copilotArgs = @{ OutputDirectory = $OutputDirectory; StartDate = $StartDate; EndDate = $EndDate }
    if ($null -ne $PurviewSearchExecutor) {
        $copilotArgs['SearchExecutor'] = $PurviewSearchExecutor
    }
    $copilotResult = & $copilotCollector @copilotArgs

    $sectionA = [PSCustomObject]@{
        GraphResult   = $graphResult
        CopilotResult = $copilotResult
    }
    Write-Host "  Section-A: Graph + Purview collectors complete (6 CSVs)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Readable summary (Write-Host does not pollute the pipeline) + return object.
# ---------------------------------------------------------------------------
$presetCount = @($presetResults | Where-Object { $_.Status -eq 'OK' }).Count
$skippedPresetCount = @($presetResults | Where-Object { $_.Status -ne 'OK' }).Count
$stubCount = if ($SkipStubs) { 0 } else { $stubResults.Count }

Write-Host ""
Write-Host "==== AI Solutions export summary ====" -ForegroundColor White
Write-Host ("OutputDirectory : {0}" -f $OutputDirectory)
Write-Host ("Window          : {0} -> {1}" -f $StartDate.ToString('u'), $EndDate.ToString('u'))
Write-Host ("Presets run     : {0}" -f $presetCount)
Write-Host ("Presets stubbed : {0}" -f $skippedPresetCount)
Write-Host ("MDA stubs       : {0}" -f $stubCount)
Write-Host ("Section-A       : {0}" -f $(if ($IncludeSectionA) { 'included (6 CSVs)' } else { 'skipped' }))
Write-Host ""

return [PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    WindowStart     = $StartDate
    WindowEnd       = $EndDate
    Presets         = $presetResults.ToArray()
    Stubs           = $stubResults.ToArray()
    PresetCount     = $presetCount
    SkippedPresetCount = $skippedPresetCount
    StubCount       = $stubCount
    SectionAIncluded = [bool]$IncludeSectionA
    SectionA         = $sectionA
}
