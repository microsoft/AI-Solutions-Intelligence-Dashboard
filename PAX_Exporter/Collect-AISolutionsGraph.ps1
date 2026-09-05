<#
.SYNOPSIS
    Collects the Section-A Microsoft Graph / static-catalog CSVs for the AI
    Solutions dashboard. This slice (A-1) delivers TWO of the five Section-A
    artifacts: A1 EntraUsers.csv (a live Microsoft Graph /users pull) and A5
    ai_solutions_catalog.csv (a static curated seed, create-if-missing).

.DESCRIPTION
    The AI Solutions dashboard (pbit) imports thirteen CSVs. Four are produced by
    Defender Advanced Hunting (Export-DefenderAdvancedHunting.ps1) and three are
    header-only MDA stubs (Invoke-AISolutionsExport.ps1). The remaining SIX are
    "Section A" -- sourced from Microsoft Graph / Entra / a static catalog, NOT
    from Advanced Hunting.

    This collector mirrors the existing exporter's proven pattern: raw Microsoft
    Graph REST via Invoke-RestMethod (NO Microsoft.Graph / ExchangeOnline SDK
    module dependency), the same auth model (-AccessToken OR the
    -TenantId/-ClientId/-ClientSecret app-registration trio OR an injectable
    -QueryExecutor scriptblock seam for credential-free testing), StrictMode
    Latest, $ErrorActionPreference='Stop', and it returns a summary
    PSCustomObject (it NEVER calls exit).

    NO tenant id, client id, secret, or token is ever hardcoded or logged.

    A1 -- EntraUsers.csv (live Graph pull):
        GET https://graph.microsoft.com/v1.0/users with
          $select=userPrincipalName,displayName,department,jobTitle,city,country,
                  companyName,accountEnabled,userType,createdDateTime,assignedLicenses
          $expand=manager($select=displayName,userPrincipalName)
        Pages are followed via @odata.nextLink until absent. Each raw user is
        projected to a fixed 14-column ordered record. Required delegated/app
        Graph permissions (admin-consented): User.Read.All,
        LicenseAssignment.Read.All, and AuditLog.Read.All. Directory.Read.All
        can be used instead of LicenseAssignment.Read.All but is broader.

    A5 -- ai_solutions_catalog.csv (static curated seed):
        A byte-exact header plus 23 curated rows. Written CREATE-IF-MISSING
        (never clobbered when a catalog already exists in -OutputDirectory),
        exactly like the MDA stub pattern in the orchestrator. -SkipCatalogSeed
        suppresses writing it entirely.

.PARAMETER OutputDirectory
    Directory that receives EntraUsers.csv and ai_solutions_catalog.csv.
    Created if it does not exist.

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
    INJECTION SEAM FOR TESTING. A scriptblock that receives a single argument: a
    PSCustomObject with a Uri property (the Graph request URL). It must return an
    object exposing a .value array and OPTIONALLY an @odata.nextLink string
    property. When supplied, this is used INSTEAD of calling Microsoft Graph,
    which enables credential-free testing of the pagination and projection logic.

.PARAMETER SkipCatalogSeed
    When set, ai_solutions_catalog.csv is NOT written (status 'Skipped').

.EXAMPLE
    # Live Entra users pull using a pre-acquired Graph token.
    .\Collect-AISolutionsGraph.ps1 -AccessToken $env:GRAPH_TOKEN `
        -OutputDirectory .\dashboard_data

.EXAMPLE
    # Live pull using an app registration (client credentials).
    $secret = Read-Host -AsSecureString 'Client secret'
    .\Collect-AISolutionsGraph.ps1 -TenantId $tid -ClientId $cid -ClientSecret $secret `
        -OutputDirectory .\dashboard_data

.EXAMPLE
    # Credential-free test using an injected mock executor.
    $mock = { param($ctx) [pscustomobject]@{ value = @([pscustomobject]@{ userPrincipalName='a@x' }) } }
    .\Collect-AISolutionsGraph.ps1 -QueryExecutor $mock -OutputDirectory $tempDir

.NOTES
    Requires PowerShell 7+. For real (non-mock) execution the identity used must
    have admin-consented Microsoft Graph permissions User.Read.All,
    LicenseAssignment.Read.All, and AuditLog.Read.All. Returns a summary
    PSCustomObject (does NOT call exit).
    REST + auth pattern mirrors Export-DefenderAdvancedHunting.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDirectory,

    [string]$AccessToken,

    [string]$TenantId,

    [string]$ClientId,

    [securestring]$ClientSecret,

    [scriptblock]$QueryExecutor,

    [switch]$SkipCatalogSeed,

    [datetime]$StartDate,

    [datetime]$EndDate,

    [switch]$SkipConsents,

    [switch]$SkipSignins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Constants: byte-exact headers and the static catalog seed.
# ----------------------------------------------------------------------------

# A1 EntraUsers.csv -- byte-exact 14-column header (do not rename / reorder).
$entraHeader = 'userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,hasLicense,assignedLicenses,manager_displayName,manager_userPrincipalName'

# A5 ai_solutions_catalog.csv -- byte-exact header + curated seed rows.
$catalogHeader = 'AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup'
$catalogRows = @(
    'Microsoft 365 Copilot,Productivity,Microsoft,Sanctioned,Internal Only,Microsoft Copilot'
    'GitHub Copilot,Development,Microsoft,Sanctioned,Code Context,Microsoft Copilot'
    'Bing Chat Enterprise,Search,Microsoft,Sanctioned,Internal Only,Microsoft Copilot'
    'Copilot Studio,Business Automation,Microsoft,Sanctioned,Internal Only,Microsoft Copilot'
    'Security Copilot,Security AI,Microsoft,Sanctioned,Internal Only,Microsoft Copilot'
    'ChatGPT,General AI,OpenAI,Conditional,Public Cloud,Licensed Third-Party'
    'ChatGPT Enterprise,General AI,OpenAI,Conditional,Org Managed,Licensed Third-Party'
    'ChatGPT Free,General AI,OpenAI,Unsanctioned,Public Cloud,Shadow AI'
    'ChatGPT Plus,General AI,OpenAI,Unsanctioned,Public Cloud,Shadow AI'
    'Claude,General AI,Anthropic,Unsanctioned,Public Cloud,Shadow AI'
    'Gemini,General AI,Google,Unsanctioned,Public Cloud,Shadow AI'
    'Perplexity,Search AI,Perplexity,Unsanctioned,Public Cloud,Shadow AI'
    'Midjourney,Image Generation,Midjourney,Unsanctioned,Public Cloud,Shadow AI'
    'DALL-E,Image Generation,OpenAI,Conditional,Org Managed,Licensed Third-Party'
    'Grammarly,Writing,Grammarly,Conditional,Mixed,Licensed Third-Party'
    'Notion AI,Productivity,Notion,Unsanctioned,Public Cloud,Shadow AI'
    'Adobe Firefly,Design,Adobe,Conditional,Org Managed,Licensed Third-Party'
    'Jasper,Marketing,Jasper,Unsanctioned,Public Cloud,Shadow AI'
    'Synthesia,Video,Synthesia,Unsanctioned,Public Cloud,Shadow AI'
    'Runway,Video,Runway,Unsanctioned,Public Cloud,Shadow AI'
    'Stability AI,Image Generation,Stability AI,Unsanctioned,Public Cloud,Shadow AI'
    'Hugging Face,ML Platform,Hugging Face,Unsanctioned,Public Cloud,Shadow AI'
    'Canva AI,Design,Canva,Conditional,Org Managed,Licensed Third-Party'
)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

function Write-Progress-Log {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Message -ForegroundColor $Color
}

function Get-GraphToken {
    <#
        Acquire a Microsoft Graph bearer token via the client-credentials flow.
        Never logs the secret or the resulting token.
    #>
    param(
        [string]$Tenant,
        [string]$Client,
        [securestring]$Secret
    )
    $plain = [System.Net.NetworkCredential]::new('', $Secret).Password
    try {
        $body = @{
            client_id     = $Client
            scope         = 'https://graph.microsoft.com/.default'
            client_secret = $plain
            grant_type    = 'client_credentials'
        }
        $uri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"
        $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $resp.access_token
    }
    finally {
        # Best-effort scrub of the plaintext secret from memory.
        $plain = $null
    }
}

function Invoke-GraphRest {
    <#
        Real executor: GET a Microsoft Graph URL with retry on 429 / 5xx
        (respecting Retry-After when present). Returns the raw parsed response
        object (which exposes .value and optionally @odata.nextLink).
    #>
    param(
        [string]$Uri,
        [string]$Token,
        [int]$MaxAttempts = 5
    )
    $headers = @{ Authorization = "Bearer $Token" }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
        }
        catch {
            $status = $null
            $retryAfter = $null
            try {
                if ($_.Exception.Response) {
                    $status = [int]$_.Exception.Response.StatusCode
                    $ra = $_.Exception.Response.Headers['Retry-After']
                    if ($ra) { $retryAfter = [int]$ra }
                }
            }
            catch { }

            $isRetryable = ($status -eq 429) -or ($status -ge 500 -and $status -le 599)
            if (-not $isRetryable -or $attempt -eq $MaxAttempts) {
                throw "Graph GET failed (HTTP $status, attempt $attempt/$MaxAttempts): $($_.Exception.Message)"
            }

            $delay = if ($retryAfter) { $retryAfter } else { [Math]::Min(60, [Math]::Pow(2, $attempt)) }
            Write-Progress-Log "  [RETRY] HTTP $status on attempt $attempt/$MaxAttempts - waiting $delay s" ([ConsoleColor]::Yellow)
            Start-Sleep -Seconds $delay
        }
    }
    # Unreachable in practice (loop either returns or throws), but keep the
    # StrictMode-safe explicit fall-through.
    throw "Graph GET failed after $MaxAttempts attempts: $Uri"
}

function Get-PropValue {
    <#
        StrictMode-safe optional property read. Returns $null when the property
        is absent, otherwise its value.
    #>
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function ConvertTo-CsvField {
    # Coerce a possibly-null value to a plain string ('' for null).
    param($Value)
    if ($null -eq $Value) { return '' }
    return [string]$Value
}

function Invoke-GraphPaged {
    <#
        Follow @odata.nextLink pagination for a Graph request seam, returning a
        flat List[object] of every .value item across all pages. StrictMode-safe:
        reads .value and @odata.nextLink via PSObject.Properties (never indexes
        $resp.'@odata.nextLink' directly), exactly like the A1 inline loop.
        The Invoker scriptblock receives a single [string] Uri and returns an
        object exposing .value and OPTIONALLY an @odata.nextLink string.
    #>
    param([string]$InitialUri, [scriptblock]$Invoker)

    $items = [System.Collections.Generic.List[object]]::new()
    $uri = $InitialUri
    while (-not [string]::IsNullOrEmpty($uri)) {
        $resp = & $Invoker $uri

        $valueProp = $null
        if ($null -ne $resp) { $valueProp = $resp.PSObject.Properties['value'] }
        if ($null -ne $valueProp -and $null -ne $valueProp.Value) {
            foreach ($v in @($valueProp.Value)) { $items.Add($v) }
        }

        $next = $null
        if ($null -ne $resp) {
            $p = $resp.PSObject.Properties['@odata.nextLink']
            if ($null -ne $p) { $next = [string]$p.Value }
        }
        if ([string]::IsNullOrEmpty($next)) { $uri = $null } else { $uri = $next }
    }
    return $items
}

# Shared AI-keyword list -- used by BOTH A3 (consents) and A4 (sign-ins). An app
# name is "AI" when it matches ANY keyword via -like "*keyword*" (PowerShell
# -like is case-insensitive by default). Exactly these 21 keywords, lowercase.
$aiKeywords = @(
    'openai', 'copilot', 'chatgpt', 'claude', 'anthropic', 'gemini', 'bard',
    'midjourney', 'perplexity', 'hugging', 'stability', 'github copilot',
    'bing chat', 'dall-e', 'jasper', 'grammarly', 'notion ai', 'adobe firefly',
    'canva ai', 'synthesia', 'runway'
)

function Test-IsAiApp {
    # $true when the app name matches ANY shared AI keyword (case-insensitive).
    param([string]$AppName, [string[]]$Keywords)
    if ([string]::IsNullOrEmpty($AppName)) { return $false }
    foreach ($kw in $Keywords) {
        if ($AppName -like "*$kw*") { return $true }
    }
    return $false
}

# ----------------------------------------------------------------------------
# Resolve output directory (needed for both A1 and A5).
# ----------------------------------------------------------------------------
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$entraPath   = Join-Path $OutputDirectory 'EntraUsers.csv'
$catalogPath = Join-Path $OutputDirectory 'ai_solutions_catalog.csv'
$consentsPath = Join-Path $OutputDirectory 'ai_oauth_consents.csv'
$signinsPath  = Join-Path $OutputDirectory 'ai_sso_signins.csv'

# ----------------------------------------------------------------------------
# Auth / seam resolution (mirror the exporter precedence exactly). Only resolve
# a token when a LIVE pull is actually needed (A1). The catalog seed needs none.
# ----------------------------------------------------------------------------
$useMock = $null -ne $QueryExecutor
$resolvedToken = $null

if (-not $useMock) {
    if ($AccessToken) {
        $resolvedToken = $AccessToken
    }
    elseif ($TenantId -and $ClientId -and $ClientSecret) {
        Write-Progress-Log "Acquiring Microsoft Graph token via client credentials..." ([ConsoleColor]::Cyan)
        $resolvedToken = Get-GraphToken -Tenant $TenantId -Client $ClientId -Secret $ClientSecret
    }
    else {
        throw "No credentials or test seam supplied. Provide -QueryExecutor (test), OR -AccessToken, OR -TenantId + -ClientId + -ClientSecret (app registration with Graph User.Read.All + LicenseAssignment.Read.All + AuditLog.Read.All)."
    }
}

# Single request seam: mock and real path BOTH return an object exposing .value
# (an array) and OPTIONALLY an @odata.nextLink string property.
$invokeGraph = {
    param([string]$Uri)
    if ($useMock) { return & $QueryExecutor ([pscustomobject]@{ Uri = $Uri }) }
    else          { return Invoke-GraphRest -Uri $Uri -Token $resolvedToken }
}

# ----------------------------------------------------------------------------
# A1 -- EntraUsers.csv (live Graph /users pull with @odata.nextLink pagination).
# ----------------------------------------------------------------------------
$selectClause = 'id,userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,assignedLicenses'
$expandClause = 'manager($select=displayName,userPrincipalName)'
$usersUri = 'https://graph.microsoft.com/v1.0/users?$select=' + $selectClause + '&$expand=' + $expandClause

$rawUsers = [System.Collections.Generic.List[object]]::new()
$uri = $usersUri
while (-not [string]::IsNullOrEmpty($uri)) {
    $resp = & $invokeGraph $uri

    $valueProp = $null
    if ($null -ne $resp) { $valueProp = $resp.PSObject.Properties['value'] }
    if ($null -ne $valueProp -and $null -ne $valueProp.Value) {
        foreach ($u in @($valueProp.Value)) { $rawUsers.Add($u) }
    }

    # StrictMode-safe next-link read (never index $resp.'@odata.nextLink').
    $next = $null
    if ($null -ne $resp) {
        $p = $resp.PSObject.Properties['@odata.nextLink']
        if ($null -ne $p) { $next = [string]$p.Value }
    }
    if ([string]::IsNullOrEmpty($next)) { $uri = $null } else { $uri = $next }
}

# Resolve assigned SKU ids to stable skuPartNumber values. The dashboard can
# then identify Copilot licenses without hardcoding tenant-specific GUIDs.
$assignedSkuIds = @(
    $rawUsers |
        ForEach-Object { @(Get-PropValue $_ 'assignedLicenses') } |
        ForEach-Object { Get-PropValue $_ 'skuId' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Unique
)
$skuPartNumberById = @{}
if ($assignedSkuIds.Count -gt 0) {
    $subscribedSkusUri = 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber'
    $subscribedSkus = Invoke-GraphPaged -InitialUri $subscribedSkusUri -Invoker $invokeGraph
    foreach ($subscribedSku in $subscribedSkus) {
        $skuId = [string](Get-PropValue $subscribedSku 'skuId')
        $skuPartNumber = [string](Get-PropValue $subscribedSku 'skuPartNumber')
        if (-not [string]::IsNullOrWhiteSpace($skuId) -and -not [string]::IsNullOrWhiteSpace($skuPartNumber)) {
            $skuPartNumberById[$skuId] = $skuPartNumber
        }
    }
}

# The sign-in resource does not expose userType. Keep id/UPN lookups from the
# already collected users so guest status can be projected accurately.
$userTypeById = @{}
$userTypeByUpn = @{}
foreach ($u in $rawUsers) {
    $userId = [string](Get-PropValue $u 'id')
    $userUpn = ([string](Get-PropValue $u 'userPrincipalName')).ToLowerInvariant()
    $userType = [string](Get-PropValue $u 'userType')
    if (-not [string]::IsNullOrWhiteSpace($userId)) { $userTypeById[$userId] = $userType }
    if (-not [string]::IsNullOrWhiteSpace($userUpn)) { $userTypeByUpn[$userUpn] = $userType }
}

# Project each raw user to the fixed 14-column ordered record.
$projected = [System.Collections.Generic.List[object]]::new()
foreach ($u in $rawUsers) {
    $assigned = Get-PropValue $u 'assignedLicenses'
    $skuList = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $assigned) {
        foreach ($lic in @($assigned)) {
            $sku = Get-PropValue $lic 'skuId'
            if ($null -ne $sku -and [string]$sku -ne '') {
                $skuId = [string]$sku
                $skuName = if ($skuPartNumberById.ContainsKey($skuId)) { $skuPartNumberById[$skuId] } else { $skuId }
                $skuList.Add($skuName)
            }
        }
    }
    $hasLicense = if ($skuList.Count -ge 1) { 'TRUE' } else { 'FALSE' }
    $assignedLicenses = ($skuList -join ';')

    $mgr = Get-PropValue $u 'manager'
    $mgrDisplay = ConvertTo-CsvField (Get-PropValue $mgr 'displayName')
    $mgrUpn     = ConvertTo-CsvField (Get-PropValue $mgr 'userPrincipalName')

    $projected.Add([PSCustomObject]@{
        userPrincipalName        = ConvertTo-CsvField (Get-PropValue $u 'userPrincipalName')
        displayName              = ConvertTo-CsvField (Get-PropValue $u 'displayName')
        department               = ConvertTo-CsvField (Get-PropValue $u 'department')
        jobTitle                 = ConvertTo-CsvField (Get-PropValue $u 'jobTitle')
        city                     = ConvertTo-CsvField (Get-PropValue $u 'city')
        country                  = ConvertTo-CsvField (Get-PropValue $u 'country')
        companyName              = ConvertTo-CsvField (Get-PropValue $u 'companyName')
        accountEnabled           = ConvertTo-CsvField (Get-PropValue $u 'accountEnabled')
        userType                 = ConvertTo-CsvField (Get-PropValue $u 'userType')
        createdDateTime          = ConvertTo-CsvField (Get-PropValue $u 'createdDateTime')
        hasLicense               = $hasLicense
        assignedLicenses         = $assignedLicenses
        manager_displayName      = $mgrDisplay
        manager_userPrincipalName = $mgrUpn
    })
}

# Write A1. Export-Csv writes NOTHING for an empty collection, so on zero rows
# emit the byte-exact header line explicitly (the artifact must always exist
# with a valid header so the dashboard's Power Query never errors).
if ($projected.Count -gt 0) {
    # -UseQuotes AsNeeded keeps simple values (including the header names) bare so
    # the first line is the byte-exact header; fields with commas/quotes are still
    # quoted per RFC 4180 (Power Query reads either form).
    $projected | Select-Object `
        userPrincipalName, displayName, department, jobTitle, city, country, `
        companyName, accountEnabled, userType, createdDateTime, hasLicense, `
        assignedLicenses, manager_displayName, manager_userPrincipalName |
        Export-Csv -Path $entraPath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded
}
else {
    Set-Content -Path $entraPath -Value $entraHeader -Encoding UTF8
}
$entraRowCount = $projected.Count
Write-Progress-Log ("  A1 EntraUsers.csv: {0} user row(s)" -f $entraRowCount) ([ConsoleColor]::Green)

# ----------------------------------------------------------------------------
# A5 -- ai_solutions_catalog.csv (static curated seed, create-if-missing).
# ----------------------------------------------------------------------------
if ($SkipCatalogSeed) {
    $catalogStatus = 'Skipped'
}
elseif (Test-Path $catalogPath) {
    $catalogStatus = 'SkippedExists'
}
else {
    # UTF-8 without BOM (PS7 default for WriteAllText), LF line endings, single
    # trailing LF -- same convention as the orchestrator's stub writer.
    $catalogText = ($catalogHeader + "`n" + ($catalogRows -join "`n"))
    [System.IO.File]::WriteAllText($catalogPath, $catalogText + "`n")
    $catalogStatus = 'Created'
}
Write-Progress-Log ("  A5 ai_solutions_catalog.csv: {0}" -f $catalogStatus) ([ConsoleColor]::Cyan)

# ----------------------------------------------------------------------------
# Shared audit-log time bounds. When unbound, default to the last 180 days
# through now. Formatted as UTC ISO 8601 'Z' strings for Graph filters.
# ----------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey('StartDate')) {
    $StartDate = (Get-Date).AddDays(-180)
}
if (-not $PSBoundParameters.ContainsKey('EndDate')) {
    $EndDate = Get-Date
}
if ($EndDate -le $StartDate) {
    throw 'EndDate must be later than StartDate.'
}
$startIso = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$endIso = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# ----------------------------------------------------------------------------
# A3 -- ai_oauth_consents.csv (Graph auditLogs/directoryAudits, AI-filtered).
#   Required app permission: AuditLog.Read.All.
# ----------------------------------------------------------------------------
$consentsHeader = 'UPN,AppName,YearMonth,ConsentCount,LastConsent,PermissionWeight,Permissions'
if ($SkipConsents) {
    $consentsStatus = 'Skipped'
    $consentsRowCount = 0
}
else {
    $consentsFilter = "activityDisplayName eq 'Consent to application' and activityDateTime ge $startIso and activityDateTime lt $endIso"
    $consentsUri = 'https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?$filter=' +
        [uri]::EscapeDataString($consentsFilter) +
        '&$select=activityDateTime,activityDisplayName,targetResources,initiatedBy'

    $rawConsents = Invoke-GraphPaged -InitialUri $consentsUri -Invoker $invokeGraph

    # Project each raw directory-audit record to an intermediate consent row.
    $consentInter = [System.Collections.Generic.List[object]]::new()
    foreach ($rec in $rawConsents) {
        $activityDateTime = Get-PropValue $rec 'activityDateTime'
        $targetResources  = Get-PropValue $rec 'targetResources'
        $initiatedBy      = Get-PropValue $rec 'initiatedBy'

        # First targetResource whose type -eq 'ServicePrincipal'.
        $sp = $null
        if ($null -ne $targetResources) {
            foreach ($tr in @($targetResources)) {
                if ((Get-PropValue $tr 'type') -eq 'ServicePrincipal') { $sp = $tr; break }
            }
        }
        $appName = ConvertTo-CsvField (Get-PropValue $sp 'displayName')

        $initUser = Get-PropValue $initiatedBy 'user'
        $upn = ConvertTo-CsvField (Get-PropValue $initUser 'userPrincipalName')

        $isAI = Test-IsAiApp -AppName $appName -Keywords $aiKeywords
        if (-not ($isAI -and $upn)) { continue }

        # Permissions: modifiedProperties where displayName -eq
        # 'DelegatedPermissionGrant.Scope' -> newValue, joined ', '.
        $permParts = [System.Collections.Generic.List[string]]::new()
        $modProps = Get-PropValue $sp 'modifiedProperties'
        if ($null -ne $modProps) {
            foreach ($mp in @($modProps)) {
                if ((Get-PropValue $mp 'displayName') -eq 'DelegatedPermissionGrant.Scope') {
                    $nv = Get-PropValue $mp 'newValue'
                    if ($null -ne $nv -and [string]$nv -ne '') { $permParts.Add([string]$nv) }
                }
            }
        }
        $perms = ($permParts -join ', ')

        $scopeList = @($perms -split '[,;\s]+' | Where-Object { $_ })
        $weight = $scopeList.Count
        foreach ($scope in $scopeList) {
            if ($scope -match 'Mail\.|Files\.|Sites\.') { $weight += 5 }
            if ($scope -match '\.ReadWrite') { $weight += 2 }
        }

        $ts = [string]$activityDateTime
        $parsed = [datetime]::Parse($ts, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $consentInter.Add([pscustomobject]@{
            UPN       = ([string]$upn).ToLower()
            AppName   = $appName
            Timestamp = $parsed
            YearMonth = $parsed.ToString('yyyy-MM')
            Weight    = $weight
            Perms     = if ($perms -ne '') { $perms } else { 'Unknown' }
        })
    }

    # Aggregate by UPN, AppName, YearMonth.
    $consentRows = [System.Collections.Generic.List[object]]::new()
    $consentGroups = $consentInter | Group-Object -Property UPN, AppName, YearMonth
    foreach ($g in $consentGroups) {
        $first = $g.Group[0]
        $maxTs = ($g.Group | ForEach-Object { $_.Timestamp } | Measure-Object -Maximum).Maximum
        $maxWeight = ($g.Group | ForEach-Object { $_.Weight } | Measure-Object -Maximum).Maximum
        $uniquePerms = @($g.Group | ForEach-Object { $_.Perms } | Select-Object -Unique)
        $consentRows.Add([pscustomobject]@{
            UPN              = $first.UPN
            AppName          = $first.AppName
            YearMonth        = $first.YearMonth
            ConsentCount     = $g.Count
            LastConsent      = $maxTs.ToString('yyyy-MM-dd')
            PermissionWeight = $maxWeight
            Permissions      = ($uniquePerms -join '; ')
        })
    }

    if ($consentRows.Count -gt 0) {
        $consentRows | Select-Object `
            UPN, AppName, YearMonth, ConsentCount, LastConsent, PermissionWeight, Permissions |
            Export-Csv -Path $consentsPath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded
    }
    else {
        Set-Content -Path $consentsPath -Value $consentsHeader -Encoding UTF8
    }
    $consentsRowCount = $consentRows.Count
    $consentsStatus = 'Written'
}
Write-Progress-Log ("  A3 ai_oauth_consents.csv: {0} ({1} row(s))" -f $consentsStatus, $consentsRowCount) ([ConsoleColor]::Green)

# ----------------------------------------------------------------------------
# A4 -- ai_sso_signins.csv (Graph auditLogs/signIns, AI-filtered, successes).
#   Required app permission: AuditLog.Read.All. User.Read.All is already used
#   for EntraUsers and supplies the userType lookup used for guest classification.
# ----------------------------------------------------------------------------
$signinsHeader = 'UPN,Application,YearMonth,SignInCount,DistinctDays,IsGuest,Countries,HasConditionalAccess,LastSignIn'
if ($SkipSignins) {
    $signinsStatus = 'Skipped'
    $signinsRowCount = 0
}
else {
    $signinsFilter = "createdDateTime ge $startIso and createdDateTime lt $endIso"
    $signinsUri = 'https://graph.microsoft.com/v1.0/auditLogs/signIns?$filter=' +
        [uri]::EscapeDataString($signinsFilter) +
        '&$select=userId,userPrincipalName,appDisplayName,createdDateTime,location,conditionalAccessStatus,status'

    $rawSignins = Invoke-GraphPaged -InitialUri $signinsUri -Invoker $invokeGraph

    # Project each raw sign-in record to an intermediate sign-in row.
    $signinInter = [System.Collections.Generic.List[object]]::new()
    foreach ($rec in $rawSignins) {
        $app = ConvertTo-CsvField (Get-PropValue $rec 'appDisplayName')
        $isAI = Test-IsAiApp -AppName $app -Keywords $aiKeywords

        $status = Get-PropValue $rec 'status'
        $errorCode = Get-PropValue $status 'errorCode'

        if (-not ($isAI -and ($errorCode -eq 0))) { continue }

        $upn = ([string](ConvertTo-CsvField (Get-PropValue $rec 'userPrincipalName'))).ToLower()
        $createdDateTime = [string](Get-PropValue $rec 'createdDateTime')
        $parsed = [datetime]::Parse($createdDateTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)

        $location = Get-PropValue $rec 'location'
        $country = ConvertTo-CsvField (Get-PropValue $location 'countryOrRegion')

        $userId = [string](Get-PropValue $rec 'userId')
        $userType = if (-not [string]::IsNullOrWhiteSpace($userId) -and $userTypeById.ContainsKey($userId)) {
            $userTypeById[$userId]
        }
        elseif ($userTypeByUpn.ContainsKey($upn)) {
            $userTypeByUpn[$upn]
        }
        else {
            ''
        }
        $isGuest = if ($userType -eq 'Guest' -or $upn -like '*#ext#*') { 'TRUE' } else { 'FALSE' }

        $caStatus = Get-PropValue $rec 'conditionalAccessStatus'
        $hasCA = if ($caStatus -eq 'success') { 'TRUE' } else { 'FALSE' }

        $signinInter.Add([pscustomobject]@{
            UPN       = $upn
            App       = $app
            Date      = $parsed.ToString('yyyy-MM-dd')
            YearMonth = $parsed.ToString('yyyy-MM')
            Country   = $country
            IsGuest   = $isGuest
            HasCA     = $hasCA
        })
    }

    # Keep successful-CA and non-successful-CA sign-ins in separate aggregates
    # so the dashboard can count each category without mixed-group suppression.
    $signinRows = [System.Collections.Generic.List[object]]::new()
    $signinGroups = $signinInter | Group-Object -Property UPN, App, YearMonth, HasCA
    foreach ($g in $signinGroups) {
        $first = $g.Group[0]
        $distinctDays = @($g.Group | ForEach-Object { $_.Date } | Select-Object -Unique).Count
        $uniqueCountries = @($g.Group | ForEach-Object { $_.Country } | Where-Object { $_ } | Select-Object -Unique)
        $countries = if ($uniqueCountries.Count -gt 0) { ($uniqueCountries -join '; ') } else { 'Unknown' }
        $lastSignIn = ($g.Group | ForEach-Object { $_.Date } | Measure-Object -Maximum).Maximum
        $signinRows.Add([pscustomobject]@{
            UPN                  = $first.UPN
            Application          = $first.App
            YearMonth            = $first.YearMonth
            SignInCount          = $g.Count
            DistinctDays         = $distinctDays
            IsGuest              = $first.IsGuest
            Countries            = $countries
            HasConditionalAccess = $first.HasCA
            LastSignIn           = $lastSignIn
        })
    }

    if ($signinRows.Count -gt 0) {
        $signinRows | Select-Object `
            UPN, Application, YearMonth, SignInCount, DistinctDays, IsGuest, `
            Countries, HasConditionalAccess, LastSignIn |
            Export-Csv -Path $signinsPath -NoTypeInformation -Encoding UTF8 -UseQuotes AsNeeded
    }
    else {
        Set-Content -Path $signinsPath -Value $signinsHeader -Encoding UTF8
    }
    $signinsRowCount = $signinRows.Count
    $signinsStatus = 'Written'
}
Write-Progress-Log ("  A4 ai_sso_signins.csv: {0} ({1} row(s))" -f $signinsStatus, $signinsRowCount) ([ConsoleColor]::Green)

# ----------------------------------------------------------------------------
# Summary (Write-Host does not pollute the pipeline) + return object.
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "==== AI Solutions Graph collection summary ====" -ForegroundColor White
Write-Host ("OutputDirectory : {0}" -f $OutputDirectory)
Write-Host ("EntraUsers      : {0} row(s)" -f $entraRowCount)
Write-Host ("Catalog         : {0}" -f $catalogStatus)
Write-Host ("Consents        : {0} ({1} row(s))" -f $consentsStatus, $consentsRowCount)
Write-Host ("Signins         : {0} ({1} row(s))" -f $signinsStatus, $signinsRowCount)
Write-Host ""

return [PSCustomObject]@{
    OutputDirectory = $OutputDirectory
    EntraUsers      = [pscustomobject]@{ Path = $entraPath;   RowCount = $entraRowCount }
    Catalog         = [pscustomobject]@{ Path = $catalogPath; Status   = $catalogStatus }
    Consents        = [pscustomobject]@{ Path = $consentsPath; RowCount = $consentsRowCount; Status = $consentsStatus }
    Signins         = [pscustomobject]@{ Path = $signinsPath;  RowCount = $signinsRowCount;  Status = $signinsStatus }
}
