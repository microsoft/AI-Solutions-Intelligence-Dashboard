<#
    Invoke-AISolutionsExport.Tests.ps1

    CREDENTIAL-FREE integration test for the slice-C orchestrator
    Invoke-AISolutionsExport.ps1.

    Exercises the orchestrator end-to-end through the injectable -QueryExecutor
    mock seam, so NO tenant, token, app-registration, or network access is
    required. Follows the SAME plain-PowerShell assertion style as
    Preset.ClientChannel.Tests.ps1 (run, assert, print PASS/FAIL per case, exit
    non-zero if ANY case fails, fixed Get-Random -SetSeed).

    The mock scriptblock is captured via .GetNewClosure() over a LOCAL
    List[object] (a reference-type List, so the closure and the test share the
    SAME object). The exporter invokes the mock via `& $QueryExecutor`, so a
    $script: lookup would resolve against the EXPORTER's scope; a closure over a
    local List keeps the capture bound to THIS test.

    Cases:
      c1. Full artifact set produced -- all SEVEN files exist (4 real CSVs +
          3 MDA stubs) after a run with stubs enabled.
      c2. Orchestrator config wiring + invocation coverage -- the returned
          summary's .Presets array carries the per-artifact UserBucketColumn the
          orchestrator wired (activity_sessions/offhours_geo -> 'UPN';
          client_channel/file_proximity -> empty/null), AND the captured calls
          prove the orchestrator invoked the exporter for all four presets
          (each KQL classifier matched at least one call). This verifies the
          orchestrator's -UserBucketColumn WIRING, not the exporter's runtime
          $ctx.BucketColumn (which only becomes 'UPN' on window saturation and
          stays '' for a small non-saturating mock).
      c3. Stub header fidelity -- each of the 3 stub files, trimmed, EQUALS its
          exact expected header string and contains exactly one non-empty line.
      c4. Stub create-if-missing (non-clobber) -- a pre-seeded MDA CSV keeps its
          real data row (is NOT overwritten by a header-only stub).
      c5. Auth/seam guard -- invoking with NEITHER -QueryExecutor NOR any auth
          THROWS.
      c10. No-MDA path -- -SkipActivitySessions writes its exact stub, does not
          invoke CloudAppEvents, and still runs the other three presets.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed.
$null = Get-Random -SetSeed 20260605

$scriptPath = Join-Path $PSScriptRoot '..\Invoke-AISolutionsExport.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

# One-calendar-month window keeps Month-mode partitioning small. LOCAL literals
# (no 'Z') so the range is exactly one calendar month regardless of timezone.
$startDate = [datetime]'2026-05-01T00:00:00'
$endDate   = [datetime]'2026-06-01T00:00:00'

# Exact expected stub headers (byte-for-byte, from the ASSUMPTIONS table).
$expectedStubs = [ordered]@{
    'ai_appgov_alerts.csv'   = 'Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description'
    'ai_cloud_discovery.csv' = 'AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus'
    'ai_mda_sessions.csv'    = 'Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount'
}
$activitySessionsHeader = 'UPN,AISolution,YearMonth,Sessions,ActiveDays,EstimatedPrompts,DistinctDevices,Category,RiskTier'

$realArtifacts = @(
    'ai_activity_sessions.csv',
    'ai_offhours_geo.csv',
    'ai_client_channel.csv',
    'ai_file_proximity.csv'
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
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_orch_{0}_{1}" -f $Tag, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# Classify a captured KQL string to one of the four presets.
function Get-PresetClass {
    param([string]$Kql)
    if ($Kql.Contains('CloudAppEvents')) { return 'activity_sessions' }
    if ($Kql.Contains('EntraIdSignInEvents')) { return 'offhours_geo' }
    if ($Kql.Contains('DeviceFileEvents')) { return 'file_proximity' }
    if ($Kql.Contains('summarize EventCount = count() by AISite')) { return 'client_channel' }
    return 'unknown'
}

function New-MockAhRows {
    param([string]$Kql, [int]$Count = 2)
    $class = Get-PresetClass -Kql $Kql
    for ($i = 1; $i -le $Count; $i++) {
        switch ($class) {
            'activity_sessions' {
                [PSCustomObject]@{ UPN="u$i@x"; AISolution='ChatGPT'; YearMonth='2026-05'; Sessions=1; ActiveDays=1; EstimatedPrompts=1; DistinctDevices=1; Category='General AI'; RiskTier='Conditional' }
            }
            'offhours_geo' {
                [PSCustomObject]@{ UPN="u$i@x"; YearMonth='2026-05'; TotalSessions=1; OffHoursSessions=0; OffHoursPct=0; DistinctCountries=1; AnomalousCountryCount=0; AnomalousCountries='' }
            }
            'file_proximity' {
                [PSCustomObject]@{ Timestamp="2026-05-0${i}T00:00:00Z"; UPN="u$i@x"; AISolution='ChatGPT'; YearMonth='2026-05'; FileName="f$i.docx"; FolderCategory='Documents'; FolderPath='C:\Documents'; SecondsToAI=1; NameMatchesSensitivePattern=0; FolderMatchesSensitive=0 }
            }
            'client_channel' {
                [PSCustomObject]@{ AISite="site$i.example"; Channel='Browser'; YearMonth='2026-05'; EventCount=1 }
            }
            default {
                throw 'Unknown preset in test mock.'
            }
        }
    }
}

# ===========================================================================
# CASE c1. Full artifact set produced (4 real CSVs + 3 stubs = 7 files).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c1: full artifact set produced (7 files) ----" -ForegroundColor Cyan

# This captured list backs c1's own assertions; c2 does its own capturing run.
$capturedC1 = [System.Collections.Generic.List[object]]::new()
$outC1 = $null
try {
    $c1Mock = {
        param($ctx)
        $capturedC1.Add([PSCustomObject]@{ Kql = [string]$ctx.Kql; BucketColumn = [string]$ctx.BucketColumn })
        return @(New-MockAhRows -Kql ([string]$ctx.Kql))
    }.GetNewClosure()

    $outC1 = New-TempOutDir 'c1'
    & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC1 `
        -QueryExecutor $c1Mock `
        -WarningAction SilentlyContinue | Out-Null

    $expectedFiles = @()
    $expectedFiles += $realArtifacts
    $expectedFiles += ([string[]]$expectedStubs.Keys)

    $missing = @()
    foreach ($f in $expectedFiles) {
        $fp = Join-Path $outC1 $f
        if (-not (Test-Path $fp)) { $missing += $f }
    }
    $passC1 = ($missing.Count -eq 0)
    $missingLabel = if ($missing.Count -gt 0) { ($missing -join ',') } else { 'none' }
    Add-CaseResult -Name 'c1. all 7 dashboard files produced (4 real + 3 stub)' -Pass $passC1 `
        -Detail ("expected=7; missing={0}" -f $missingLabel)
}
catch {
    Add-CaseResult -Name 'c1. all 7 dashboard files produced (4 real + 3 stub)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c2. Orchestrator config wiring + invocation coverage.
#   (1) The returned summary's .Presets array carries the per-artifact
#       UserBucketColumn the orchestrator WIRED:
#         ai_activity_sessions.csv / ai_offhours_geo.csv -> 'UPN'
#         ai_client_channel.csv    / ai_file_proximity.csv -> empty ('' or $null)
#   (2) The captured calls prove the orchestrator invoked the exporter for all
#       four presets (each KQL classifier matched at least one call).
#   NOTE: this verifies the orchestrator's -UserBucketColumn WIRING, not the
#   exporter's runtime $ctx.BucketColumn -- the exporter only sets
#   BucketColumn='UPN' when a window saturates (>= RowCap), so a small
#   non-saturating mock leaves $ctx.BucketColumn '' on every call. The wiring is
#   what Slice C must verify, and the orchestrator surfaces it on the summary.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c2: orchestrator UserBucketColumn wiring + all four presets invoked ----" -ForegroundColor Cyan
try {
    # Own run with the same capturing mock; capture the RETURNED summary object
    # (do NOT pipe to Out-Null -- we need .Presets).
    $capturedC2 = [System.Collections.Generic.List[object]]::new()
    $c2Mock = {
        param($ctx)
        $capturedC2.Add([PSCustomObject]@{ Kql = [string]$ctx.Kql })
        return @(New-MockAhRows -Kql ([string]$ctx.Kql))
    }.GetNewClosure()

    $outC2 = New-TempOutDir 'c2'
    $summaryC2 = & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC2 `
        -QueryExecutor $c2Mock `
        -WarningAction SilentlyContinue

    # (1) CONFIG WIRING via the returned summary's .Presets array. UserBucketColumn
    #     is '' for non-bucketed presets (accept '' or $null as empty).
    $ps = $summaryC2.Presets
    $asE = @($ps | Where-Object { $_.Artifact -eq 'ai_activity_sessions.csv' })
    $ogE = @($ps | Where-Object { $_.Artifact -eq 'ai_offhours_geo.csv' })
    $ccE = @($ps | Where-Object { $_.Artifact -eq 'ai_client_channel.csv' })
    $fpE = @($ps | Where-Object { $_.Artifact -eq 'ai_file_proximity.csv' })

    $asOk = ($asE.Count -eq 1) -and ($asE[0].UserBucketColumn -eq 'UPN')
    $ogOk = ($ogE.Count -eq 1) -and ($ogE[0].UserBucketColumn -eq 'UPN')
    $ccOk = ($ccE.Count -eq 1) -and [string]::IsNullOrEmpty([string]$ccE[0].UserBucketColumn)
    $fpOk = ($fpE.Count -eq 1) -and [string]::IsNullOrEmpty([string]$fpE[0].UserBucketColumn)
    $wiringOk = $asOk -and $ogOk -and $ccOk -and $fpOk

    # Safe display values (avoid indexing a missing entry in the detail string).
    $asVal = if ($asE.Count -eq 1) { $asE[0].UserBucketColumn } else { '<missing>' }
    $ogVal = if ($ogE.Count -eq 1) { $ogE[0].UserBucketColumn } else { '<missing>' }
    $ccVal = if ($ccE.Count -eq 1) { "'$($ccE[0].UserBucketColumn)'" } else { '<missing>' }
    $fpVal = if ($fpE.Count -eq 1) { "'$($fpE[0].UserBucketColumn)'" } else { '<missing>' }

    # (2) INVOCATION COVERAGE via the captured calls (each classifier matched >=1).
    $seen = @{ activity_sessions = 0; offhours_geo = 0; file_proximity = 0; client_channel = 0; unknown = 0 }
    foreach ($call in $capturedC2) {
        $cls = Get-PresetClass -Kql $call.Kql
        $seen[$cls]++
    }
    $allFour = ($seen['activity_sessions'] -gt 0) -and ($seen['offhours_geo'] -gt 0) -and
               ($seen['file_proximity'] -gt 0) -and ($seen['client_channel'] -gt 0)

    $passC2 = $wiringOk -and $allFour
    Add-CaseResult -Name 'c2. orchestrator wires per-preset UserBucketColumn (activity/offhours=UPN, client/file=none) and invokes all four presets' -Pass $passC2 `
        -Detail ("wiringOk={0} (as={1},og={2},cc={3},fp={4}); allFour={5}; calls: as={6},og={7},fp={8},cc={9},unknown={10}" -f `
            $wiringOk, $asVal, $ogVal, $ccVal, $fpVal, `
            $allFour, $seen['activity_sessions'], $seen['offhours_geo'], $seen['file_proximity'], $seen['client_channel'], $seen['unknown'])
}
catch {
    Add-CaseResult -Name 'c2. orchestrator wires per-preset UserBucketColumn (activity/offhours=UPN, client/file=none) and invokes all four presets' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c3. Stub header fidelity (reuses c1's out dir).
#   Each stub, trimmed, EQUALS its exact expected header AND has exactly one
#   non-empty line.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c3: stub header fidelity (exact header, one non-empty line) ----" -ForegroundColor Cyan
try {
    $allMatch = $true
    $details = @()
    foreach ($name in $expectedStubs.Keys) {
        $expected = $expectedStubs[$name]
        $fp = Join-Path $outC1 $name
        $content = Get-Content -LiteralPath $fp -Raw
        $trimmedEq = ($content.Trim() -ceq $expected)
        $nonEmpty = @($content -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
        $oneLine = ($nonEmpty.Count -eq 1)
        if (-not ($trimmedEq -and $oneLine)) { $allMatch = $false }
        $details += ("{0}(eq={1},lines={2})" -f $name, $trimmedEq, $nonEmpty.Count)
    }
    Add-CaseResult -Name 'c3. stub header fidelity (byte-exact header, one line)' -Pass $allMatch `
        -Detail ($details -join '; ')
}
catch {
    Add-CaseResult -Name 'c3. stub header fidelity (byte-exact header, one line)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c4. Stub create-if-missing (non-clobber).
#   Pre-seed ai_appgov_alerts.csv with header + a real data row; run; assert the
#   seeded row survives while the other two stubs get created.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c4: stub create-if-missing (non-clobber) ----" -ForegroundColor Cyan
try {
    $outC4 = New-TempOutDir 'c4'
    $seededHeader = $expectedStubs['ai_appgov_alerts.csv']
    $seededRow = '2026-05-15T09:00:00Z,2026-05,user@contoso.com,ChatGPT,DataExfil,High,Seeded real row'
    $seededPath = Join-Path $outC4 'ai_appgov_alerts.csv'
    [System.IO.File]::WriteAllText($seededPath, ($seededHeader + "`n" + $seededRow + "`n"))

    $capturedC4 = [System.Collections.Generic.List[object]]::new()
    $c4Mock = {
        param($ctx)
        $capturedC4.Add([PSCustomObject]@{ Kql = [string]$ctx.Kql; BucketColumn = [string]$ctx.BucketColumn })
        return @(New-MockAhRows -Kql ([string]$ctx.Kql) -Count 1)
    }.GetNewClosure()

    & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC4 `
        -QueryExecutor $c4Mock `
        -WarningAction SilentlyContinue | Out-Null

    $afterContent = Get-Content -LiteralPath $seededPath -Raw
    $seedSurvived = $afterContent.Contains($seededRow)
    $otherTwoCreated = (Test-Path (Join-Path $outC4 'ai_cloud_discovery.csv')) -and
                       (Test-Path (Join-Path $outC4 'ai_mda_sessions.csv'))
    $passC4 = $seedSurvived -and $otherTwoCreated
    Add-CaseResult -Name 'c4. stub create-if-missing (seeded MDA row not clobbered)' -Pass $passC4 `
        -Detail ("seedSurvived={0}; otherTwoCreated={1}" -f $seedSurvived, $otherTwoCreated)
}
catch {
    Add-CaseResult -Name 'c4. stub create-if-missing (seeded MDA row not clobbered)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c5. Auth/seam guard (no executor, no auth -> throws).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c5: auth/seam guard (no executor, no auth -> throws) ----" -ForegroundColor Cyan
try {
    $outC5 = New-TempOutDir 'c5'
    $threwC5 = $false
    try {
        & $scriptPath `
            -StartDate $startDate -EndDate $endDate `
            -OutputDirectory $outC5 `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwC5 = $true
    }
    Add-CaseResult -Name 'c5. auth/seam guard throws with no credentials' -Pass $threwC5 `
        -Detail ("threw={0}" -f $threwC5)
}
catch {
    Add-CaseResult -Name 'c5. auth/seam guard throws with no credentials' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Section-A shared fixtures (cases c6-c9). The six Section-A artifacts, plus
# the three injectable mock seams used to drive the -IncludeSectionA path with
# NO tenant / token / network access:
#   * $ahMock       -> existing Defender-AH -QueryExecutor seam (as in c1).
#   * $graphMock    -> Section-A Graph -QueryExecutor seam, URI-dispatched so
#                      A1 (/users), A3 (directoryAudits), A4 (signIns) each
#                      return data. A5 catalog is a static seed (always written).
#   * $purviewMock  -> Section-A Purview -SearchExecutor seam (page-keyed audit
#                      records whose .AuditData is a JSON string).
# ===========================================================================
$sectionAArtifacts = @(
    'EntraUsers.csv',
    'ai_solutions_catalog.csv',
    'ai_oauth_consents.csv',
    'ai_sso_signins.csv',
    'ai_copilot_usage_graph.csv',
    'ai_copilot_surface_usage.csv'
)

$ahMock = {
    param($ctx)
    return @(New-MockAhRows -Kql ([string]$ctx.Kql))
}

$graphMock = {
    param($ctx)
    $uri = [string]$ctx.Uri
    if ($uri -like '*directoryAudits*') {
        return [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    activityDateTime    = '2026-05-10T10:00:00Z'
                    activityDisplayName = 'Consent to application'
                    initiatedBy         = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'consenter@x' } }
                    targetResources     = @(
                        [pscustomobject]@{
                            type               = 'ServicePrincipal'
                            displayName        = 'OpenAI ChatGPT'
                            modifiedProperties = @(
                                [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.Scope'; newValue = 'Mail.Read User.Read' }
                            )
                        }
                    )
                }
            )
        }
    }
    if ($uri -like '*signIns*') {
        return [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    userPrincipalName       = 'signer@x'
                    appDisplayName          = 'GitHub Copilot'
                    createdDateTime         = '2026-05-12T09:00:00Z'
                    location                = [pscustomobject]@{ countryOrRegion = 'US' }
                    userType                = 'Member'
                    conditionalAccessStatus = 'success'
                    status                  = [pscustomobject]@{ errorCode = 0 }
                }
            )
        }
    }
    # Default: the A1 /users pull.
    return [pscustomobject]@{
        value = @(
            [pscustomobject]@{ userPrincipalName = 'u1@x'; displayName = 'User One' },
            [pscustomobject]@{ userPrincipalName = 'u2@x'; displayName = 'User Two' }
        )
    }
}

$purviewMock = {
    param($ctx)
    if ($ctx.Page -eq 0) {
        $rec = [pscustomobject]@{ UserId = 'a@x'; CreationTime = '2026-05-04T10:00:00Z'; Workload = 'Word' }
        $json = $rec | ConvertTo-Json -Compress -Depth 5
        return @([pscustomobject]@{ AuditData = $json })
    }
    return @()
}

# ===========================================================================
# CASE c6. -IncludeSectionA with all three seams -> all THIRTEEN files exist
#   (4 real + 3 stub + 6 Section-A).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c6: -IncludeSectionA produces all 13 dashboard files ----" -ForegroundColor Cyan
try {
    $outC6 = New-TempOutDir 'c6'
    & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC6 `
        -QueryExecutor $ahMock `
        -IncludeSectionA `
        -GraphQueryExecutor $graphMock `
        -PurviewSearchExecutor $purviewMock `
        -WarningAction SilentlyContinue | Out-Null

    $expectedC6 = @()
    $expectedC6 += $realArtifacts
    $expectedC6 += ([string[]]$expectedStubs.Keys)
    $expectedC6 += $sectionAArtifacts

    $missingC6 = @()
    foreach ($f in $expectedC6) {
        if (-not (Test-Path (Join-Path $outC6 $f))) { $missingC6 += $f }
    }
    $passC6 = ($missingC6.Count -eq 0) -and ($expectedC6.Count -eq 13)
    $missingLabelC6 = if ($missingC6.Count -gt 0) { ($missingC6 -join ',') } else { 'none' }
    Add-CaseResult -Name 'c6. -IncludeSectionA emits all 13 dashboard CSVs (4 real + 3 stub + 6 Section-A)' -Pass $passC6 `
        -Detail ("expected={0}; missing={1}" -f $expectedC6.Count, $missingLabelC6)
}
catch {
    Add-CaseResult -Name 'c6. -IncludeSectionA emits all 13 dashboard CSVs (4 real + 3 stub + 6 Section-A)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c7. Backward-compat: WITHOUT -IncludeSectionA, none of the 6 Section-A
#   files are produced (only the 7 baseline files present).
# ===========================================================================
Write-Host ""
Write-Host "---- Case c7: default run produces NO Section-A files (backward-compat) ----" -ForegroundColor Cyan
try {
    $outC7 = New-TempOutDir 'c7'
    & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC7 `
        -QueryExecutor $ahMock `
        -WarningAction SilentlyContinue | Out-Null

    $presentSectionA = @()
    foreach ($f in $sectionAArtifacts) {
        if (Test-Path (Join-Path $outC7 $f)) { $presentSectionA += $f }
    }
    $passC7 = ($presentSectionA.Count -eq 0)
    Add-CaseResult -Name 'c7. default (no -IncludeSectionA) writes zero Section-A files' -Pass $passC7 `
        -Detail ("sectionAFilesPresent={0}" -f $presentSectionA.Count)
}
catch {
    Add-CaseResult -Name 'c7. default (no -IncludeSectionA) writes zero Section-A files' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c8. Return-object surface for Section-A.
#   (1) With -IncludeSectionA: .SectionAIncluded -eq $true AND .SectionA's
#       GraphResult and CopilotResult are both non-null.
#   (2) Without -IncludeSectionA: .SectionAIncluded -eq $false AND .SectionA is
#       $null.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c8: summary surfaces SectionAIncluded + SectionA results ----" -ForegroundColor Cyan
try {
    $outC8a = New-TempOutDir 'c8a'
    $summaryC8a = & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC8a `
        -QueryExecutor $ahMock `
        -IncludeSectionA `
        -GraphQueryExecutor $graphMock `
        -PurviewSearchExecutor $purviewMock `
        -WarningAction SilentlyContinue

    $incOk    = ($summaryC8a.SectionAIncluded -eq $true)
    $graphOk  = ($null -ne $summaryC8a.SectionA) -and ($null -ne $summaryC8a.SectionA.GraphResult)
    $copiOk   = ($null -ne $summaryC8a.SectionA) -and ($null -ne $summaryC8a.SectionA.CopilotResult)

    $outC8b = New-TempOutDir 'c8b'
    $summaryC8b = & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC8b `
        -QueryExecutor $ahMock `
        -WarningAction SilentlyContinue

    $offOk  = ($summaryC8b.SectionAIncluded -eq $false)
    $nullOk = ($null -eq $summaryC8b.SectionA)

    $passC8 = $incOk -and $graphOk -and $copiOk -and $offOk -and $nullOk
    Add-CaseResult -Name 'c8. summary SectionAIncluded/SectionA reflects -IncludeSectionA on and off' -Pass $passC8 `
        -Detail ("on(inc={0},graph={1},copilot={2}); off(inc=false?{3},null?{4})" -f $incOk, $graphOk, $copiOk, $offOk, $nullOk)
}
catch {
    Add-CaseResult -Name 'c8. summary SectionAIncluded/SectionA reflects -IncludeSectionA on and off' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c9. Section-A Graph auth guard: -IncludeSectionA with ONLY the AH
#   -QueryExecutor (no Graph seam / token / app-reg) -> THROWS.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c9: -IncludeSectionA without Graph auth -> throws ----" -ForegroundColor Cyan
try {
    $outC9 = New-TempOutDir 'c9'
    $threwC9 = $false
    try {
        & $scriptPath `
            -StartDate $startDate -EndDate $endDate `
            -OutputDirectory $outC9 `
            -QueryExecutor $ahMock `
            -IncludeSectionA `
            -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwC9 = $true
    }
    Add-CaseResult -Name 'c9. -IncludeSectionA without Graph auth throws (Section-A auth guard)' -Pass $threwC9 `
        -Detail ("threw={0}" -f $threwC9)
}
catch {
    Add-CaseResult -Name 'c9. -IncludeSectionA without Graph auth throws (Section-A auth guard)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE c10. No-MDA path: skip CloudAppEvents, write activity stub, and run the
#   remaining three Advanced Hunting presets.
# ===========================================================================
Write-Host ""
Write-Host "---- Case c10: -SkipActivitySessions produces a stub and runs other presets ----" -ForegroundColor Cyan
try {
    $capturedC10 = [System.Collections.Generic.List[object]]::new()
    $c10Mock = {
        param($ctx)
        $capturedC10.Add([PSCustomObject]@{ Kql = [string]$ctx.Kql })
        return @(New-MockAhRows -Kql ([string]$ctx.Kql))
    }.GetNewClosure()

    $outC10 = New-TempOutDir 'c10'
    $summaryC10 = & $scriptPath `
        -StartDate $startDate -EndDate $endDate `
        -OutputDirectory $outC10 `
        -QueryExecutor $c10Mock `
        -SkipActivitySessions `
        -WarningAction SilentlyContinue

    $activityPath = Join-Path $outC10 'ai_activity_sessions.csv'
    $activityContent = Get-Content -LiteralPath $activityPath -Raw
    $activityLines = @($activityContent -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
    $activityEntry = @($summaryC10.Presets | Where-Object { $_.Artifact -eq 'ai_activity_sessions.csv' })
    $classes = @($capturedC10 | ForEach-Object { Get-PresetClass -Kql $_.Kql })
    $noCloudAppCall = @($classes | Where-Object { $_ -eq 'activity_sessions' }).Count -eq 0
    $otherThreeRan = @('offhours_geo', 'client_channel', 'file_proximity' | ForEach-Object {
        @($classes | Where-Object { $_ -eq $PSItem }).Count -gt 0
    }) -notcontains $false
    $summaryOk = ($summaryC10.PresetCount -eq 3) -and
                 ($summaryC10.SkippedPresetCount -eq 1) -and
                 ($activityEntry.Count -eq 1) -and
                 ($activityEntry[0].Status -eq 'StubCreated')
    $passC10 = ($activityLines.Count -eq 1) -and
               ($activityLines[0] -ceq $activitySessionsHeader) -and
               $noCloudAppCall -and $otherThreeRan -and $summaryOk
    Add-CaseResult -Name 'c10. no-MDA path stubs activity sessions and runs other three presets' -Pass $passC10 `
        -Detail ("headerOk={0}; noCloudAppCall={1}; otherThreeRan={2}; summaryOk={3}" -f ($activityLines[0] -ceq $activitySessionsHeader), $noCloudAppCall, $otherThreeRan, $summaryOk)
}
catch {
    Add-CaseResult -Name 'c10. no-MDA path stubs activity sessions and runs other three presets' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== INVOKE AI-SOLUTIONS EXPORT RESULTS ====" -ForegroundColor White
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
Write-Host ("OVERALL: PASS (all {0} orchestrator cases green)" -f $caseResults.Count) -ForegroundColor Green
exit 0
