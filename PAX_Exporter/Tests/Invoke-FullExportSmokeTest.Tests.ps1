<#
    Invoke-FullExportSmokeTest.Tests.ps1

    CREDENTIAL-FREE test suite for the full-export harness
    Invoke-FullExportSmokeTest.ps1.

    The harness ends with `exit 0/1`, so every case runs it as a CHILD pwsh
    process and inspects the child's exit code (and captured stdout). No tenant,
    token, app-registration, or network access is required: the run-producing
    cases drive the three orchestrator injection seams (Defender AH, Section-A
    Graph, Section-A Purview) via a small runner script, exactly as
    Invoke-AISolutionsExport.Tests.ps1 case c6 does. The re-validation cases use
    the harness's -SkipOrchestration seam to validate a tampered output
    directory without re-exporting.

    Follows the SAME plain-PowerShell assertion style as the other Tests/*.ps1
    (run, assert, print PASS/FAIL per case, exit non-zero if ANY case fails,
    fixed Get-Random -SetSeed).

    Cases:
      h1. Happy path: all three mock seams produce all 13 CSVs with the exact
          manifest headers -> child exit 0 and a PASS verdict.
      h2. Missing file: after a good mocked run, delete one CSV, re-validate
          with -SkipOrchestration -> child exit 1 and that file flagged MISSING.
      h3. Header mismatch: after a good mocked run, corrupt one CSV's header
          line, re-validate with -SkipOrchestration -> child exit 1 and that
          file flagged HEADER MISMATCH.
      h4. No credentials / no seams: invoke with none of {seams, AccessToken,
          trio} -> child exit 1 and a pre-flight FAIL message.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed.
$null = Get-Random -SetSeed 20260725

$harnessPath = Join-Path $PSScriptRoot '..\Invoke-FullExportSmokeTest.ps1'
$harnessPath = (Resolve-Path $harnessPath).Path

# The thirteen dashboard artifacts (used for existence checks in the test).
$allArtifacts = @(
    'EntraUsers.csv','ai_copilot_usage_graph.csv','ai_copilot_surface_usage.csv','ai_oauth_consents.csv',
    'ai_sso_signins.csv','ai_solutions_catalog.csv','ai_appgov_alerts.csv',
    'ai_cloud_discovery.csv','ai_mda_sessions.csv','ai_activity_sessions.csv',
    'ai_offhours_geo.csv','ai_client_channel.csv','ai_file_proximity.csv'
)

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
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_fex_{0}_{1}" -f $Tag, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ---------------------------------------------------------------------------
# Runner script (written once). Defines the three credential-free mock seams
# and invokes the harness with them so all thirteen CSVs are produced. The mocks
# mirror Invoke-AISolutionsExport.Tests.ps1 case c6, except the Defender AH mock
# is KQL-dispatched to return each preset's EXACT terminal-projection columns so
# the produced Defender CSVs carry the byte-exact (quote-all) headers.
#
# The harness ends with `exit`, which terminates this runner process with the
# harness's exit code -- so `pwsh -File runner.ps1` yields the harness verdict.
# ---------------------------------------------------------------------------
$runnerScript = @'
param(
    [Parameter(Mandatory)][string]$HarnessPath,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$null = Get-Random -SetSeed 20260725

$ahMock = {
    param($ctx)
    $kql = [string]$ctx.Kql
    if ($kql.Contains('CloudAppEvents')) {
        return @([pscustomobject]@{ UPN='u@x'; AISolution='ChatGPT'; YearMonth='2026-05'; Sessions=3; ActiveDays=2; EstimatedPrompts=5; DistinctDevices=1; Category='General AI'; RiskTier='Conditional' })
    }
    if ($kql.Contains('EntraIdSignInEvents')) {
        return @([pscustomobject]@{ UPN='u@x'; YearMonth='2026-05'; TotalSessions=4; OffHoursSessions=1; OffHoursPct=0.25; DistinctCountries=1; AnomalousCountryCount=0; AnomalousCountries='' })
    }
    if ($kql.Contains('DeviceFileEvents')) {
        return @([pscustomobject]@{ Timestamp='2026-05-10T09:00:00Z'; UPN='u@x'; AISolution='ChatGPT'; YearMonth='2026-05'; FileName='a.docx'; FolderCategory='Documents'; FolderPath='C:\Users\u\Documents'; SecondsToAI=42; NameMatchesSensitivePattern=0; FolderMatchesSensitive=0 })
    }
    if ($kql.Contains('summarize EventCount = count() by AISite')) {
        return @([pscustomobject]@{ AISite='chatgpt.com'; Channel='Browser'; YearMonth='2026-05'; EventCount=7 })
    }
    return @([pscustomobject]@{ Col1='a'; Col2=1 })
}

$graphMock = {
    param($ctx)
    $uri = [string]$ctx.Uri
    if ($uri -like '*directoryAudits*') {
        return [pscustomobject]@{ value = @([pscustomobject]@{
            activityDateTime='2026-05-10T10:00:00Z'; activityDisplayName='Consent to application'
            initiatedBy=[pscustomobject]@{ user=[pscustomobject]@{ userPrincipalName='consenter@x' } }
            targetResources=@([pscustomobject]@{ type='ServicePrincipal'; displayName='OpenAI ChatGPT'
                modifiedProperties=@([pscustomobject]@{ displayName='DelegatedPermissionGrant.Scope'; newValue='Mail.Read User.Read' }) }) }) }
    }
    if ($uri -like '*signIns*') {
        return [pscustomobject]@{ value = @([pscustomobject]@{
            userPrincipalName='signer@x'; appDisplayName='GitHub Copilot'; createdDateTime='2026-05-12T09:00:00Z'
            location=[pscustomobject]@{ countryOrRegion='US' }; userType='Member'; conditionalAccessStatus='success'
            status=[pscustomobject]@{ errorCode=0 } }) }
    }
    return [pscustomobject]@{ value = @(
        [pscustomobject]@{ userPrincipalName='u1@x'; displayName='User One' },
        [pscustomobject]@{ userPrincipalName='u2@x'; displayName='User Two' }) }
}

$purviewMock = {
    param($ctx)
    if ($ctx.Page -eq 0) {
        $rec = [pscustomobject]@{ UserId='a@x'; CreationTime='2026-05-04T10:00:00Z'; Workload='Word' }
        return @([pscustomobject]@{ AuditData = ($rec | ConvertTo-Json -Compress -Depth 5) })
    }
    return @()
}

& $HarnessPath `
    -StartDate '2026-05-01T00:00:00' -EndDate '2026-06-01T00:00:00' `
    -OutputDirectory $OutputDirectory `
    -QueryExecutor $ahMock -GraphQueryExecutor $graphMock -PurviewSearchExecutor $purviewMock
'@

$runnerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_fex_runner_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
Set-Content -LiteralPath $runnerPath -Value $runnerScript -Encoding UTF8

# Run the mock-driven runner (produces all 13 CSVs) as a child pwsh process.
function Invoke-MockedRun {
    param([string]$OutputDirectory)
    $out = & pwsh -NoProfile -File $runnerPath -HarnessPath $harnessPath -OutputDirectory $OutputDirectory 2>&1 | Out-String
    return [PSCustomObject]@{ Code = $LASTEXITCODE; Out = $out }
}

# Run the harness directly (no mocks) as a child pwsh process, forwarding args.
function Invoke-Harness {
    param([string[]]$HarnessArgs)
    $out = & pwsh -NoProfile -File $harnessPath @HarnessArgs 2>&1 | Out-String
    return [PSCustomObject]@{ Code = $LASTEXITCODE; Out = $out }
}

try {
    # =======================================================================
    # CASE h1. Happy path -- all three seams -> all 13 CSVs, byte-exact -> 0.
    # =======================================================================
    Write-Host ""
    Write-Host "---- Case h1: mocked full run -> exit 0 + PASS verdict ----" -ForegroundColor Cyan
    try {
        $outH1 = New-TempOutDir 'h1'
        $r = Invoke-MockedRun -OutputDirectory $outH1
        $allExist = $true
        foreach ($f in $allArtifacts) { if (-not (Test-Path (Join-Path $outH1 $f))) { $allExist = $false } }
        $passH1 = ($r.Code -eq 0) -and ($r.Out -match 'FULL-EXPORT SMOKE TEST: PASS') -and $allExist
        Add-CaseResult -Name 'h1. mocked full run exits 0 with PASS verdict and all 13 CSVs present' -Pass $passH1 `
            -Detail ("code={0}; allExist={1}" -f $r.Code, $allExist)
    }
    catch {
        Add-CaseResult -Name 'h1. mocked full run exits 0 with PASS verdict and all 13 CSVs present' -Pass $false -Detail "threw: $($_.Exception.Message)"
    }

    # =======================================================================
    # CASE h2. Missing file -> delete one CSV, re-validate -> exit 1 + flagged.
    # =======================================================================
    Write-Host ""
    Write-Host "---- Case h2: delete one CSV, re-validate -> exit 1 + MISSING flag ----" -ForegroundColor Cyan
    try {
        $outH2 = New-TempOutDir 'h2'
        $r0 = Invoke-MockedRun -OutputDirectory $outH2
        $deleted = 'ai_sso_signins.csv'
        Remove-Item -LiteralPath (Join-Path $outH2 $deleted) -Force

        $r = Invoke-Harness -HarnessArgs @('-SkipOrchestration', '-OutputDirectory', $outH2)
        $flagged = ($r.Out -match [regex]::Escape($deleted)) -and ($r.Out -match 'MISSING FILE')
        $passH2 = ($r0.Code -eq 0) -and ($r.Code -eq 1) -and $flagged
        Add-CaseResult -Name 'h2. deleted CSV re-validation exits 1 and flags the missing file' -Pass $passH2 `
            -Detail ("setupCode={0}; code={1}; flagged={2}" -f $r0.Code, $r.Code, $flagged)
    }
    catch {
        Add-CaseResult -Name 'h2. deleted CSV re-validation exits 1 and flags the missing file' -Pass $false -Detail "threw: $($_.Exception.Message)"
    }

    # =======================================================================
    # CASE h3. Header mismatch -> corrupt one header, re-validate -> 1 + flag.
    # =======================================================================
    Write-Host ""
    Write-Host "---- Case h3: corrupt one header, re-validate -> exit 1 + MISMATCH flag ----" -ForegroundColor Cyan
    try {
        $outH3 = New-TempOutDir 'h3'
        $r0 = Invoke-MockedRun -OutputDirectory $outH3
        $corrupted = 'ai_client_channel.csv'
        $cp = Join-Path $outH3 $corrupted
        $lines = @(Get-Content -LiteralPath $cp)
        if ($lines.Count -gt 0) { $lines[0] = 'BROKEN,HEADER,LINE,EventCount' } else { $lines = @('BROKEN,HEADER,LINE,EventCount') }
        Set-Content -LiteralPath $cp -Value $lines -Encoding UTF8

        $r = Invoke-Harness -HarnessArgs @('-SkipOrchestration', '-OutputDirectory', $outH3)
        $flagged = ($r.Out -match [regex]::Escape($corrupted)) -and ($r.Out -match 'HEADER MISMATCH')
        $passH3 = ($r0.Code -eq 0) -and ($r.Code -eq 1) -and $flagged
        Add-CaseResult -Name 'h3. corrupted header re-validation exits 1 and flags the header mismatch' -Pass $passH3 `
            -Detail ("setupCode={0}; code={1}; flagged={2}" -f $r0.Code, $r.Code, $flagged)
    }
    catch {
        Add-CaseResult -Name 'h3. corrupted header re-validation exits 1 and flags the header mismatch' -Pass $false -Detail "threw: $($_.Exception.Message)"
    }

    # =======================================================================
    # CASE h4. No credentials / no seams -> pre-flight FAIL -> exit 1.
    # =======================================================================
    Write-Host ""
    Write-Host "---- Case h4: no seams / no creds -> pre-flight FAIL + exit 1 ----" -ForegroundColor Cyan
    try {
        $outH4 = New-TempOutDir 'h4'
        $r = Invoke-Harness -HarnessArgs @('-OutputDirectory', $outH4)
        $preflight = ($r.Out -match 'no credentials or test seam') -and ($r.Out -match 'FULL-EXPORT SMOKE TEST: FAIL')
        $passH4 = ($r.Code -eq 1) -and $preflight
        Add-CaseResult -Name 'h4. no seams/creds triggers pre-flight FAIL and exit 1' -Pass $passH4 `
            -Detail ("code={0}; preflightMsg={1}" -f $r.Code, $preflight)
    }
    catch {
        Add-CaseResult -Name 'h4. no seams/creds triggers pre-flight FAIL and exit 1' -Pass $false -Detail "threw: $($_.Exception.Message)"
    }
}
finally {
    Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== FULL-EXPORT SMOKE TEST HARNESS RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} harness cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
