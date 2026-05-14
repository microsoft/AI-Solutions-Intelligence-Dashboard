# AI Usage Dashboard v26 — Setup Instructions

**One report. Two paths.** Choose the path that matches your tenant.

| Path | Who it's for | CSVs you populate | CSVs you stub |
|---|---|---|---|
| **Path A — No MDA** | M365 E5 + MDE Plan 2, MDA not deployed | 9 baseline CSVs | 3 MDA stubs |
| **Path B — Full MDA** | M365 E5 + MDE Plan 2 + MDA + App Governance | All 12 CSVs | 0 |

The PBIT is identical for both paths — the difference is just what's in the data folder.

---

## Step 0 — Prerequisites

- Power BI Desktop (latest)
- One folder for all CSVs, e.g. `C:\AI_Usage_Data\` (Windows) or `~/AI_Usage_Data/` (Mac)
- The PBIT file: [AI Solutions Unified May 4th v5.pbit](AI%20Solutions%20Unified%20May%204th%20v5.pbit)
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

### 1.3  ai_activity_sessions.csv  (Defender CloudAppEvents)

Defender XDR → Advanced Hunting → paste KQL Section B2 → Run → Export CSV.

### 1.4  ai_oauth_consents.csv  (Entra Audit Logs)

Run the PowerShell block in KQL Section A3 (uses Graph `Get-MgAuditLogDirectoryAudit`) → outputs `ai_oauth_consents.csv`.

### 1.5  ai_sso_signins.csv  (Entra Sign-In Logs)

Run the PowerShell block in KQL Section A4 (uses Graph `Get-MgAuditLogSignIn`) → outputs `ai_sso_signins.csv`.

### 1.6  ai_file_proximity.csv  (MDE Plan 2)

Defender XDR → Advanced Hunting → paste KQL Section B3 → Run → Export CSV.

### 1.7  ai_offhours_geo.csv  (AADSignInEventsBeta)

Defender XDR → Advanced Hunting → paste KQL Section B4 → Run → Export CSV.

### 1.8  ai_solutions_catalog.csv  (hand-maintained)

Open in Excel. Schema: `AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup`.

`RiskTier` values: `Sanctioned`, `Conditional`, `Unsanctioned`. The dashboard derives `LicenseStatus` (Licensed vs Shadow) from this column. `SolutionGroup` is a display grouping label (e.g. "Microsoft Copilot", "Third-Party AI").

Seed example in KQL Section A5.

### 1.9  ai_client_channel.csv  (Browser/Desktop/API split)

Defender XDR → Advanced Hunting → paste KQL Section B5 → Run → Export CSV.

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

### 3.1  ai_appgov_alerts.csv  (App Governance ML alerts)

**Prereq:** Defender for Cloud Apps + App Governance enabled.

Defender XDR → Advanced Hunting → paste KQL Section **B6** → Run → Export CSV.

### 3.2  ai_cloud_discovery.csv  (Cloud Discovery — Shadow AI catalog)

**Prereq:** MDA Cloud Discovery log uploader configured (firewall/proxy logs streaming into MDA).

1. Defender XDR → **Cloud Apps** → **Cloud Discovery** → **Discovered Apps**
2. Filter: `Category = Generative AI`
3. Time range: Last 90 days
4. **Export** → CSV
5. Run the PowerShell pivot in KQL Section **B7** to reshape to the expected schema.

### 3.3  ai_mda_sessions.csv  (Conditional Access App Control sessions)

**Prereq:** Defender for Cloud Apps + MDA app connector for at least one AI app (e.g. ChatGPT Enterprise reverse-proxied through MDA).

Defender XDR → Advanced Hunting → paste KQL Section **B8** → Run → Export CSV.

---

## Step 4 — Open the PBIT

1. Double-click [AI Solutions Unified May 4th v5.pbit](AI%20Solutions%20Unified%20May%204th%20v5.pbit)
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
| "Action Plan" | Verdicts, scorecards, and top actions displayed |

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
| Page 11/12/13 visuals blank but no overlay | Stub CSV missing | Create the header-only CSV from Step 2 |
| All Copilot prompt counts = 0 | Used Defender CloudAppEvents instead of Purview | Re-export `ai_copilot_usage_graph.csv` from Purview Audit (Step 1.2) |
| Weekly Days > 7 | Old PBIT version | Re-download the latest PBIT; the `Weekly Days Used per User` measure is hard-capped at 7 |
| "Behavioral Risk" page empty | Missing MDE Plan 2 export | Re-export `ai_file_proximity.csv` and `ai_offhours_geo.csv` (Steps 1.6, 1.7) |
| Calendar slicer day-grain doesn't filter facts | Expected — fact tables are at month grain | Use Year / Quarter / Month slicer instead |

---

## File reference

| File | Source | Schema |
|---|---|---|
| [AI Solutions Unified May 4th v5.pbit](AI%20Solutions%20Unified%20May%204th%20v5.pbit) | Power BI template (15 pages, 122 measures) | — |
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
