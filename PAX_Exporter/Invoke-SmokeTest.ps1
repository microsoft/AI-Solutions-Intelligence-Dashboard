<#
.SYNOPSIS
    LIVE smoke test for Export-DefenderAdvancedHunting.ps1: runs the REAL
    exporter against a small recent window and prints a clear PASS/FAIL verdict.

.DESCRIPTION
    Unlike the credential-free unit/edge-case suites (which use the
    -QueryExecutor mock seam), this wrapper exercises the real Microsoft Graph
    path end-to-end. Run it ONCE a real tenant token or app registration is
    available to confirm connectivity, authentication, and CSV output.

    A PASS means the exporter:
        * completed without throwing, AND
        * produced a CSV artifact at -OutputPath, AND
        * returned a summary object.
    Zero rows is an ACCEPTABLE result for the smoke test (an empty but valid
    artifact still proves the pipeline works).

    A FAIL prints the underlying reason, including HTTP-status guidance for the
    common 401 (bad/expired token) and 403 (missing consent) cases.

    NO secret, token, tenant id, client id, or client secret value is ever
    hardcoded or written to output. Secrets are accepted only as parameters
    (ClientSecret as a SecureString) and passed straight through to the
    exporter.

.PARAMETER StartDate
    Inclusive start of the smoke-test window (half-open interval start).
    Defaults to 2 days ago (local midnight).

.PARAMETER EndDate
    Exclusive end of the smoke-test window (half-open interval end).
    Defaults to today (local midnight).

.PARAMETER QueryPresetPath
    Path to a KQL preset file containing the literal {TIMEFILTER} token.
    Defaults to the bundled presets\CloudAppEvents_ai_activity_sessions.kql.

.PARAMETER OutputPath
    Path to the CSV artifact the smoke test writes. Defaults to a unique file
    under the system temp directory.

.PARAMETER TimeColumn
    Time column used for filtering / subdivision. Defaults to 'Timestamp'.

.PARAMETER AccessToken
    A pre-acquired Microsoft Graph bearer token. Never logged. Use this OR the
    -TenantId/-ClientId/-ClientSecret trio.

.PARAMETER TenantId
    Azure AD tenant id for client-credentials auth. Used only when -AccessToken
    is not supplied.

.PARAMETER ClientId
    App registration (client) id for client-credentials auth.

.PARAMETER ClientSecret
    App registration client secret as a SecureString. Never logged.

.EXAMPLE
    # Smoke test with a pre-acquired token over the default (last 2 days) window.
    .\Invoke-SmokeTest.ps1 -AccessToken $env:GRAPH_TOKEN

.EXAMPLE
    # Smoke test with an app registration (client credentials).
    $secret = Read-Host -AsSecureString 'Client secret'
    .\Invoke-SmokeTest.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret `
        -StartDate '2026-07-01' -EndDate '2026-07-03'

.NOTES
    Requires PowerShell 7+ and Microsoft Graph permission
    ThreatHunting.Read.All granted (admin-consented) to the identity used.
    Exit code: 0 on PASS, 1 on FAIL.
#>
[CmdletBinding()]
param(
    [datetime]$StartDate = (Get-Date).Date.AddDays(-2),

    [datetime]$EndDate = (Get-Date).Date,

    [string]$QueryPresetPath = (Join-Path $PSScriptRoot 'presets\CloudAppEvents_ai_activity_sessions.kql'),

    [string]$OutputPath = (Join-Path ([System.IO.Path]::GetTempPath()) ("ah_smoketest_{0}.csv" -f ([guid]::NewGuid().ToString('N')))),

    [string]$TimeColumn = 'Timestamp',

    [string]$AccessToken,

    [string]$TenantId,

    [string]$ClientId,

    [securestring]$ClientSecret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Fail {
    param([string]$Reason)
    Write-Host ("SMOKE TEST: FAIL - {0}" -f $Reason) -ForegroundColor Red
    exit 1
}

Write-Host "==== Export-DefenderAdvancedHunting LIVE smoke test ====" -ForegroundColor Cyan
Write-Host ("Window     : {0} -> {1}" -f $StartDate.ToString('u'), $EndDate.ToString('u'))
Write-Host ("Preset     : {0}" -f $QueryPresetPath)
Write-Host ("OutputPath : {0}" -f $OutputPath)

# --- Pre-flight validation (fail fast, before any auth) --------------------
$exporter = Join-Path $PSScriptRoot 'Export-DefenderAdvancedHunting.ps1'
if (-not (Test-Path $exporter)) {
    Write-Fail "exporter not found at '$exporter'"
}
if (-not (Test-Path $QueryPresetPath)) {
    Write-Fail "KQL preset not found at '$QueryPresetPath'"
}

$hasToken = -not [string]::IsNullOrWhiteSpace($AccessToken)
$hasAppReg = (-not [string]::IsNullOrWhiteSpace($TenantId)) -and
             (-not [string]::IsNullOrWhiteSpace($ClientId)) -and
             ($null -ne $ClientSecret)
if (-not ($hasToken -or $hasAppReg)) {
    Write-Fail "no credentials supplied. Provide -AccessToken OR -TenantId + -ClientId + -ClientSecret (app registration with Graph ThreatHunting.Read.All)."
}

$kql = Get-Content -Path $QueryPresetPath -Raw
if ($kql -notmatch '\{TIMEFILTER\}') {
    Write-Fail "preset '$QueryPresetPath' does not contain the required {TIMEFILTER} token."
}

# --- Assemble pass-through parameters (secrets passed by reference only) ----
$exporterArgs = @{
    Query      = $kql
    StartDate  = $StartDate
    EndDate    = $EndDate
    TimeColumn = $TimeColumn
    OutputPath = $OutputPath
}
if ($hasToken) {
    $exporterArgs['AccessToken'] = $AccessToken
}
else {
    $exporterArgs['TenantId'] = $TenantId
    $exporterArgs['ClientId'] = $ClientId
    $exporterArgs['ClientSecret'] = $ClientSecret
}

# --- Run the real exporter --------------------------------------------------
$summary = $null
try {
    $summary = & $exporter @exporterArgs
}
catch {
    $msg = $_.Exception.Message
    $guidance = ''
    if ($msg -match '\b401\b') {
        $guidance = ' (HTTP 401: the access token is missing, malformed, or expired - acquire a fresh token.)'
    }
    elseif ($msg -match '\b403\b') {
        $guidance = ' (HTTP 403: the identity lacks admin-consented ThreatHunting.Read.All - grant and consent the permission.)'
    }
    Write-Fail ("exporter threw: {0}{1}" -f $msg, $guidance)
}

# --- Evaluate verdict -------------------------------------------------------
if ($null -eq $summary) {
    Write-Fail "exporter returned no summary object."
}
if (-not (Test-Path $OutputPath)) {
    Write-Fail "no CSV artifact was produced at '$OutputPath'."
}

$rowCount = 'unknown'
try { $rowCount = $summary.TotalRows } catch { }

Write-Host ""
Write-Host "==== smoke-test summary ====" -ForegroundColor White
Write-Host ("TotalRows          : {0}" -f $rowCount)
try { Write-Host ("PartitionsExecuted : {0}" -f $summary.PartitionsExecuted) } catch { }
try { Write-Host ("SubdivisionEvents  : {0}" -f $summary.SubdivisionEvents) } catch { }
try { Write-Host ("MinWindowHit       : {0}" -f $summary.MinWindowHit) } catch { }
Write-Host ("Artifact           : {0}" -f $OutputPath)
Write-Host ""

# 0 rows is acceptable: an empty but valid artifact still proves the pipeline.
Write-Host ("SMOKE TEST: PASS (completed, artifact written, summary returned; TotalRows={0})" -f $rowCount) -ForegroundColor Green
exit 0
