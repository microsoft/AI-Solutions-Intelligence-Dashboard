# AI Solutions Intelligence Dashboard v26.1 / V27 In Testing - Setup Instructions

**One report. Two paths.** Choose the path that matches your tenant.

| Path | Who it's for | CSVs you populate | CSVs you stub |
|---|---|---|---|
| **Path A — No MDA** | M365 E5 + MDE Plan 2, MDA not deployed | Up to 9 baseline CSVs | 3 MDA stubs plus an `ai_activity_sessions.csv` stub |
| **Path B — Full MDA** | M365 E5 + MDE Plan 2 + MDA + App Governance | All 13 CSVs | 0 |

The PBIT is identical for both paths — the difference is just what's in the data folder.

---

## Quick Reference — What tool does each CSV need?

| Step | CSV file | Tool | Requires |
|---|---|---|---|
| 1.1 | `EntraUsers.csv` | 💻 PowerShell (Microsoft Graph) | Graph API |
| 1.2 | `ai_copilot_usage_graph.csv` | 💻 PowerShell (Purview Audit) | Purview Audit reader |
| 1.2b | `ai_copilot_surface_usage.csv` | 💻 PowerShell (Purview Audit) | Purview Audit reader |
| **1.3** | **`ai_activity_sessions.csv`** | **🔍 Defender Advanced Hunting** | **Defender for Cloud Apps (`CloudAppEvents`)** |
| 1.4 | `ai_oauth_consents.csv` | 💻 PowerShell (Microsoft Graph) | AuditLog.Read.All |
| 1.5 | `ai_sso_signins.csv` | 💻 PowerShell (Microsoft Graph) | AuditLog.Read.All |
| **1.6** | **`ai_file_proximity.csv`** | **🔍 Defender Advanced Hunting** | **MDE Plan 2** |
| **1.7** | **`ai_offhours_geo.csv`** | **🔍 Defender Advanced Hunting** | **Entra ID P2 + `EntraIdSignInEvents`** |
| 1.8 | `ai_solutions_catalog.csv` | 📋 Excel / text editor | — |
| **1.9** | **`ai_client_channel.csv`** | **🔍 Defender Advanced Hunting** | **MDE Plan 2** |
| **3.1** | **`ai_appgov_alerts.csv`** | **🔍 Defender Advanced Hunting** | **MDA App Governance** |
| 3.2 | `ai_cloud_discovery.csv` | 🛡️ MDA Portal + PowerShell | MDA Cloud Discovery |
| **3.3** | **`ai_mda_sessions.csv`** | **🔍 Defender Advanced Hunting** | **MDA CAAC** |

> **🔍 How to run an Advanced Hunting query:**
> 1. Go to **https://security.microsoft.com** → **Hunting** → **Advanced Hunting**
> 2. Click **+ New query**
> 3. Paste the query from the step below
> 4. Click **Run query**
> 5. Click **Export** → **Export to CSV**
> 6. Rename the downloaded file to match the expected filename

---

## Step 0 — Prerequisites

- Power BI Desktop (latest supported Windows release)
- One Windows folder for all CSVs, e.g. `C:\AI_Usage_Data\`
- The current testing PBIT: [AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit](AI-Solutions-Intelligence-Dashboard%20V27%20In%20Testing.pbit)
- The stable PBIT: [AI-Solutions-Intelligence-Dashboard V26 Validated.pbit](AI-Solutions-Intelligence-Dashboard%20V26%20Validated.pbit)
- The KQL pack: [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql)

Permissions you will need over the course of setup:
- Microsoft Graph application permissions for the automated exporter: `User.Read.All`, `LicenseAssignment.Read.All`, `AuditLog.Read.All`, `ThreatHunting.Read.All`
- Tenant-wide Graph application-permission consent: Privileged Role Administrator or Global Administrator
- Microsoft Defender XDR portal: Security Reader, Global Reader, or assigned Defender XDR Unified RBAC hunting access
- Exchange Online audit cmdlet: View-Only Audit Logs or Audit Logs for `Search-UnifiedAuditLog`
- Microsoft Purview portal: Audit Reader or Audit Manager for audit search/export; eDiscovery roles alone are not sufficient
- Defender for Cloud Apps (Path B only): Security Reader or Global Reader for read-only portal access

### Access matrix

| Collector operation | Minimal permission | Interactive/consent role | Product or data dependency |
|---|---|---|---|
| Graph `/users` | `User.Read.All` | Privileged Role Administrator or Global Administrator grants application-permission consent | Microsoft Entra directory |
| Graph `/subscribedSkus` | `LicenseAssignment.Read.All` | Same application-permission consent owner; delegated calls require Directory Readers or Global Reader | Tenant subscription data |
| Graph `/auditLogs/directoryAudits` | `AuditLog.Read.All` | Same consent owner; delegated calls require Reports Reader, Security Reader, or Security Administrator | Entra audit retention |
| Graph `/auditLogs/signIns` | `AuditLog.Read.All` | Same consent owner; delegated calls require Global Reader, Reports Reader, Security Reader, Security Operator, or Security Administrator | Entra sign-in retention |
| Graph `/security/runHuntingQuery` | `ThreatHunting.Read.All` | Same consent owner; interactive portal access requires Security Reader, Global Reader, or assigned Defender XDR Unified RBAC hunting access | Defender XDR and each queried table's licensed/onboarded product |
| `Search-UnifiedAuditLog -Operations CopilotInteraction` | No Graph permission | View-Only Audit Logs or Audit Logs in Exchange Online; Purview Audit Reader or Audit Manager for portal search/export | Purview Audit, retained events, and Copilot activity |
| Power BI Desktop | No tenant role | Local file access | Supported Windows device |
| Publish a PBIX to an existing workspace | No Graph permission | Power BI workspace Contributor, Member, or Admin | Power BI Pro/PPU unless the workspace uses qualifying capacity |
| Publish or update a Power BI app | No Graph permission | Power BI workspace Member or Admin | Applicable Power BI license/capacity |
| Refresh a local/UNC Folder source in the service | No Graph permission | An on-premises gateway administrator or authorized connection creator configures the connection; the semantic model owner maps credentials | Running gateway and reachable source |

Do not request `Directory.Read.All`, `Reports.Read.All`,
`ServiceHealth.Read.All`, or `ActivityFeed.Read` for this exporter. The current
code does not call their endpoint families. Product activation, connector
configuration, log uploaders, tenant settings, and Conditional Access policies
are separate administrative operations and can require additional write roles.

> **Retention:** Native Defender Advanced Hunting commonly exposes about 30 days of data. Microsoft Entra sign-in and Purview Audit retention varies by license and audit policy. A query that asks for 90 or 180 days only returns what the source still retains.

---

## Step 1 — Collect baseline CSVs (both paths)

These 10 CSVs power the core dashboard pages (Executive Summary, Copilot Deep Dive, Behavioral Risk, Shadow AI, Dept Intensity by Solution, Department Breakdown, Benchmarks & Targets, and more).

### 1.1  EntraUsers.csv  (Microsoft Graph)

```powershell
$skuById = @{}
Connect-MgGraph -Scopes "User.Read.All","LicenseAssignment.Read.All"
Get-MgSubscribedSku -All | ForEach-Object {
  $skuById[$_.SkuId.ToString()] = $_.SkuPartNumber
}
Get-MgUser -All `
  -Property "userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,assignedLicenses,manager" `
  -ExpandProperty manager |
  Select-Object userPrincipalName,displayName,department,jobTitle,city,country,companyName,
                accountEnabled,userType,createdDateTime,
    @{n='hasLicense';e={ if ($_.AssignedLicenses.Count -gt 0) {'TRUE'} else {'FALSE'} }},
    @{n='assignedLicenses';e={
      ($_.AssignedLicenses | ForEach-Object {
        $id = $_.SkuId.ToString()
        if ($skuById.ContainsKey($id)) { $skuById[$id] } else { $id }
      }) -join ';'
    }},
    @{n='manager_displayName';      e={ $_.Manager.AdditionalProperties.displayName }},
    @{n='manager_userPrincipalName';e={ $_.Manager.AdditionalProperties.userPrincipalName }} |
  Export-Csv -NoTypeInformation EntraUsers.csv
```

> `assignedLicenses` must contain Graph `skuPartNumber` values, not tenant license GUIDs. The mapping above and `Collect-AISolutionsGraph.ps1` do this automatically.

### 1.2  Copilot usage CSVs  (Purview Audit)

Run `PAX_Exporter\Collect-AICopilotUsage.ps1`. It searches Purview Audit for `CopilotInteraction` events and writes both `ai_copilot_usage_graph.csv` (the compatibility-wide schema) and `ai_copilot_surface_usage.csv` (one row per user, month, and observed surface). The normalized file prefers `AppHost`, falls back to `Workload`, retains the raw source values, and automatically includes new surfaces.

The collector can return more than 50,000 records overall. It safely splits any date window that reaches the 50,000-record audit-session ceiling and de-duplicates the half-open child windows. If a one-minute window itself reaches the ceiling, collection fails explicitly rather than publishing a silently truncated export.

> The Graph Reports user-detail endpoint returns last-activity fields, not the required per-surface count schema, and cannot replace these Purview exports.
>
> Why Purview over Defender CloudAppEvents? Purview exposes `CopilotInteraction` events across observed app hosts and workloads, while `CloudAppEvents` does not supply the required per-surface schema. These audit-derived metrics are directional: Microsoft notes that they can differ from the official Microsoft 365 Copilot usage report and Viva Insights Copilot Dashboard.

### 1.3  🔍 ai_activity_sessions.csv  (Defender Advanced Hunting — CloudAppEvents)

**Output file:** `ai_activity_sessions.csv`  
**Schema:** `UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts, DistinctDevices, Category, RiskTier`

> `CloudAppEvents` requires Defender for Cloud Apps data and the Microsoft 365 activities connector to be available in Advanced Hunting. MDE Plan 2 alone does not provide this table. Without it, create this exact header as a stub; activity-dependent visuals will remain empty.

<details>
<summary><strong>📋 Click to expand KQL query (v26.1 — validated June 2026)</strong></summary>

```kql
let AIAppNames = dynamic([
    "Microsoft 365 Copilot", "GitHub Copilot", "Copilot", "Bing Chat",
    "ChatGPT", "OpenAI", "Claude", "Anthropic",
    "Gemini", "Bard", "Perplexity", "Midjourney",
    "Grammarly", "Notion", "Jasper", "Adobe Firefly",
    "Canva", "Synthesia", "Runway", "Stability", "Hugging Face"
]);
let UserUpns = IdentityInfo
    | summarize take_any(AccountUpn) by AccountObjectId;
CloudAppEvents
| where Timestamp > ago(30d)
| where Application has_any (AIAppNames)
| extend AISolution = case(
    Application has "GitHub Copilot", "GitHub Copilot",
    Application has "Copilot Studio", "Copilot Studio",
    Application has "Security Copilot", "Security Copilot",
    Application has "Copilot" or Application has "Microsoft 365 Copilot", "Microsoft 365 Copilot",
    Application has "ChatGPT" or Application has "OpenAI", "ChatGPT",
    Application has "Claude" or Application has "Anthropic", "Claude",
    Application has "Gemini" or Application has "Bard", "Gemini",
    Application has "Perplexity", "Perplexity",
    Application has "Midjourney", "Midjourney",
    Application has "Bing Chat" or Application has "Bing Copilot", "Bing Chat Enterprise",
    Application has "Grammarly", "Grammarly",
    Application has "Notion", "Notion AI",
    Application has "Firefly" or Application has "Adobe Firefly", "Adobe Firefly",
    Application has "Jasper", "Jasper",
    Application has "Synthesia", "Synthesia",
    Application has "Runway", "Runway",
    Application has "Hugging Face", "Hugging Face",
    Application has "Canva", "Canva AI",
    Application has "Stability", "Stability AI",
    ""
)
| where isnotempty(AISolution)
| lookup kind=leftouter UserUpns on AccountObjectId
| extend UPN = tolower(coalesce(AccountUpn, AccountObjectId))
| extend YearMonth = format_datetime(Timestamp, "yyyy-MM")
| extend DeviceKey = coalesce(
    tostring(RawEventData.DeviceId),
    tostring(RawEventData.deviceId),
    tostring(IPAddress),
    tostring(DeviceType),
    "Unknown"
)
| summarize
    Sessions = count(),
    ActiveDays = dcount(bin(Timestamp, 1d)),
    EstimatedPrompts = countif(ActionType in ("MessageSent", "SearchPerformed", "AppAccessedViaAPI")),
    DistinctDevices = dcount(DeviceKey)
    by UPN, AISolution, YearMonth
| extend Category = case(
    AISolution in ("Microsoft 365 Copilot", "Bing Chat Enterprise"), "Productivity",
    AISolution == "GitHub Copilot", "Development",
    AISolution == "Copilot Studio", "Business Automation",
    AISolution == "Security Copilot", "Security AI",
    AISolution in ("ChatGPT", "Claude", "Gemini", "Perplexity"), "General AI",
    AISolution in ("Midjourney", "DALL-E", "Stability AI", "Adobe Firefly"), "Image Generation",
    AISolution in ("Grammarly", "Jasper"), "Writing",
    AISolution in ("Notion AI", "Canva AI"), "Productivity",
    AISolution in ("Synthesia", "Runway"), "Video",
    "Other"
)
| extend RiskTier = case(
    AISolution in ("Microsoft 365 Copilot", "GitHub Copilot", "Bing Chat Enterprise", "Copilot Studio", "Security Copilot"), "Sanctioned",
    AISolution in ("ChatGPT", "Adobe Firefly", "Grammarly", "DALL-E", "Canva AI"), "Conditional",
    "Unsanctioned"
)
| project UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts,
          DistinctDevices, Category, RiskTier
| order by UPN asc, YearMonth asc
```

</details>

> **Note:** `EstimatedPrompts` will be 0 for Microsoft 365 Copilot rows - use `ai_copilot_usage_graph.csv` (Step 1.2) for audit-event-derived Copilot activity. These values can differ from the official Microsoft 365 Copilot usage report. Some UPN values may appear as object IDs (guest/service accounts); those rows contribute to totals but will not filter by department.

### 1.4  ai_oauth_consents.csv  (Entra Audit Logs)

Run the PowerShell block in KQL Section A3 (uses Graph `Get-MgAuditLogDirectoryAudit`) → outputs `ai_oauth_consents.csv`.

### 1.5  ai_sso_signins.csv  (Entra Sign-In Logs)

Run the PowerShell block in KQL Section A4 (uses Graph `Get-MgAuditLogSignIn`) → outputs `ai_sso_signins.csv`.

### 1.6  🔍 ai_file_proximity.csv  (Defender Advanced Hunting — DeviceFileEvents + DeviceNetworkEvents)

**Requires:** MDE Plan 2 (both `DeviceFileEvents` and `DeviceNetworkEvents` tables must be available)  
**Output file:** `ai_file_proximity.csv`  
**Schema:** `Timestamp, UPN, AISolution, YearMonth, FileName, FolderCategory, FolderPath, SecondsToAI, NameMatchesSensitivePattern, FolderMatchesSensitive`

<details>
<summary><strong>📋 Click to expand KQL query (validated June 2026)</strong></summary>

```kql
let AIDomains = dynamic([
    "copilot.microsoft.com", "chat.openai.com", "chatgpt.com",
    "claude.ai", "gemini.google.com", "bard.google.com",
    "perplexity.ai", "midjourney.com", "huggingface.co",
    "stability.ai", "jasper.ai", "grammarly.com", "notion.so",
    "firefly.adobe.com", "runwayml.com", "canva.com",
    "app.synthesia.io"
]);
let SensitiveNamePatterns = dynamic([
    "confidential", "secret", "password", "credential", "private",
    "restricted", "internal", "draft", "salary", "ssn", "pii",
    "financial", "budget", "forecast", "strategy", "merger",
    "acquisition", "termination", "layoff", "patent"
]);
let SensitiveFolderPatterns = dynamic([
    "confidential", "restricted", "hr", "legal", "finance",
    "executive", "board", "compliance", "audit", "security"
]);
let AIVisits =
    DeviceNetworkEvents
    | where Timestamp > ago(30d)
    | where ActionType == "ConnectionSuccess"
    | where RemoteUrl has_any (AIDomains)
    | extend AISolution = case(
        RemoteUrl has "copilot.microsoft.com", "Microsoft 365 Copilot",
        RemoteUrl has "chat.openai.com" or RemoteUrl has "chatgpt.com", "ChatGPT",
        RemoteUrl has "claude.ai", "Claude",
        RemoteUrl has "gemini.google.com" or RemoteUrl has "bard.google.com", "Gemini",
        RemoteUrl has "perplexity.ai", "Perplexity",
        RemoteUrl has "midjourney.com", "Midjourney",
        RemoteUrl has "huggingface.co", "Hugging Face",
        RemoteUrl has "stability.ai", "Stability AI",
        RemoteUrl has "jasper.ai", "Jasper",
        RemoteUrl has "grammarly.com", "Grammarly",
        RemoteUrl has "notion.so", "Notion AI",
        RemoteUrl has "firefly.adobe.com", "Adobe Firefly",
        RemoteUrl has "runwayml.com", "Runway",
        RemoteUrl has "canva.com", "Canva AI",
        RemoteUrl has "app.synthesia.io", "Synthesia",
        "Other AI"
    )
    | project AITimestamp = Timestamp, DeviceId, AISolution;
let FileAccess =
    DeviceFileEvents
    | where Timestamp > ago(30d)
    | where ActionType in ("FileCreated", "FileModified", "FileRenamed", "FileCopied")
    | where FileName !endswith ".tmp" and FileName !endswith ".log"
    | project FileTimestamp = Timestamp, DeviceId, FileName, FolderPath,
              InitiatingProcessAccountUpn;
AIVisits
| join kind=inner FileAccess on DeviceId
| where FileTimestamp between (AITimestamp .. (AITimestamp + 5m))
| extend SecondsToAI = datetime_diff("second", FileTimestamp, AITimestamp)
| extend UPN = tolower(InitiatingProcessAccountUpn)
| extend YearMonth = format_datetime(AITimestamp, "yyyy-MM")
| extend FolderCategory = case(
    FolderPath has "Desktop", "Desktop",
    FolderPath has "Downloads", "Downloads",
    FolderPath has "Documents", "Documents",
    FolderPath has "OneDrive", "OneDrive",
    FolderPath has "SharePoint", "SharePoint",
    "Other"
)
| extend NameMatchesSensitivePattern = iff(FileName has_any (SensitiveNamePatterns), 1, 0)
| extend FolderMatchesSensitive = iff(FolderPath has_any (SensitiveFolderPatterns), 1, 0)
| project Timestamp = AITimestamp, UPN, AISolution, YearMonth, FileName,
          FolderCategory, FolderPath, SecondsToAI,
          NameMatchesSensitivePattern, FolderMatchesSensitive
| order by Timestamp asc
```

</details>

### 1.7  🔍 ai_offhours_geo.csv  (Defender Advanced Hunting — EntraIdSignInEvents)

**Output file:** `ai_offhours_geo.csv`  
**Schema:** `UPN, YearMonth, TotalSessions, OffHoursSessions, OffHoursPct, DistinctCountries, AnomalousCountryCount, AnomalousCountries`

<details>
<summary><strong>📋 Click to expand KQL query (v26.1 — validated June 2026)</strong></summary>

```kql
let AIAppNames = dynamic([
    "Microsoft 365 Copilot", "GitHub Copilot", "Copilot",
    "ChatGPT", "OpenAI", "Claude", "Anthropic",
    "Gemini", "Perplexity", "Midjourney", "Grammarly",
    "Notion", "Jasper", "Adobe Firefly", "Canva"
]);
let AISignIns =
    EntraIdSignInEvents
    | where Timestamp > ago(30d)
    | where ErrorCode == 0
    | where Application has_any (AIAppNames)
        or ResourceDisplayName has_any (AIAppNames)
    | extend UPN = tolower(AccountUpn)
    | extend YearMonth = format_datetime(Timestamp, "yyyy-MM")
    | extend HourOfDay = hourofday(Timestamp)
    | extend IsOffHours = iff(HourOfDay < 7 or HourOfDay >= 19, 1, 0)
    | extend Country = coalesce(Country, "Unknown")
    | project UPN, YearMonth, Timestamp, IsOffHours, Country;
let UserPrimaryCountry =
    AISignIns
    | summarize CountryCount = count() by UPN, Country
    | summarize TotalEvents = sum(CountryCount), arg_max(CountryCount, Country) by UPN
    | project UPN, PrimaryCountry = Country;
AISignIns
| summarize
    TotalSessions = count(),
    OffHoursSessions = countif(IsOffHours == 1),
    DistinctCountries = dcount(Country),
    Countries = make_set(Country)
    by UPN, YearMonth
| extend OffHoursPct = round(todouble(OffHoursSessions) / todouble(TotalSessions), 4)
| join kind=leftouter UserPrimaryCountry on UPN
| extend AnomalousCountries = set_difference(Countries, pack_array(PrimaryCountry))
| extend AnomalousCountryCount = array_length(AnomalousCountries)
| extend AnomalousCountries = iff(AnomalousCountryCount > 0,
    strcat_array(AnomalousCountries, "; "), "")
| project UPN, YearMonth, TotalSessions, OffHoursSessions, OffHoursPct,
          DistinctCountries, AnomalousCountryCount, AnomalousCountries
| order by UPN asc, YearMonth asc
```

</details>

### 1.8  ai_solutions_catalog.csv  (hand-maintained)

Open in Excel. Schema: `AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup`.

`RiskTier` values: `Sanctioned`, `Conditional`, `Unsanctioned`. The dashboard derives `LicenseStatus` (Licensed vs Shadow) from this column. `SolutionGroup` is a display grouping label (e.g. "Microsoft Copilot", "Third-Party AI").

Seed example in KQL Section A5.

### 1.9  🔍 ai_client_channel.csv  (Defender Advanced Hunting — DeviceNetworkEvents)

**Output file:** `ai_client_channel.csv`  
**Schema:** `AISite, Channel, YearMonth, EventCount`

<details>
<summary><strong>📋 Click to expand KQL query (validated June 2026)</strong></summary>

```kql
let AIDomains = dynamic([
    "copilot.microsoft.com", "copilot.cloud.microsoft",
    "chat.openai.com", "chatgpt.com", "api.openai.com",
    "claude.ai", "api.anthropic.com",
    "gemini.google.com", "bard.google.com",
    "perplexity.ai", "midjourney.com",
    "huggingface.co", "stability.ai", "jasper.ai",
    "grammarly.com", "notion.so", "firefly.adobe.com",
    "runwayml.com", "canva.com", "app.synthesia.io"
]);
DeviceNetworkEvents
| where Timestamp > ago(30d)
| where ActionType == "ConnectionSuccess"
| where RemoteUrl has_any (AIDomains)
| extend AISite = case(
    RemoteUrl has "copilot.microsoft.com" or RemoteUrl has "copilot.cloud.microsoft", "copilot.microsoft.com",
    RemoteUrl has "chat.openai.com" or RemoteUrl has "chatgpt.com", "chatgpt.com",
    RemoteUrl has "api.openai.com", "api.openai.com",
    RemoteUrl has "claude.ai", "claude.ai",
    RemoteUrl has "api.anthropic.com", "api.anthropic.com",
    RemoteUrl has "gemini.google.com" or RemoteUrl has "bard.google.com", "gemini.google.com",
    RemoteUrl has "perplexity.ai", "perplexity.ai",
    RemoteUrl has "midjourney.com", "midjourney.com",
    RemoteUrl has "huggingface.co", "huggingface.co",
    RemoteUrl has "stability.ai", "stability.ai",
    RemoteUrl has "jasper.ai", "jasper.ai",
    RemoteUrl has "grammarly.com", "grammarly.com",
    RemoteUrl has "notion.so", "notion.so",
    RemoteUrl has "firefly.adobe.com", "firefly.adobe.com",
    RemoteUrl has "runwayml.com", "runwayml.com",
    RemoteUrl has "canva.com", "canva.com",
    RemoteUrl has "app.synthesia.io", "app.synthesia.io",
    RemoteUrl
)
| extend Channel = case(
    InitiatingProcessFileName has_any ("chrome.exe", "msedge.exe", "firefox.exe",
        "brave.exe", "safari", "opera.exe", "iexplore.exe",
        "Chrome", "Safari", "Firefox"), "Browser",
    InitiatingProcessFileName has_any ("python", "node", "java", "curl",
        "powershell", "pwsh", "cmd.exe", "bash",
        "dotnet", "go"), "API",
    "Desktop"
)
| extend YearMonth = format_datetime(Timestamp, "yyyy-MM")
| summarize EventCount = count() by AISite, Channel, YearMonth
| order by AISite asc, YearMonth asc, Channel asc
```

</details>

---

## Step 2 — Path A: No MDA (create stubs)

If you don't have MDA deployed, save these three header-only CSVs (one row each) so Power Query loads cleanly:

**`ai_appgov_alerts.csv`**
```
Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description
```

**`ai_cloud_discovery.csv`**
```
AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus
```

**`ai_mda_sessions.csv`**
```
Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount
```

Because `CloudAppEvents` is also a Defender for Cloud Apps table, create this additional stub when that table is unavailable:

**`ai_activity_sessions.csv`**
```
UPN,AISolution,YearMonth,Sessions,ActiveDays,EstimatedPrompts,DistinctDevices,Category,RiskTier
```

MDA-dependent visuals, including the Shadow AI Catalog (MDA) page, remain empty. Activity-dependent visuals also remain empty when `ai_activity_sessions.csv` is a stub.

**Skip to Step 4.**

---

## Step 3 — Path B: Full MDA (populate the 3 extra CSVs)

### 3.1  🔍 ai_appgov_alerts.csv  (Defender Advanced Hunting — AlertInfo + AlertEvidence)

**Requires:** Microsoft Defender for Cloud Apps + App Governance enabled  
**Output file:** `ai_appgov_alerts.csv`  
**Schema:** `Timestamp, YearMonth, UPN, AppName, AlertType, Severity, Description`

<details>
<summary><strong>📋 Click to expand KQL query (v26.1 — validated June 2026)</strong></summary>

```kql
let AIAppNames = dynamic([
    "ChatGPT", "OpenAI", "Claude", "Anthropic", "Gemini",
    "Perplexity", "Midjourney", "Grammarly", "Jasper",
    "Notion", "Adobe Firefly", "Canva", "Synthesia", "Runway",
    "Stability", "Hugging Face", "Copilot", "GitHub Copilot"
]);
AlertInfo
| where Timestamp > ago(30d)
| where ServiceSource == "Microsoft Cloud App Security"
    or ServiceSource == "Microsoft Defender for Cloud Apps"
| join kind=inner (
    AlertEvidence
    | where Timestamp > ago(30d)
    | where EntityType == "User" or EntityType == "CloudApplication"
    | extend EvidenceDetail = case(
        EntityType == "User", AccountUpn,
        EntityType == "CloudApplication",
            tostring(parse_json(tostring(AdditionalFields)).AppName),
        ""
    )
    | summarize
        Users = make_set_if(EvidenceDetail, EntityType == "User"),
        Apps  = make_set_if(EvidenceDetail, EntityType == "CloudApplication")
        by AlertId
) on AlertId
| where Apps has_any (AIAppNames)
| mv-expand UPN = Users to typeof(string)
| mv-expand AppName = Apps to typeof(string)
| where AppName has_any (AIAppNames)
| extend YearMonth = format_datetime(Timestamp, "yyyy-MM")
| project Timestamp = format_datetime(Timestamp, "yyyy-MM-dd HH:mm:ss"),
          YearMonth,
          UPN = tolower(UPN),
          AppName,
          AlertType = Category,
          Severity,
          Description = Title
| order by Timestamp asc
```

</details>

> **Expected result if MDA App Governance is not active:** Query runs cleanly but returns **0 rows** — this is correct. Your `ServiceSource` will show "Microsoft Defender XDR" instead of "Microsoft Defender for Cloud Apps". Use the header-only stub CSV (Step 2) and the MDA page will display the yellow callout overlay.

### 3.2  ai_cloud_discovery.csv  (Cloud Discovery — Shadow AI catalog)

**Prereq:** MDA Cloud Discovery log uploader configured (firewall/proxy logs streaming into MDA).

1. Defender XDR → **Cloud Apps** → **Cloud Discovery** → **Discovered Apps**
2. Filter: `Category = Generative AI`
3. Time range: Last 90 days
4. **Export** → CSV
5. Run the PowerShell pivot in KQL Section **B7** to reshape to the expected schema.

### 3.3  🔍 ai_mda_sessions.csv  (Defender Advanced Hunting — CloudAppEvents)

**Requires:** MDA + Conditional Access App Control policies configured for at least one AI app  
**Output file:** `ai_mda_sessions.csv`  
**Schema:** `Timestamp, YearMonth, UPN, AppName, ActionType, PolicyHit, PolicyAction, IPAddress, CountryCode, EventCount`
**Value domains:** `PolicyHit` is `TRUE` or `FALSE`; `PolicyAction` is `Allow`, `Warn`, or `Block`.

<details>
<summary><strong>📋 Click to expand KQL query (v26.1 — validated June 2026)</strong></summary>

```kql
let AIAppNames = dynamic([
    "Microsoft 365 Copilot", "GitHub Copilot", "Copilot",
    "ChatGPT", "OpenAI", "Claude", "Anthropic",
    "Gemini", "Perplexity", "Midjourney", "Grammarly",
    "Notion", "Jasper", "Adobe Firefly", "Canva",
    "Synthesia", "Runway", "Stability", "Hugging Face"
]);
let UserUpns = IdentityInfo
    | summarize take_any(AccountUpn) by AccountObjectId;
CloudAppEvents
| where Timestamp > ago(30d)
| where Application has_any (AIAppNames)
| where ActionType in (
    "FileUploaded", "FileDownloaded", "FilePreviewed",
    "PasteAction", "PrintAction", "CopyAction",
    "SessionLogon", "SessionLogoff",
    "AppAccessBlocked", "FileBlocked", "UploadBlocked"
)
| lookup kind=leftouter UserUpns on AccountObjectId
| extend UPN = tolower(coalesce(AccountUpn, AccountObjectId))
| extend YearMonth = format_datetime(Timestamp, "yyyy-MM")
| extend PolicyName = tostring(RawEventData.PolicyName)
| extend PolicyHit = iff(isnotempty(PolicyName), "TRUE", "FALSE")
| extend PolicyAction = case(
    ActionType has "Blocked", "Block",
    ActionType has "Warn" or ActionType has "Monitor" or PolicyHit == "TRUE", "Warn",
    "Allow"
)
| extend IPAddress = tostring(IPAddress)
| extend CountryCode = tostring(RawEventData.CountryCode)
| summarize
    EventCount = count(),
    Timestamp = min(Timestamp)
    by YearMonth, UPN,
       AppName = Application,
       ActionType,
       PolicyHit,
       PolicyAction,
       IPAddress,
       CountryCode
| extend Timestamp = format_datetime(Timestamp, "yyyy-MM-dd HH:mm:ss")
| project Timestamp, YearMonth, UPN, AppName, ActionType, PolicyHit,
          PolicyAction, IPAddress, CountryCode, EventCount
| order by Timestamp asc
```

</details>

> **Expected result without MDA CAAC:** Query runs cleanly but returns **0 rows** — this is correct. Use the header-only stub CSV (Step 2).

---

## Step 4 - Open the PBIT

1. Double-click [AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit](AI-Solutions-Intelligence-Dashboard%20V27%20In%20Testing.pbit). Use [V26 Validated](AI-Solutions-Intelligence-Dashboard%20V26%20Validated.pbit) when you need the stable release.
2. When prompted for **`AI_Data_Folder_Path`**, paste your folder path:
   - Windows: `C:\AI_Usage_Data`
3. Click **Load**
4. Wait for refresh (1–3 min depending on tenant size)
5. **File → Save As** → save as PBIX with a descriptive name (e.g. `AI_Solutions_<TenantName>_<YYYY-MM-DD>.pbix`)

---

## Step 5 — Verify

| Check | Expected |
|---|---|
| "Executive Summary" KPI cards | All headline metrics show numbers (not blanks or errors) |
| "Dept Intensity by Solution" bubble chart | Bubbles plotted; X-axis 0–7 |
| "Behavioral Risk" KPIs | Per-user averages displayed (requires MDE P2 data) |
| "Shadow AI" page | Unmanaged AI users and % using unmanaged AI displayed |
| "Shadow AI Catalog (MDA)" — **Path A** | Yellow callout shown, visuals empty (expected) |
| "Shadow AI Catalog (MDA)" — **Path B** | Yellow callout shown, KPIs and detail table populated |
| "Benchmarks & Targets" | Target sliders functional, gap indicators populated |
| "Tier Comparison" | Coverage matrix renders |
| "Glossary & Data Dictionary" | Category / term definitions table renders |

---

## Step 6 — Refresh schedule (optional)

To keep the report current:
1. Re-run Steps 1.x (and 3.x for Path B) on whatever cadence you want — weekly is typical.
2. Overwrite the CSVs in your data folder.
3. In Power BI Desktop: **Home → Refresh**, save.
4. For Power BI Service refresh, either keep the local/UNC Folder source and configure an on-premises data gateway, or redesign the Power Query source to use the SharePoint/OneDrive connector and configure its credentials before publishing. Publishing alone does not make `C:\AI_Usage_Data` refreshable in the service.

---

## Upgrading from No-MDA to Full MDA

When MDA gets deployed in your tenant later:
1. Run KQL Sections B6 / B7 / B8
2. **Overwrite** the three stub CSVs with the real exports
3. Refresh the report — MDA pages light up automatically
4. No PBIT change needed

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "We couldn't find the file" on load | Folder path is incorrect or the expected CSV is missing | Confirm the folder and CSV filename shown in the error |
| "Shadow AI Catalog (MDA)" visuals blank but no overlay | Stub CSV missing | Create the header-only CSV from Step 2 |
| All Copilot prompt counts = 0 | Used Defender CloudAppEvents instead of Purview | Re-export both Copilot CSVs with `Collect-AICopilotUsage.ps1` (Step 1.2) |
| Weekly Days > 7 | Old PBIT version | Re-download the latest PBIT; the `Weekly Days Used per User` measure is hard-capped at 7 |
| "Behavioral Risk" page empty | Missing MDE Plan 2 export | Re-export `ai_file_proximity.csv` and `ai_offhours_geo.csv` (Steps 1.6, 1.7) |
| Calendar slicer day-grain doesn't filter facts | Expected — fact tables are at month grain | Use Year / Quarter / Month slicer instead |

---

## Interpretation and data protection

- V27 is experimental and **In Testing**. Use the
  [interpretation guide](INTERPRETATION_GUIDE.md) before operational use.
- Risk scores, geo anomalies, file proximity, and estimated prompts are heuristic
  triage signals. They are not proof of misuse, disclosure, policy breach, or data
  leakage.
- Purview audit-derived Copilot counts can differ from the official Microsoft 365
  Copilot usage report.
- Generated CSVs and derived PBIX files are not automatically labeled, encrypted,
  or access-controlled. Apply organizational sensitivity labels, retention,
  storage controls, and least-access rules before sharing.
- Customers are responsible for lawful collection and use, notices and consent,
  data residency, and compliance with organizational policy and applicable law.

---

## File reference

| File | Source | Schema |
|---|---|---|
| [AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit](AI-Solutions-Intelligence-Dashboard%20V27%20In%20Testing.pbit) | Current testing Power BI template; compatible with the V26 13-file contract | — |
| [AI-Solutions-Intelligence-Dashboard V26 Validated.pbit](AI-Solutions-Intelligence-Dashboard%20V26%20Validated.pbit) | Power BI template (10 pages, 123 measures) | — |
| [AI_Usage_v26_Blueprint.md](AI_Usage_v26_Blueprint.md) | Architecture & page-tier mapping | — |
| [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql) | All collection queries (A1–A5, B2–B8) | — |

| CSV | Tier | Optional? | Schema (header) |
|---|---|---|---|
| EntraUsers.csv | Baseline | No | `userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,hasLicense,assignedLicenses,manager_displayName,manager_userPrincipalName` |
| ai_copilot_usage_graph.csv | Baseline (Purview) | No | `UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate` |
| ai_copilot_surface_usage.csv | Baseline (Purview) | No | `UserPrincipalName,YearMonth,Surface,SourceWorkload,SourceAppHost,PromptCount,ActiveDays,LastActivityDate` |
| ai_activity_sessions.csv | Baseline (Defender) | No | `UPN,AISolution,YearMonth,Sessions,ActiveDays,EstimatedPrompts,DistinctDevices,Category,RiskTier` |
| ai_oauth_consents.csv | Baseline (Entra) | No | `UPN,AppName,YearMonth,ConsentCount,LastConsent,PermissionWeight,Permissions` |
| ai_sso_signins.csv | Baseline (Entra) | No | `UPN,Application,YearMonth,SignInCount,DistinctDays,IsGuest,Countries,HasConditionalAccess,LastSignIn` |
| ai_file_proximity.csv | MDE P2 | No (stub if missing MDE P2) | `Timestamp,UPN,AISolution,YearMonth,FileName,FolderCategory,FolderPath,SecondsToAI,NameMatchesSensitivePattern,FolderMatchesSensitive` |
| ai_offhours_geo.csv | Entra ID P2 + Defender XDR Advanced Hunting | No (stub if table unavailable) | `UPN,YearMonth,TotalSessions,OffHoursSessions,OffHoursPct,DistinctCountries,AnomalousCountryCount,AnomalousCountries` |
| ai_solutions_catalog.csv | Manual | No | `AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup` |
| ai_client_channel.csv | MDE P2 / MDA | No (stub if missing) | `AISite,Channel,YearMonth,EventCount` |
| ai_appgov_alerts.csv | **MDA only** | Stub if no MDA | `Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description` |
| ai_cloud_discovery.csv | **MDA only** | Stub if no MDA | `AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus` |
| ai_mda_sessions.csv | **MDA only** | Stub if no MDA | `Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount` |
