<#
.SYNOPSIS
    LIVE full-export smoke test for Invoke-AISolutionsExport.ps1: runs the REAL
    orchestrator with -IncludeSectionA over a small recent window and validates
    that ALL TWELVE dashboard CSVs are produced with byte-exact header lines.

.DESCRIPTION
    Where Invoke-SmokeTest.ps1 exercises a SINGLE Defender Advanced Hunting
    preset, this wrapper drives the FULL dashboard export end-to-end through
    Invoke-AISolutionsExport.ps1 -IncludeSectionA and confirms the complete
    twelve-artifact dashboard contract:

        Section-A (Graph / Purview / Entra / catalog):
            EntraUsers.csv, ai_copilot_usage_graph.csv, ai_oauth_consents.csv,
            ai_sso_signins.csv, ai_solutions_catalog.csv
        MDA stubs (header-only create-if-missing):
            ai_appgov_alerts.csv, ai_cloud_discovery.csv, ai_mda_sessions.csv
        Defender Advanced Hunting:
            ai_activity_sessions.csv, ai_offhours_geo.csv,
            ai_client_channel.csv, ai_file_proximity.csv

    A PASS means the orchestrator:
        * completed without throwing, AND
        * produced every one of the twelve CSVs at -OutputDirectory, AND
        * each CSV's first line equals its expected header BYTE-EXACT
          (ordinal, case-sensitive comparison).

    A FAIL prints a per-file PASS/FAIL table naming every missing file and every
    header mismatch, plus HTTP-status guidance for the common 401 (bad/expired
    token) and 403 (missing consent) cases when the orchestrator throws.

    HEADER QUOTING NOTE. The eight Section-A + MDA-stub CSVs are written with
    unquoted headers (Export-Csv -UseQuotes AsNeeded / Set-Content literal). The
    four Defender CSVs are written by Export-DefenderAdvancedHunting.ps1 via the
    default Export-Csv (RFC-4180 quote-all), so their header fields are wrapped
    in double quotes. The embedded manifest reflects exactly what the producers
    emit; the underlying column names and order are identical for every artifact.

    NO secret, token, tenant id, client id, or client secret value is ever
    hardcoded or written to output. Secrets are accepted only as parameters
    (ClientSecret as a SecureString) and passed straight through, by reference,
    to the orchestrator.

.PARAMETER StartDate
    Inclusive start of the export window (half-open interval start), passed
    straight through to the orchestrator. Defaults to 2 days ago (local
    midnight).

.PARAMETER EndDate
    Exclusive end of the export window (half-open interval end), passed straight
    through to the orchestrator. Defaults to today (local midnight).

.PARAMETER OutputDirectory
    Directory that receives all twelve produced CSVs. Defaults to a unique
    subdirectory under the system temp directory. Created if it does not exist.

.PARAMETER AccessToken
    A pre-acquired Microsoft Graph bearer token. Never logged. Use this OR the
    -TenantId/-ClientId/-ClientSecret trio OR the three -*Executor test seams.

.PARAMETER TenantId
    Azure AD tenant id for client-credentials auth. Used only when no test seam
    and no -AccessToken are supplied.

.PARAMETER ClientId
    App registration (client) id for client-credentials auth.

.PARAMETER ClientSecret
    App registration client secret as a SecureString. Never logged.

.PARAMETER QueryExecutor
    INJECTION SEAM FOR TESTING (Defender Advanced Hunting). A scriptblock passed
    straight through to the orchestrator's -QueryExecutor. When supplied, the
    four Defender CSVs are produced with NO credentials and NO network calls.

.PARAMETER GraphQueryExecutor
    INJECTION SEAM FOR TESTING (Section-A Graph: EntraUsers, ai_oauth_consents,
    ai_sso_signins, ai_solutions_catalog). A scriptblock passed straight through
    to the orchestrator's -GraphQueryExecutor.

.PARAMETER PurviewSearchExecutor
    INJECTION SEAM FOR TESTING (Section-A Purview: ai_copilot_usage_graph). A
    scriptblock passed straight through to the orchestrator's
    -PurviewSearchExecutor.

.PARAMETER SkipOrchestration
    TEST / RE-VALIDATION SEAM. When set, the orchestrator run is SKIPPED and
    only the twelve-CSV byte-exact header validation of -OutputDirectory is
    performed. This re-validates an existing output directory (for example one
    produced by a prior run) without re-exporting, and requires NO credentials
    or test seams. Default off preserves the full live run-then-validate flow.

.EXAMPLE
    # (1) Interactive token: acquire a Graph token, then run the full export.
    Connect-MgGraph -Scopes 'ThreatHunting.Read.All','User.Read.All',`
        'AuditLog.Read.All','Directory.Read.All'
    $token = (Get-MgContext) ? (ConvertFrom-SecureString -AsPlainText `
        (Get-MgAccessToken)) : $null   # or use `az account get-access-token`
    .\Invoke-FullExportSmokeTest.ps1 -AccessToken $token `
        -StartDate '2026-05-01' -EndDate '2026-05-03'

.EXAMPLE
    # (2) App registration (client credentials) trio.
    $secret = Read-Host -AsSecureString 'Client secret'
    .\Invoke-FullExportSmokeTest.ps1 -TenantId $tid -ClientId $cid `
        -ClientSecret $secret -OutputDirectory .\dashboard_data

.EXAMPLE
    # (3) Credential-free, fully-mocked run using the three test seams.
    $ahMock      = { param($ctx) ...return preset-shaped rows... }
    $graphMock   = { param($ctx) ...return Graph value payloads... }
    $purviewMock = { param($ctx) ...return audit records... }
    .\Invoke-FullExportSmokeTest.ps1 `
        -QueryExecutor $ahMock -GraphQueryExecutor $graphMock `
        -PurviewSearchExecutor $purviewMock

.EXAMPLE
    # (4) Re-validate an already-populated output directory without exporting.
    .\Invoke-FullExportSmokeTest.ps1 -SkipOrchestration `
        -OutputDirectory .\dashboard_data

.NOTES
    Requires PowerShell 7+.

    Live (non-mock) permissions required on the identity used:
        * ThreatHunting.Read.All   (Defender Advanced Hunting -- 4 CSVs)
        * User.Read.All            (EntraUsers)
        * AuditLog.Read.All        (ai_oauth_consents, ai_sso_signins)
        * Application.Read.All     (ai_oauth_consents app resolution)
        * Directory.Read.All       (ai_sso_signins)
    All must be admin-consented.

    Live Section-A A2 (ai_copilot_usage_graph.csv) relies on the caller's
    AMBIENT Exchange Online session: run Connect-ExchangeOnline BEFORE this
    harness so the Purview audit search can execute. The three MDA CSVs are
    header-only stubs created by the orchestrator.

    A Defender CSV that returns ZERO rows is written as an EMPTY file by the
    exporter; because this harness validates the first line byte-exact, a
    genuinely empty tenant window will report that artifact as a header
    mismatch. Choose a window with known AI activity for a clean live PASS.

    Exit code: 0 on PASS (all twelve byte-exact), 1 on any FAIL.
#>
[CmdletBinding()]
param(
    [datetime]$StartDate = (Get-Date).Date.AddDays(-2),

    [datetime]$EndDate = (Get-Date).Date,

    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ("ah_fullexport_{0}" -f ([guid]::NewGuid().ToString('N')))),

    [string]$AccessToken,

    [string]$TenantId,

    [string]$ClientId,

    [securestring]$ClientSecret,

    [scriptblock]$QueryExecutor,

    [scriptblock]$GraphQueryExecutor,

    [scriptblock]$PurviewSearchExecutor,

    [switch]$SkipOrchestration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Fail {
    param([string]$Reason)
    Write-Host ("FULL-EXPORT SMOKE TEST: FAIL - {0}" -f $Reason) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Expected byte-exact header manifest (filename -> first line as ACTUALLY
# emitted by each producer). Section-A + MDA stubs are unquoted; the four
# Defender CSVs are RFC-4180 quote-all (Export-Csv default). Column names and
# order match every producing script / preset terminal projection.
# ---------------------------------------------------------------------------
$expectedHeaders = [ordered]@{
    'EntraUsers.csv'             = 'userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,hasLicense,assignedLicenses,manager_displayName,manager_userPrincipalName'
    'ai_copilot_usage_graph.csv' = 'UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate'
    'ai_oauth_consents.csv'      = 'UPN,AppName,YearMonth,ConsentCount,LastConsent,PermissionWeight,Permissions'
    'ai_sso_signins.csv'         = 'UPN,Application,YearMonth,SignInCount,DistinctDays,IsGuest,Countries,HasConditionalAccess,LastSignIn'
    'ai_solutions_catalog.csv'   = 'AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup'
    'ai_appgov_alerts.csv'       = 'Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description'
    'ai_cloud_discovery.csv'     = 'AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus'
    'ai_mda_sessions.csv'        = 'Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount'
    'ai_activity_sessions.csv'   = '"UPN","AISolution","YearMonth","Sessions","ActiveDays","EstimatedPrompts","DistinctDevices","Category","RiskTier"'
    'ai_offhours_geo.csv'        = '"UPN","YearMonth","TotalSessions","OffHoursSessions","OffHoursPct","DistinctCountries","AnomalousCountryCount","AnomalousCountries"'
    'ai_client_channel.csv'      = '"AISite","Channel","YearMonth","EventCount"'
    'ai_file_proximity.csv'      = '"Timestamp","UPN","AISolution","YearMonth","FileName","FolderCategory","FolderPath","SecondsToAI","NameMatchesSensitivePattern","FolderMatchesSensitive"'
}

Write-Host "==== AI Solutions FULL-EXPORT LIVE smoke test ====" -ForegroundColor Cyan
Write-Host ("Window          : {0} -> {1}" -f $StartDate.ToString('u'), $EndDate.ToString('u'))
Write-Host ("OutputDirectory : {0}" -f $OutputDirectory)

# ---------------------------------------------------------------------------
# Pre-flight validation (fail fast, before any auth). Skipped entirely in
# re-validation mode (-SkipOrchestration), which only inspects an existing
# -OutputDirectory and needs neither the orchestrator nor any credentials.
# ---------------------------------------------------------------------------
if (-not $SkipOrchestration) {
    $orchestrator = Join-Path $PSScriptRoot 'Invoke-AISolutionsExport.ps1'
    if (-not (Test-Path $orchestrator)) {
        Write-Fail "orchestrator not found at '$orchestrator'."
    }

    $hasQuerySeam   = ($null -ne $QueryExecutor)
    $hasGraphSeam   = ($null -ne $GraphQueryExecutor)
    $hasPurviewSeam = ($null -ne $PurviewSearchExecutor)
    $hasAnySeam     = $hasQuerySeam -or $hasGraphSeam -or $hasPurviewSeam

    $hasToken = -not [string]::IsNullOrWhiteSpace($AccessToken)
    $hasTrio  = (-not [string]::IsNullOrWhiteSpace($TenantId)) -and
                (-not [string]::IsNullOrWhiteSpace($ClientId)) -and
                ($null -ne $ClientSecret)

    if (-not ($hasAnySeam -or $hasToken -or $hasTrio)) {
        Write-Fail "no credentials or test seam supplied. Provide at least one of -QueryExecutor/-GraphQueryExecutor/-PurviewSearchExecutor (test), OR -AccessToken, OR -TenantId + -ClientId + -ClientSecret."
    }

    # -----------------------------------------------------------------------
    # Assemble pass-through parameters. Auth precedence: seams > AccessToken >
    # app-registration trio. Secrets forwarded by reference only; never logged.
    # -----------------------------------------------------------------------
    $orchestratorArgs = @{
        StartDate       = $StartDate
        EndDate         = $EndDate
        OutputDirectory = $OutputDirectory
        IncludeSectionA = $true
    }
    if ($hasAnySeam) {
        if ($hasQuerySeam)   { $orchestratorArgs['QueryExecutor']         = $QueryExecutor }
        if ($hasGraphSeam)   { $orchestratorArgs['GraphQueryExecutor']    = $GraphQueryExecutor }
        if ($hasPurviewSeam) { $orchestratorArgs['PurviewSearchExecutor'] = $PurviewSearchExecutor }
    }
    elseif ($hasToken) {
        $orchestratorArgs['AccessToken'] = $AccessToken
    }
    else {
        $orchestratorArgs['TenantId']     = $TenantId
        $orchestratorArgs['ClientId']     = $ClientId
        $orchestratorArgs['ClientSecret'] = $ClientSecret
    }

    $authLabel = if ($hasAnySeam) { 'test seam(s)' } elseif ($hasToken) { 'access token' } else { 'app-registration trio' }
    Write-Host ("Auth            : {0}" -f $authLabel)

    # -----------------------------------------------------------------------
    # Run the real orchestrator (full export, all twelve CSVs).
    # -----------------------------------------------------------------------
    try {
        & $orchestrator @orchestratorArgs | Out-Null
    }
    catch {
        $msg = $_.Exception.Message
        $guidance = ''
        if ($msg -match '\b401\b') {
            $guidance = ' (HTTP 401: the access token is missing, malformed, or expired - acquire a fresh token.)'
        }
        elseif ($msg -match '\b403\b') {
            $guidance = ' (HTTP 403: the identity lacks an admin-consented permission - grant and consent the required Graph scopes.)'
        }
        Write-Fail ("orchestrator threw: {0}{1}" -f $msg, $guidance)
    }
}
else {
    Write-Host "Mode            : re-validation only (-SkipOrchestration; orchestrator NOT run)"
}

# ---------------------------------------------------------------------------
# Validation: every one of the twelve CSVs must exist AND its first line must
# equal the manifest header byte-exact (ordinal comparison). Collect ALL
# failures; never stop at the first.
# ---------------------------------------------------------------------------
$results = [System.Collections.Generic.List[object]]::new()
foreach ($name in $expectedHeaders.Keys) {
    $expected = [string]$expectedHeaders[$name]
    $path = Join-Path $OutputDirectory $name

    if (-not (Test-Path $path)) {
        $results.Add([PSCustomObject]@{ File = $name; Pass = $false; Detail = 'MISSING FILE' })
        continue
    }

    $firstLine = Get-Content -LiteralPath $path -TotalCount 1
    if ($null -eq $firstLine) { $firstLine = '' }

    if ([string]::Equals([string]$firstLine, $expected, [System.StringComparison]::Ordinal)) {
        $results.Add([PSCustomObject]@{ File = $name; Pass = $true; Detail = 'header OK' })
    }
    else {
        $results.Add([PSCustomObject]@{ File = $name; Pass = $false; Detail = ("HEADER MISMATCH (got: {0})" -f $firstLine) })
    }
}

# ---------------------------------------------------------------------------
# Per-file PASS/FAIL table + verdict. Always print the summary before exiting.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==== full-export validation (12 CSVs) ====" -ForegroundColor White
$failCount = 0
foreach ($r in $results) {
    $tag = if ($r.Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($r.Pass) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Write-Host ("  {0}  {1,-28} {2}" -f $tag, $r.File, $r.Detail) -ForegroundColor $color
    if (-not $r.Pass) { $failCount++ }
}
Write-Host ""

if ($failCount -gt 0) {
    Write-Host ("FULL-EXPORT SMOKE TEST: FAIL ({0} of {1} artifacts failed validation)" -f $failCount, $results.Count) -ForegroundColor Red
    exit 1
}

Write-Host ("FULL-EXPORT SMOKE TEST: PASS (all {0} dashboard CSVs present with byte-exact headers)" -f $results.Count) -ForegroundColor Green
exit 0
