<#
    Collect-AISolutionsGraph.Tests.ps1

    CREDENTIAL-FREE test for the Section-A Graph collector
    Collect-AISolutionsGraph.ps1 (Slice A-1: A1 EntraUsers.csv + A5
    ai_solutions_catalog.csv).

    Exercises the collector through the injectable -QueryExecutor mock seam, so
    NO tenant, token, app-registration, or network access is required. Follows
    the SAME plain-PowerShell assertion style as Invoke-AISolutionsExport.Tests.ps1
    (run, assert, print PASS/FAIL per case, exit non-zero if ANY case fails,
    fixed Get-Random -SetSeed).

    The mock scriptblock is captured via .GetNewClosure() over a LOCAL
    List[object] (a reference-type List, so the closure and the test share the
    SAME object). The collector invokes the mock via `& $QueryExecutor`, so a
    $script: lookup would resolve against the COLLECTOR's scope; a closure over a
    local List keeps the capture bound to THIS test.

    Cases:
      a1. EntraUsers header fidelity -- single-page mock (2 users); assert the
          CSV first line EQUALS the exact 14-column header string.
      a2. Pagination -- page 1 (u1,u2 + @odata.nextLink) then page 2 (u3);
          assert produced data-row count = 3.
      a3. License projection -- assignedLicenses=@(s1,s2) -> hasLicense=TRUE,
          assignedLicenses='s1;s2'; assignedLicenses=@() -> FALSE and ''.
      a4. Manager expansion -- manager present -> manager_displayName/UPN filled;
          no manager -> both empty.
      a5. Catalog seed create-if-missing -- first run creates the file with the
          exact header + 20 data rows; a pre-seeded different-content catalog in
          a fresh dir is NOT overwritten.
      a6. Auth guard -- no -QueryExecutor and no auth THROWS (live pull path).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Determinism: fixed seed.
$null = Get-Random -SetSeed 20260724

$scriptPath = Join-Path $PSScriptRoot '..\Collect-AISolutionsGraph.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

# Exact expected byte-for-byte headers (from the ASSUMPTIONS).
$expectedEntraHeader   = 'userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,hasLicense,assignedLicenses,manager_displayName,manager_userPrincipalName'
$expectedCatalogHeader = 'AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup'

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
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("ah_graph_{0}_{1}" -f $Tag, ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# ===========================================================================
# CASE a1. EntraUsers header fidelity (single-page mock, 2 users).
# ===========================================================================
Write-Host ""
Write-Host "---- Case a1: EntraUsers header fidelity ----" -ForegroundColor Cyan
try {
    $a1Mock = {
        param($ctx)
        [pscustomobject]@{
            value = @(
                [pscustomobject]@{ userPrincipalName = 'u1@x'; displayName = 'User One' },
                [pscustomobject]@{ userPrincipalName = 'u2@x'; displayName = 'User Two' }
            )
        }
    }.GetNewClosure()

    $outA1 = New-TempOutDir 'a1'
    & $scriptPath -OutputDirectory $outA1 -QueryExecutor $a1Mock -SkipCatalogSeed -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $entraPath = Join-Path $outA1 'EntraUsers.csv'
    $firstLine = (Get-Content -LiteralPath $entraPath)[0]
    $passA1 = ($firstLine -ceq $expectedEntraHeader)
    Add-CaseResult -Name 'a1. EntraUsers.csv first line equals exact 14-column header' -Pass $passA1 `
        -Detail ("headerMatch={0}" -f $passA1)
}
catch {
    Add-CaseResult -Name 'a1. EntraUsers.csv first line equals exact 14-column header' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE a2. Pagination (page1 nextLink -> page2), assert 3 data rows.
# ===========================================================================
Write-Host ""
Write-Host "---- Case a2: pagination follows @odata.nextLink ----" -ForegroundColor Cyan
try {
    $a2Calls = [System.Collections.Generic.List[object]]::new()
    $a2Mock = {
        param($ctx)
        $a2Calls.Add([string]$ctx.Uri)
        if ([string]$ctx.Uri -like '*page2*') {
            return [pscustomobject]@{
                value = @([pscustomobject]@{ userPrincipalName = 'u3@x'; displayName = 'User Three' })
            }
        }
        else {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ userPrincipalName = 'u1@x'; displayName = 'User One' },
                    [pscustomobject]@{ userPrincipalName = 'u2@x'; displayName = 'User Two' }
                )
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page2'
            }
        }
    }.GetNewClosure()

    $outA2 = New-TempOutDir 'a2'
    & $scriptPath -OutputDirectory $outA2 -QueryExecutor $a2Mock -SkipCatalogSeed -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $entraPath = Join-Path $outA2 'EntraUsers.csv'
    $rows = @(Import-Csv -LiteralPath $entraPath)
    $passA2 = ($rows.Count -eq 3) -and ($a2Calls.Count -eq 2)
    Add-CaseResult -Name 'a2. pagination yields 3 data rows over 2 pages' -Pass $passA2 `
        -Detail ("rows={0}; calls={1}" -f $rows.Count, $a2Calls.Count)
}
catch {
    Add-CaseResult -Name 'a2. pagination yields 3 data rows over 2 pages' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE a3. License projection.
# ===========================================================================
Write-Host ""
Write-Host "---- Case a3: license projection (hasLicense / assignedLicenses) ----" -ForegroundColor Cyan
try {
    $a3Mock = {
        param($ctx)
        if ([string]$ctx.Uri -like '*subscribedSkus*') {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ skuId = 's1'; skuPartNumber = 'Microsoft_365_Copilot' },
                    [pscustomobject]@{ skuId = 's2'; skuPartNumber = 'SPE_E5' }
                )
            }
        }
        [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    userPrincipalName = 'lic@x'; displayName = 'Licensed'
                    assignedLicenses  = @([pscustomobject]@{ skuId = 's1' }, [pscustomobject]@{ skuId = 's2' })
                },
                [pscustomobject]@{
                    userPrincipalName = 'nolic@x'; displayName = 'Unlicensed'
                    assignedLicenses  = @()
                }
            )
        }
    }.GetNewClosure()

    $outA3 = New-TempOutDir 'a3'
    & $scriptPath -OutputDirectory $outA3 -QueryExecutor $a3Mock -SkipCatalogSeed -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outA3 'EntraUsers.csv'))
    $licRow = $rows | Where-Object { $_.userPrincipalName -eq 'lic@x' }
    $noRow  = $rows | Where-Object { $_.userPrincipalName -eq 'nolic@x' }

    $licOk = ($licRow.hasLicense -eq 'TRUE') -and ($licRow.assignedLicenses -eq 'Microsoft_365_Copilot;SPE_E5')
    $noOk  = ($noRow.hasLicense -eq 'FALSE') -and ($noRow.assignedLicenses -eq '')
    $passA3 = $licOk -and $noOk
    Add-CaseResult -Name 'a3. license projection resolves SKU part numbers' -Pass $passA3 `
        -Detail ("lic(hasLic={0},skus='{1}'); nolic(hasLic={2},skus='{3}')" -f $licRow.hasLicense, $licRow.assignedLicenses, $noRow.hasLicense, $noRow.assignedLicenses)
}
catch {
    Add-CaseResult -Name 'a3. license projection (TRUE/s1;s2 and FALSE/empty)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE a4. Manager expansion.
# ===========================================================================
Write-Host ""
Write-Host "---- Case a4: manager expansion (manager_displayName / _userPrincipalName) ----" -ForegroundColor Cyan
try {
    $a4Mock = {
        param($ctx)
        [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    userPrincipalName = 'hasmgr@x'; displayName = 'Has Manager'
                    manager = [pscustomobject]@{ displayName = 'Mgr N'; userPrincipalName = 'mgr@x' }
                },
                [pscustomobject]@{
                    userPrincipalName = 'nomgr@x'; displayName = 'No Manager'
                }
            )
        }
    }.GetNewClosure()

    $outA4 = New-TempOutDir 'a4'
    & $scriptPath -OutputDirectory $outA4 -QueryExecutor $a4Mock -SkipCatalogSeed -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outA4 'EntraUsers.csv'))
    $hasRow = $rows | Where-Object { $_.userPrincipalName -eq 'hasmgr@x' }
    $noRow  = $rows | Where-Object { $_.userPrincipalName -eq 'nomgr@x' }

    $hasOk = ($hasRow.manager_displayName -eq 'Mgr N') -and ($hasRow.manager_userPrincipalName -eq 'mgr@x')
    $noOk  = ($noRow.manager_displayName -eq '') -and ($noRow.manager_userPrincipalName -eq '')
    $passA4 = $hasOk -and $noOk
    Add-CaseResult -Name 'a4. manager expansion (present filled, absent empty)' -Pass $passA4 `
        -Detail ("has(disp='{0}',upn='{1}'); no(disp='{2}',upn='{3}')" -f $hasRow.manager_displayName, $hasRow.manager_userPrincipalName, $noRow.manager_displayName, $noRow.manager_userPrincipalName)
}
catch {
    Add-CaseResult -Name 'a4. manager expansion (present filled, absent empty)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE a5. Catalog seed create-if-missing (non-clobber).
# ===========================================================================
Write-Host ""
Write-Host "---- Case a5: catalog seed create-if-missing (non-clobber) ----" -ForegroundColor Cyan
try {
    $a5Mock = {
        param($ctx)
        [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    # First run: catalog created with exact header + 23 data rows.
    $outA5 = New-TempOutDir 'a5'
    & $scriptPath -OutputDirectory $outA5 -QueryExecutor $a5Mock -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $catalogPath = Join-Path $outA5 'ai_solutions_catalog.csv'
    $lines = @(Get-Content -LiteralPath $catalogPath | Where-Object { $_.Trim().Length -gt 0 })
    $headerOk = ($lines.Count -gt 0) -and ($lines[0] -ceq $expectedCatalogHeader)
    $dataRows = $lines.Count - 1
    $countOk = ($lines.Count -eq 24) -and ($dataRows -eq 23)

    # Second run in a fresh dir with a pre-seeded DIFFERENT-content catalog.
    $outA5b = New-TempOutDir 'a5b'
    $seededCatalog = Join-Path $outA5b 'ai_solutions_catalog.csv'
    $seededContent = "AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup`nMyCustomSolution,Custom,Me,Sanctioned,Internal Only,Custom Group`n"
    [System.IO.File]::WriteAllText($seededCatalog, $seededContent)
    & $scriptPath -OutputDirectory $outA5b -QueryExecutor $a5Mock -SkipConsents -SkipSignins -WarningAction SilentlyContinue | Out-Null
    $afterContent = Get-Content -LiteralPath $seededCatalog -Raw
    $nonClobber = $afterContent.Contains('MyCustomSolution')

    $passA5 = $headerOk -and $countOk -and $nonClobber
    Add-CaseResult -Name 'a5. catalog seed create-if-missing (23 rows, header exact, non-clobber)' -Pass $passA5 `
        -Detail ("headerOk={0}; lines={1}; dataRows={2}; nonClobber={3}" -f $headerOk, $lines.Count, $dataRows, $nonClobber)
}
catch {
    Add-CaseResult -Name 'a5. catalog seed create-if-missing (23 rows, header exact, non-clobber)' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE a6. Auth guard (no executor, no auth -> throws).
# ===========================================================================
Write-Host ""
Write-Host "---- Case a6: auth guard (no executor, no auth -> throws) ----" -ForegroundColor Cyan
try {
    $outA6 = New-TempOutDir 'a6'
    $threwA6 = $false
    try {
        & $scriptPath -OutputDirectory $outA6 -WarningAction SilentlyContinue | Out-Null
    }
    catch {
        $threwA6 = $true
    }
    Add-CaseResult -Name 'a6. auth guard throws with no credentials' -Pass $threwA6 `
        -Detail ("threw={0}" -f $threwA6)
}
catch {
    Add-CaseResult -Name 'a6. auth guard throws with no credentials' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE b1. A3 header + AI-filter + aggregation.
#   consents mock returns 3 records: two AI 'OpenAI ChatGPT' consents (same
#   UPN/month) and one non-AI 'Acme HR' (must be EXCLUDED). URI-dispatching:
#   'auditLogs/directoryAudits' -> consents; else empty.
# ===========================================================================
Write-Host ""
Write-Host "---- Case b1: A3 header + AI filter + aggregation ----" -ForegroundColor Cyan
try {
    $b1Consents = [System.Collections.Generic.List[object]]::new()
    $b1Consents.Add([pscustomobject]@{
        activityDateTime     = '2026-03-05T10:00:00Z'
        activityDisplayName  = 'Consent to application'
        targetResources      = @([pscustomobject]@{ type = 'ServicePrincipal'; displayName = 'OpenAI ChatGPT'; modifiedProperties = @() })
        initiatedBy          = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B1User@X' } }
    })
    $b1Consents.Add([pscustomobject]@{
        activityDateTime     = '2026-03-20T12:00:00Z'
        activityDisplayName  = 'Consent to application'
        targetResources      = @([pscustomobject]@{ type = 'ServicePrincipal'; displayName = 'OpenAI ChatGPT'; modifiedProperties = @() })
        initiatedBy          = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B1User@X' } }
    })
    $b1Consents.Add([pscustomobject]@{
        activityDateTime     = '2026-03-22T12:00:00Z'
        activityDisplayName  = 'Consent to application'
        targetResources      = @([pscustomobject]@{ type = 'ServicePrincipal'; displayName = 'Acme HR'; modifiedProperties = @() })
        initiatedBy          = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B1User@X' } }
    })
    $b1Mock = {
        param($ctx)
        $u = [string]$ctx.Uri
        if ($u -like '*auditLogs/directoryAudits*') { return [pscustomobject]@{ value = $b1Consents.ToArray() } }
        return [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    $outB1 = New-TempOutDir 'b1'
    & $scriptPath -OutputDirectory $outB1 -QueryExecutor $b1Mock -SkipCatalogSeed -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $consentsPath = Join-Path $outB1 'ai_oauth_consents.csv'
    $expectedConsentsHeader = 'UPN,AppName,YearMonth,ConsentCount,LastConsent,PermissionWeight,Permissions'
    $firstLine = (Get-Content -LiteralPath $consentsPath)[0]
    $rows = @(Import-Csv -LiteralPath $consentsPath)
    $aiRow = $rows | Where-Object { $_.AppName -eq 'OpenAI ChatGPT' }
    $nonAiRow = $rows | Where-Object { $_.AppName -eq 'Acme HR' }
    $passB1 = ($firstLine -ceq $expectedConsentsHeader) -and ($rows.Count -eq 1) -and `
              ($null -ne $aiRow) -and ([int]$aiRow.ConsentCount -eq 2) -and ($null -eq $nonAiRow)
    Add-CaseResult -Name 'b1. A3 header exact, AI-only, aggregated ConsentCount=2' -Pass $passB1 `
        -Detail ("headerOk={0}; rows={1}; consentCount={2}; nonAiPresent={3}" -f ($firstLine -ceq $expectedConsentsHeader), $rows.Count, $(if ($aiRow) { $aiRow.ConsentCount } else { 'n/a' }), ($null -ne $nonAiRow))
}
catch {
    Add-CaseResult -Name 'b1. A3 header exact, AI-only, aggregated ConsentCount=2' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE b2. A3 permission weight.
#   One AI-app record with newValue 'Mail.Read User.Read Files.ReadWrite'
#   -> weight = 3 + 5(Mail.) + 5(Files.) + 2(.ReadWrite) = 15.
# ===========================================================================
Write-Host ""
Write-Host "---- Case b2: A3 permission weight = 15 ----" -ForegroundColor Cyan
try {
    $b2Consents = [System.Collections.Generic.List[object]]::new()
    $b2Consents.Add([pscustomobject]@{
        activityDateTime     = '2026-04-10T09:00:00Z'
        activityDisplayName  = 'Consent to application'
        targetResources      = @([pscustomobject]@{
            type = 'ServicePrincipal'; displayName = 'OpenAI ChatGPT'
            modifiedProperties = @([pscustomobject]@{ displayName = 'DelegatedPermissionGrant.Scope'; newValue = 'Mail.Read User.Read Files.ReadWrite' })
        })
        initiatedBy          = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B2User@X' } }
    })
    $b2Mock = {
        param($ctx)
        $u = [string]$ctx.Uri
        if ($u -like '*auditLogs/directoryAudits*') { return [pscustomobject]@{ value = $b2Consents.ToArray() } }
        return [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    $outB2 = New-TempOutDir 'b2'
    & $scriptPath -OutputDirectory $outB2 -QueryExecutor $b2Mock -SkipCatalogSeed -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outB2 'ai_oauth_consents.csv'))
    $row = $rows | Where-Object { $_.AppName -eq 'OpenAI ChatGPT' }
    $passB2 = ($null -ne $row) -and ([int]$row.PermissionWeight -eq 15)
    Add-CaseResult -Name 'b2. A3 permission weight = 15' -Pass $passB2 `
        -Detail ("weight={0}" -f $(if ($row) { $row.PermissionWeight } else { 'n/a' }))
}
catch {
    Add-CaseResult -Name 'b2. A3 permission weight = 15' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE b3. A4 header + filter + aggregation.
#   signIns mock: 2 AI success (same UPN/app/month, 2 distinct days, one
#   conditionalAccessStatus='success') + 1 AI FAILED (errorCode=50126 excluded)
#   + 1 non-AI success (excluded).
# ===========================================================================
Write-Host ""
Write-Host "---- Case b3: A4 header + filter + aggregation ----" -ForegroundColor Cyan
try {
    $b3Signins = [System.Collections.Generic.List[object]]::new()
    $b3Signins.Add([pscustomobject]@{
        userId = 'guest-id'; userPrincipalName = 'B3User@X'; appDisplayName = 'OpenAI ChatGPT'
        createdDateTime = '2026-05-01T08:00:00Z'; location = [pscustomobject]@{ countryOrRegion = 'US' }
        conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = 0 }
    })
    $b3Signins.Add([pscustomobject]@{
        userId = 'guest-id'; userPrincipalName = 'B3User@X'; appDisplayName = 'OpenAI ChatGPT'
        createdDateTime = '2026-05-02T09:00:00Z'; location = [pscustomobject]@{ countryOrRegion = 'US' }
        conditionalAccessStatus = 'notApplied'; status = [pscustomobject]@{ errorCode = 0 }
    })
    $b3Signins.Add([pscustomobject]@{
        userId = 'guest-id'; userPrincipalName = 'B3User@X'; appDisplayName = 'OpenAI ChatGPT'
        createdDateTime = '2026-05-03T09:00:00Z'; location = [pscustomobject]@{ countryOrRegion = 'US' }
        conditionalAccessStatus = 'failure'; status = [pscustomobject]@{ errorCode = 50126 }
    })
    $b3Signins.Add([pscustomobject]@{
        userId = 'guest-id'; userPrincipalName = 'B3User@X'; appDisplayName = 'Acme HR'
        createdDateTime = '2026-05-04T09:00:00Z'; location = [pscustomobject]@{ countryOrRegion = 'US' }
        conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = 0 }
    })
    $b3Uris = [System.Collections.Generic.List[string]]::new()
    $b3Mock = {
        param($ctx)
        $u = [string]$ctx.Uri
        $b3Uris.Add($u)
        if ($u -like '*auditLogs/signIns*') { return [pscustomobject]@{ value = $b3Signins.ToArray() } }
        if ($u -like '*/users?*') {
            return [pscustomobject]@{ value = @([pscustomobject]@{ id='guest-id'; userPrincipalName='B3User@X'; userType='Guest' }) }
        }
        return [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    $outB3 = New-TempOutDir 'b3'
    & $scriptPath -OutputDirectory $outB3 -QueryExecutor $b3Mock -SkipCatalogSeed -SkipConsents `
        -StartDate ([datetime]'2026-05-01T00:00:00Z') -EndDate ([datetime]'2026-06-01T00:00:00Z') `
        -WarningAction SilentlyContinue | Out-Null

    $signinsPath = Join-Path $outB3 'ai_sso_signins.csv'
    $expectedSigninsHeader = 'UPN,Application,YearMonth,SignInCount,DistinctDays,IsGuest,Countries,HasConditionalAccess,LastSignIn'
    $firstLine = (Get-Content -LiteralPath $signinsPath)[0]
    $rows = @(Import-Csv -LiteralPath $signinsPath)
    $row = $rows | Where-Object { $_.Application -eq 'OpenAI ChatGPT' }
    $boundedUri = @($b3Uris | Where-Object { $_ -like '*auditLogs/signIns*' -and $_ -match 'createdDateTime%20lt%202026-06-01' }).Count -eq 1
    $passB3 = ($firstLine -ceq $expectedSigninsHeader) -and ($rows.Count -eq 1) -and ($null -ne $row) -and `
              ([int]$row.SignInCount -eq 2) -and ([int]$row.DistinctDays -eq 2) -and `
              ($row.HasConditionalAccess -eq 'TRUE') -and ($row.IsGuest -eq 'TRUE') -and $boundedUri
    Add-CaseResult -Name 'b3. A4 bounded filter, guest lookup, AI+success aggregation' -Pass $passB3 `
        -Detail ("headerOk={0}; rows={1}; signInCount={2}; distinctDays={3}; hasCA={4}; isGuest={5}; bounded={6}" -f ($firstLine -ceq $expectedSigninsHeader), $rows.Count, $(if ($row) { $row.SignInCount } else { 'n/a' }), $(if ($row) { $row.DistinctDays } else { 'n/a' }), $(if ($row) { $row.HasConditionalAccess } else { 'n/a' }), $(if ($row) { $row.IsGuest } else { 'n/a' }), $boundedUri)
}
catch {
    Add-CaseResult -Name 'b3. A4 header exact, AI+success only, SignInCount=2/DistinctDays=2/HasCA=TRUE' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE b4. A3 pagination follows @odata.nextLink (2 pages, 1 AI rec each).
# ===========================================================================
Write-Host ""
Write-Host "---- Case b4: A3 pagination (2 pages) ----" -ForegroundColor Cyan
try {
    $b4Mock = {
        param($ctx)
        $u = [string]$ctx.Uri
        if ($u -like '*auditLogs/directoryAudits*') {
            if ($u -like '*page2*') {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{
                        activityDateTime = '2026-07-15T10:00:00Z'; activityDisplayName = 'Consent to application'
                        targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; displayName = 'Claude'; modifiedProperties = @() })
                        initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B4b@X' } }
                    })
                }
            }
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    activityDateTime = '2026-06-15T10:00:00Z'; activityDisplayName = 'Consent to application'
                    targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; displayName = 'OpenAI ChatGPT'; modifiedProperties = @() })
                    initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'B4a@X' } }
                })
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?page2'
            }
        }
        return [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    $outB4 = New-TempOutDir 'b4'
    & $scriptPath -OutputDirectory $outB4 -QueryExecutor $b4Mock -SkipCatalogSeed -SkipSignins -WarningAction SilentlyContinue | Out-Null

    $rows = @(Import-Csv -LiteralPath (Join-Path $outB4 'ai_oauth_consents.csv'))
    $passB4 = ($rows.Count -eq 2)
    Add-CaseResult -Name 'b4. A3 pagination yields 2 data rows over 2 pages' -Pass $passB4 `
        -Detail ("rows={0}" -f $rows.Count)
}
catch {
    Add-CaseResult -Name 'b4. A3 pagination yields 2 data rows over 2 pages' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# CASE b5. Skip switches -> files NOT created; summary statuses = 'Skipped'.
# ===========================================================================
Write-Host ""
Write-Host "---- Case b5: skip switches (no files, Skipped status) ----" -ForegroundColor Cyan
try {
    $b5Mock = {
        param($ctx)
        [pscustomobject]@{ value = @() }
    }.GetNewClosure()

    $outB5 = New-TempOutDir 'b5'
    $summary = & $scriptPath -OutputDirectory $outB5 -QueryExecutor $b5Mock -SkipCatalogSeed -SkipConsents -SkipSignins -WarningAction SilentlyContinue

    $consentsExists = Test-Path (Join-Path $outB5 'ai_oauth_consents.csv')
    $signinsExists  = Test-Path (Join-Path $outB5 'ai_sso_signins.csv')
    $passB5 = (-not $consentsExists) -and (-not $signinsExists) -and `
              ($summary.Consents.Status -eq 'Skipped') -and ($summary.Signins.Status -eq 'Skipped')
    Add-CaseResult -Name 'b5. skip switches -> no files, statuses Skipped' -Pass $passB5 `
        -Detail ("consentsFile={0}; signinsFile={1}; consentsStatus={2}; signinsStatus={3}" -f $consentsExists, $signinsExists, $summary.Consents.Status, $summary.Signins.Status)
}
catch {
    Add-CaseResult -Name 'b5. skip switches -> no files, statuses Skipped' -Pass $false -Detail "threw: $($_.Exception.Message)"
}

# ===========================================================================
# Summary + exit code.
# ===========================================================================
Write-Host ""
Write-Host "==== COLLECT AI-SOLUTIONS GRAPH RESULTS ====" -ForegroundColor White
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
