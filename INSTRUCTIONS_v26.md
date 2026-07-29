# AI Solutions Intelligence Dashboard v26.1 — Setup Instructions

**One report. Two paths.** Choose the path that matches your tenant.

| Path | Who it's for | CSVs you populate | CSVs you stub |
|---|---|---|---|
| **Path A — No MDA** | M365 E5 + MDE Plan 2, MDA not deployed | 9 baseline CSVs | 3 MDA stubs |
| **Path B — Full MDA** | M365 E5 + MDE Plan 2 + MDA + App Governance | All 12 CSVs | 0 |

The PBIT is identical for both paths — the difference is just what's in the data folder.

---

## Quick Reference — What tool does each CSV need?

| Step | CSV file | Tool | Requires |
|---|---|---|---|
| 1.1 | `EntraUsers.csv` | 💻 PowerShell (Microsoft Graph) | Graph API |
| 1.2 | `ai_copilot_usage_graph.csv` | 💻 PowerShell (Purview Audit) or 🌐 Graph API | Purview Audit reader |
| **1.3** | **`ai_activity_sessions.csv`** | **🔍 Defender Advanced Hunting** | **MDE / MDA connected** |
| 1.4 | `ai_oauth_consents.csv` | 💻 PowerShell (Microsoft Graph) | AuditLog.Read.All |
| 1.5 | `ai_sso_signins.csv` | 💻 PowerShell (Microsoft Graph) | AuditLog.Read.All |
| **1.6** | **`ai_file_proximity.csv`** | **🔍 Defender Advanced Hunting** | **MDE Plan 2** |
| **1.7** | **`ai_offhours_geo.csv`** | **🔍 Defender Advanced Hunting** | **AADSignInEventsBeta** |
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

- Power BI Desktop (latest)
- One folder for all CSVs, e.g. `C:\AI_Usage_Data\` (Windows) or `~/AI_Usage_Data/` (Mac)
- The PBIT file: [AI-Solutions-Intelligence-Dashboard V26.pbit](AI-Solutions-Intelligence-Dashboard%20V26.pbit)
- The KQL pack: [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql)

Permissions you will need over the course of setup:
- Microsoft Graph: `Reports.Read.All`, `AuditLog.Read.All`, `Directory.Read.All`, `Application.Read.All`
- Microsoft Defender XDR: Advanced Hunting access (Security Reader minimum)
- Microsoft Purview: eDiscovery / Audit reader (or use PowerShell `Search-UnifiedAuditLog`)
- Defender for Cloud Apps (Path B only): Reader on the MDA portal + App Governance reader

---

## Step 1 — Collect baseline CSVs (both paths)

These 9 CSVs power the core dashboard pages (Executive Summary, Copilot Deep Dive, Behavioral Risk, Shadow AI, Dept Intensity by Solution, Department Breakdown, Benchmarks & Targets, and more).

### 1.1  EntraUsers.csv  (Microsoft Graph)

```powershell
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"
Get-MgUser -All `
  -Property "userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,assignedLicenses,manager" `
  -ExpandProperty manager |
  Select-Object userPrincipalName,displayName,department,jobTitle,city,country,companyName,
                accountEnabled,userType,createdDateTime,
    @{n='hasLicense';e={ if ($_.AssignedLicenses.Count -gt 0) {'TRUE'} else {'FALSE'} }},
    @{n='assignedLicenses';e={ ($_.AssignedLicenses.SkuId) -join ';' }},
    @{n='manager_displayName';      e={ $_.Manager.AdditionalProperties.displayName }},
    @{n='manager_userPrincipalName';e={ $_.Manager.AdditionalProperties.userPrincipalName }} |
  Export-Csv -NoTypeInformation EntraUsers.csv
```

> Replace Copilot SKU GUIDs with the literal "Copilot" so the License Utilization measure works:
> `(Get-Content EntraUsers.csv) -replace '05e9a617-0261-4cee-bb44-138d3ef5d965','Copilot_M365' | Set-Content EntraUsers.csv`

### 1.2  ai_copilot_usage_graph.csv  (Purview Audit OR Graph Reports API)

The Power Query loads a file named **`ai_copilot_usage_graph.csv`**. You can populate it from either source:

**Option A (Purview — recommended, richer per-surface data):**
Run the PowerShell script in `kql_queries_v22_E5V3.kql` Section A2. It searches Purview Audit for `CopilotInteraction` events and pivots them into per-user monthly prompt counts by surface (Teams/Word/Excel/Outlook/PowerPoint/Chat).

**Option B (Graph Reports API — simpler):**
```
GET https://graph.microsoft.com/v1.0/reports/getMicrosoft365CopilotUsageUserDetail(period='D90')
```
Save the response as `ai_copilot_usage_graph.csv`.

> **Important:** Whichever source you choose, the output file must be named `ai_copilot_usage_graph.csv`.
>
> Why Purview over Defender CloudAppEvents? CloudAppEvents only captures the BizChat surface — it misses in-app Copilot in Word/Excel/PPT/Outlook/Teams. Purview is the only complete source.

### 1.3  🔍 ai_activity_sessions.csv  (Defender Advanced Hunting — CloudAppEvents)

**Output file:** `ai_activity_sessions.csv`  
**Schema:** `UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts, DistinctDevices, Category, RiskTier`

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
| where Timestamp > ago(180d)
| where Application has_any (AIAppNames)
| extend AISolution = case(
    Application has "Copilot" or Application has "Microsoft 365 Copilot", "Microsoft 365 Copilot",
    Application has "GitHub Copilot", "GitHub Copilot",
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
| summarize
    Sessions = count(),
    ActiveDays = dcount(bin(Timestamp, 1d)),
    EstimatedPrompts = countif(ActionType in ("MessageSent", "SearchPerformed", "AppAccessedViaAPI")),
    DistinctDevices = dcount(DeviceType)
    by UPN, AISolution, YearMonth
| extend Category = case(
    AISolution in ("Microsoft 365 Copilot", "GitHub Copilot", "Bing Chat Enterprise"), "Productivity",
    AISolution in ("ChatGPT", "Claude", "Gemini", "Perplexity"), "General AI",
    AISolution in ("Midjourney", "DALL-E", "Stability AI", "Adobe Firefly"), "Image Generation",
    AISolution in ("Grammarly", "Jasper"), "Writing",
    AISolution in ("Notion AI", "Canva AI"), "Productivity",
    AISolution in ("Synthesia", "Runway"), "Video",
    "Other"
)
| extend RiskTier = case(
    AISolution in ("Microsoft 365 Copilot", "GitHub Copilot", "Bing Chat Enterprise"), "Sanctioned",
    AISolution in ("ChatGPT", "Adobe Firefly", "Grammarly", "DALL-E", "Canva AI"), "Conditional",
    "Unsanctioned"
)
| project UPN, AISolution, YearMonth, Sessions, ActiveDays, EstimatedPrompts,
          DistinctDevices, Category, RiskTier
| order by UPN asc, YearMonth asc
```

</details>

> **Note:** `EstimatedPrompts` will be 0 for Microsoft 365 Copilot rows — use `ai_copilot_usage_graph.csv` (Step 1.2) for authoritative Copilot prompt counts. Some UPN values may appear as object IDs (guest/service accounts) — those rows contribute to totals but won't filter by department.

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
    | where Timestamp > ago(90d)
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
    | where Timestamp > ago(90d)
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

### 1.7  🔍 ai_offhours_geo.csv  (Defender Advanced Hunting — AADSignInEventsBeta)

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
    AADSignInEventsBeta
    | where Timestamp > ago(90d)
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

> **Schema note:** The country column name differs by environment. This query uses `Country` (correct for Sentinel workspaces). If running in **native Defender XDR Advanced Hunting**, change `coalesce(Country, "Unknown")` to `coalesce(CountryCode, "Unknown")`.

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
| where Timestamp > ago(90d)
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

The three MDA pages (11, 12, 13) will display the yellow "MDA Required" callout and empty visuals. Everything else works.

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
| where Timestamp > ago(180d)
| where ServiceSource == "Microsoft Cloud App Security"
    or ServiceSource == "Microsoft Defender for Cloud Apps"
| join kind=inner (
    AlertEvidence
    | where Timestamp > ago(180d)
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
| where Timestamp > ago(90d)
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
| extend PolicyHit = tostring(RawEventData.PolicyName)
| extend PolicyAction = case(
    ActionType has "Blocked", "Block",
    ActionType has "Monitor", "Monitor",
    isnotempty(PolicyHit), "Alert",
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

## Step 4 — Open the PBIT

1. Double-click [AI-Solutions-Intelligence-Dashboard V26.pbit](AI-Solutions-Intelligence-Dashboard%20V26.pbit)
2. When prompted for **`AI_Data_Folder_Path`**, paste your folder path (with trailing slash):
   - Windows: `C:\AI_Usage_Data\`
   - Mac: `/Users/yourname/AI_Usage_Data/`
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
4. (Or publish to Power BI Service and configure scheduled refresh against OneDrive / SharePoint hosting the CSVs.)

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
| "We couldn't find the file" on load | Folder path missing trailing slash | Add trailing `\` (Windows) or `/` (Mac) |
| "Shadow AI Catalog (MDA)" visuals blank but no overlay | Stub CSV missing | Create the header-only CSV from Step 2 |
| All Copilot prompt counts = 0 | Used Defender CloudAppEvents instead of Purview | Re-export `ai_copilot_usage_graph.csv` from Purview Audit (Step 1.2) |
| Weekly Days > 7 | Old PBIT version | Re-download the latest PBIT; the `Weekly Days Used per User` measure is hard-capped at 7 |
| "Behavioral Risk" page empty | Missing MDE Plan 2 export | Re-export `ai_file_proximity.csv` and `ai_offhours_geo.csv` (Steps 1.6, 1.7) |
| Calendar slicer day-grain doesn't filter facts | Expected — fact tables are at month grain | Use Year / Quarter / Month slicer instead |

---

## File reference

| File | Source | Schema |
|---|---|---|
| [AI-Solutions-Intelligence-Dashboard V26.pbit](AI-Solutions-Intelligence-Dashboard%20V26.pbit) | Power BI template (10 pages, 122 measures) | — |
| [AI_Usage_v26_Blueprint.md](AI_Usage_v26_Blueprint.md) | Architecture & page-tier mapping | — |
| [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql) | All collection queries (A1–A5, B2–B8) | — |

| CSV | Tier | Optional? | Schema (header) |
|---|---|---|---|
| EntraUsers.csv | Baseline | No | `userPrincipalName,displayName,department,jobTitle,city,country,companyName,accountEnabled,userType,createdDateTime,hasLicense,assignedLicenses,manager_displayName,manager_userPrincipalName` |
| ai_copilot_usage_graph.csv | Baseline (Purview or Graph) | No | `UserPrincipalName,YearMonth,TeamsPrompts,WordPrompts,ExcelPrompts,OutlookPrompts,PowerPointPrompts,ChatPrompts,TotalPrompts,ActiveDays,LastActivityDate` |
| ai_activity_sessions.csv | Baseline (Defender) | No | `UPN,AISolution,YearMonth,Sessions,ActiveDays,EstimatedPrompts,DistinctDevices,Category,RiskTier` |
| ai_oauth_consents.csv | Baseline (Entra) | No | `UPN,AppName,YearMonth,ConsentCount,LastConsent,PermissionWeight,Permissions` |
| ai_sso_signins.csv | Baseline (Entra) | No | `UPN,Application,YearMonth,SignInCount,DistinctDays,IsGuest,Countries,HasConditionalAccess,LastSignIn` |
| ai_file_proximity.csv | MDE P2 | No (stub if missing MDE P2) | `Timestamp,UPN,AISolution,YearMonth,FileName,FolderCategory,FolderPath,SecondsToAI,NameMatchesSensitivePattern,FolderMatchesSensitive` |
| ai_offhours_geo.csv | Defender | No | `UPN,YearMonth,TotalSessions,OffHoursSessions,OffHoursPct,DistinctCountries,AnomalousCountryCount,AnomalousCountries` |
| ai_solutions_catalog.csv | Manual | No | `AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup` |
| ai_client_channel.csv | MDE P2 / MDA | No (stub if missing) | `AISite,Channel,YearMonth,EventCount` |
| ai_appgov_alerts.csv | **MDA only** | Stub if no MDA | `Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description` |
| ai_cloud_discovery.csv | **MDA only** | Stub if no MDA | `AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus` |
| ai_mda_sessions.csv | **MDA only** | Stub if no MDA | `Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount` |
