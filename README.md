# AI Solutions Intelligence Dashboard

<div align="center">

![Current Version](https://img.shields.io/badge/version-v26.1%20Validated-blue)

**A single Power BI report that delivers a complete, defensible view of AI usage across your Microsoft 365 tenant — Copilot adoption, shadow AI, OAuth risk, off-hours/geo anomalies, and (optionally) MDA App Governance & Cloud Discovery — all in one PBIT.**

> **v26.1 — June 23, 2026:** All KQL queries in `kql_queries_v22_E5V3.kql` have been live-tested against a real tenant. Eight bugs fixed across B2, B4, B6, and B8 (UPN resolution, schema portability between Sentinel and native Defender XDR, KQL syntax errors). B3 and B5 validated clean. See the [query pack changelog](kql_queries_v22_E5V3.kql) for details.

### 📥 [Click Here to Download All Files](https://github.com/microsoft/AI-Solutions-Intelligence-Dashboard/archive/refs/heads/main.zip)

**Related Templates & Tools:**

[![Start Here](https://img.shields.io/badge/Guide-Start%20Here-brightgreen)](DATA_SETUP_START_HERE.md)
[![PAX Exporter](https://img.shields.io/badge/Tool-PAX%20Exporter-8A2BE2)](PAX_Exporter/README.md)
[![Dashboard PBIT](https://img.shields.io/badge/Report-Dashboard%20PBIT-003087)](AI-Solutions-Intelligence-Dashboard%20V26%20Validated.pbit)
[![Architecture Blueprint](https://img.shields.io/badge/Report-Architecture%20Blueprint-teal)](AI_Usage_v26_Blueprint.md)
[![Setup Instructions](https://img.shields.io/badge/Report-Setup%20Instructions-purple)](INSTRUCTIONS_v26.md)
[![KQL Query Pack](https://img.shields.io/badge/Report-KQL%20Query%20Pack-darkgreen)](kql_queries_v22_E5V3.kql)
[![Sample Data Generator](https://img.shields.io/badge/Report-Sample%20Data%20Generator-orange)](build_v26_sample_data.py)
[![PBIT Generator](https://img.shields.io/badge/Tool-PBIT%20Generator-red)](generate_pbit_v26_unified.py)

**Additional Resources:**
[Defender for Endpoint docs](https://learn.microsoft.com/defender-endpoint/) · [Defender for Cloud Apps docs](https://learn.microsoft.com/defender-cloud-apps/) · [Microsoft Purview Audit docs](https://learn.microsoft.com/purview/audit-solutions-overview) · [Microsoft Graph Reports API](https://learn.microsoft.com/graph/api/resources/report)

⭐ **Star this repository** to receive notifications about new template versions
👀 **Watch** for updates and announcements

</div>

---

## ▶️ Report preview

<div align="center"><img src="images/report-preview.gif" alt="Animated preview of all 10 AI Solutions Intelligence Dashboard pages using synthetic sample data" width="900"></div>

*Representative tour of all 10 pages, generated exclusively from the repository's synthetic `sample_data_v26` files. The preview contains aggregate sample metrics only—no tenant or employee data.*

---

## 🧭 Choose how to collect your data

Every tenant loads the **same report** from the **same 13 CSV files** — you just pick how to generate them.

<table>
<tr>
<td width="33%" valign="top">

### 🟢 Under ~10,000 users
**Manual CSV export**

Copy-paste queries into the portal and click Export. A few files need one short PowerShell step.

➡️ **[Start Here](DATA_SETUP_START_HERE.md)** · [Full manual guide](INSTRUCTIONS_v26.md)

</td>
<td width="33%" valign="top">

### 🔵 Over ~10,000 users
**Automated PAX exporter**

Run our updated scripts — they page past Defender's 10,000-row cap for you.

➡️ **[PAX Exporter](PAX_Exporter/README.md)**

</td>
<td width="33%" valign="top">

### 🧪 Just exploring
**Sample data**

Generate realistic sample CSVs and tour the report with no tenant access.

➡️ **[Sample Data Generator](build_v26_sample_data.py)**

</td>
</tr>
</table>

---

## 📚 Continue reading

<table>
<tr>
<td width="33%" valign="top">

**1 · [Start Here](DATA_SETUP_START_HERE.md)**

The friendly, non-technical overview. Begin here if you're new.

</td>
<td width="33%" valign="top">

**2 · [Setup & data collection](INSTRUCTIONS_v26.md)**

Every CSV, click-by-click — Graph, Purview, and Defender.

</td>
<td width="33%" valign="top">

**3 · [Automated exporter](PAX_Exporter/README.md)**

Run the PAX scripts to pull everything, past the 10K-row cap.

</td>
</tr>
<tr>
<td width="33%" valign="top">

**4 · [KQL query pack](kql_queries_v22_E5V3.kql)**

The six validated Defender Advanced Hunting queries (v26.1).

</td>
<td width="33%" valign="top">

**5 · [Architecture blueprint](AI_Usage_v26_Blueprint.md)**

The tier model, measure design, and generator pipeline.

</td>
<td width="33%" valign="top">

**6 · [Security & license](SECURITY.md)**

Read-only permissions, data handling, and licensing notes.

</td>
</tr>
</table>

---

<details open>
<summary><strong>📊 Why Use This Report & Insights You Can Explore</strong></summary>

<br>

This dashboard replaces fragmented, surface-level AI adoption reports with a single, unified view that spans Copilot usage, shadow AI detection, OAuth risk scoring, behavioral anomalies, and (optionally) Microsoft Defender for Cloud Apps signals. The same PBIT loads on every tier; visuals remain empty when their required source table is unavailable.

**Executive Overview:**
Track total AI users, adoption rate, license utilization, top tools, and monthly trends at a glance. Identify the gap between licensed capacity and actual usage with KPI cards that surface workforce adoption, per-surface Copilot prompt counts (Teams, Word, Excel, Outlook, PowerPoint, Chat), and department-level activity breakdowns.

**AI Adoption Strategy:**
Detect shadow AI usage across unsanctioned tools, assess behavioral risk through file-proximity analysis and off-hours/geo anomalies, and review OAuth consent patterns with permission-weighted risk scores. Coverage is source-specific: MDE Plan 2 supplies device-event signals, Entra supplies sign-ins, Purview supplies Copilot interactions, and Defender for Cloud Apps supplies `CloudAppEvents`, App Governance, and Cloud Discovery.

**Solution Priority:**
Prioritize AI tool governance with the solutions catalog (Sanctioned / Conditional / Unsanctioned tiers), benchmark adoption against configurable targets, and use the tier comparison matrix to understand which pages and signals map to your available data sources.

**AI Solutions Usage Activity & Trends:**
Drill into per-user activity across all signals, visualize department intensity with bubble charts (weekly days vs. weekly actions per user, capped at 7), and break down AI client channels (Browser / Desktop / API) by AI site. Optional MDA pages provide OAuth anomaly alerts, cloud discovery shadow AI catalogs with risk scores, and per-session DLP/policy enforcement intelligence.

</details>

---

<details>
<summary><strong style="font-size:1.5em;">🖥️ Report Pages Overview</strong></summary>

<br>

The dashboard includes **10** interactive report pages organized into core analytics, an MDA-powered catalog, and a consolidated glossary & data dictionary.

---

### 1. Executive Summary

KPI cards showing total AI users, adoption rate, top tools, and monthly trends. Includes workforce adoption donut, license utilization gauge, gap-to-target indicators, Copilot adoption percentage, and executive narrative verdicts. Works on E3 + Copilot baseline tier.

*Screenshot coming soon*
*Click image to enlarge*

---

### 2. Copilot Deep Dive

Dynamic Copilot prompt breakdowns for every surface observed by Purview Audit, including Teams, Word, Excel, Outlook, PowerPoint, Chat, Loop, OneNote, SharePoint, Edge, and future workloads. Requires `ai_copilot_usage_graph.csv` and `ai_copilot_surface_usage.csv`.

*Screenshot coming soon*
*Click image to enlarge*

---

### 3. Behavioral Risk

Per-user risk scoring with file-proximity analysis (files accessed within 5 minutes of AI site visits), off-hours session percentages, geo anomaly counts, and composite AI Risk Score. OAuth consent patterns use Graph audit data. File proximity requires MDE Plan 2; off-hours analysis requires `EntraIdSignInEvents`.

*Screenshot coming soon*
*Click image to enlarge*

---

### 4. Shadow AI

Unmanaged AI detection showing unsanctioned tool usage, non-Microsoft AI activity, percentage of users on unmanaged tools, and tool sprawl metrics. This page is populated by `CloudAppEvents` and therefore requires Defender for Cloud Apps; the MDE-only file-proximity and client-channel exports do not populate it.

*Screenshot coming soon*
*Click image to enlarge*

---

### 5. Dept Intensity by Solution

Bubble chart plotting weekly days used vs. weekly actions per user (capped at 7), with tool and department slicers for drill-down. Visualizes adoption intensity across organizational units.

*Screenshot coming soon*
*Click image to enlarge*

---

### 6. Department Breakdown

Department-level activity tables with per-AI-solution breakdowns, weekly trend filtering, and cross-department comparison metrics.

*Screenshot coming soon*
*Click image to enlarge*

---

### 7. Shadow AI Catalog (MDA)

Cloud Discovery shadow AI catalog with risk-scored domains, traffic volumes (upload/download), transaction counts, and sanction status. **Requires Microsoft Defender for Cloud Apps** — displays a yellow "MDA Required" callout when MDA data is not available.

*Screenshot coming soon*
*Click image to enlarge*

---

### 8. Benchmarks & Targets

Interactive what-if parameter sliders for Copilot adoption target, workforce AI adoption target, license utilization target, unmanaged AI threshold, and logins-without-CA threshold. Gap-to-target indicators, months-to-target projection, and scorecard status cards.

*Screenshot coming soon*
*Click image to enlarge*

---

### 9. Glossary & Data Dictionary

Consolidated reference page with plain-language definitions for every adoption, risk, and shadow AI metric, plus a data dictionary describing each source table and CSV. A static reference page that works on every license tier with no data dependency.

*Screenshot coming soon*
*Click image to enlarge*

---

### 10. Tier Comparison

Coverage matrix mapping each report page to its required license level (E3+Copilot → E5/MDE P2 → MDA). Self-service tier identification — which pages have data vs. empty visuals tells you exactly where your tenant stands.

*Screenshot coming soon*
*Click image to enlarge*

</details>

---

<details>
<summary><strong style="font-size:1.5em;">📨 Everything Your IT Admin Needs to Get Started</strong></summary>

<br>

Copy and send this pre-written email to your IT administrator or security team to request the access and permissions needed to populate the dashboard. It covers Microsoft Graph, Defender XDR, Purview, and (optionally) MDA portal access.

**Copy the request below into your preferred mail client.**

---

```
Subject: Access Request: AI Solutions Intelligence Dashboard Setup

Hi [IT Admin Name],

I'm setting up the AI Solutions Intelligence Dashboard to provide visibility
into AI usage across our Microsoft 365 tenant. I need the following access
to collect the required data:

1. Microsoft Graph API permissions:
   - User.Read.All, LicenseAssignment.Read.All, AuditLog.Read.All,
     ThreatHunting.Read.All

2. Microsoft Entra admin centre: Reports Reader + Security Reader role

3. Microsoft Purview portal: Audit Reader or eDiscovery Manager role

4. Microsoft Defender XDR: Security Reader (Advanced Hunting access)

5. Defender for Cloud Apps: Cloud App Security Reader when collecting
   CloudAppEvents, App Governance, or Cloud Discovery data

The dashboard uses read-only access to generate CSV exports.
No write permissions are required.

Setup instructions:
https://github.com/microsoft/AI-Solutions-Intelligence-Dashboard

Please let me know if you need additional details.

Thank you!
```

</details>

---

<details>
<summary><strong style="font-size:1.5em;">📋 Instructions</strong></summary>

<br>

### Step 1. Collect Your Data (CSVs)

The dashboard expects 13 CSV filenames. Populate each source available in your tenant and use an exact header-only stub for any unavailable source. Save all files in a single folder (for example, `C:\AI_Usage_Data\`).

#### Path A — Setup without MDA (M365 E3/E5 + MDE Plan 2)

Collect the available baseline CSVs using Microsoft Graph, Purview Audit, and Defender Advanced Hunting, then create header-only files for unavailable sources. `CloudAppEvents` requires Defender for Cloud Apps, so no-MDA tenants must also stub `ai_activity_sessions.csv`.

<details>
<summary><strong>Detailed step-by-step guide</strong></summary>

<br>

**Baseline CSVs to collect:**

| # | File | Source |
|---|---|---|
| 1 | `EntraUsers.csv` | Microsoft Graph (`Get-MgUser` with `-ExpandProperty manager`) |
| 2 | `ai_solutions_catalog.csv` | Manual — Excel → CSV with columns: `AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup` |
| 3 | `ai_copilot_usage_graph.csv` | Microsoft Purview Audit (`CopilotInteraction` records, pivoted via PowerShell) |
| 4 | `ai_copilot_surface_usage.csv` | Microsoft Purview Audit (`CopilotInteraction` records, normalized to one row per user/month/surface) |
| 5 | `ai_activity_sessions.csv` | Defender XDR Advanced Hunting (`CloudAppEvents`) |
| 6 | `ai_oauth_consents.csv` | Entra Audit Logs via Graph (`Get-MgAuditLogDirectoryAudit`) |
| 7 | `ai_sso_signins.csv` | Entra Sign-In Logs via Graph (`Get-MgAuditLogSignIn`) |
| 8 | `ai_file_proximity.csv` | Defender XDR Advanced Hunting (`DeviceFileEvents` joined with `DeviceNetworkEvents`) |
| 9 | `ai_offhours_geo.csv` | Defender XDR Advanced Hunting (`EntraIdSignInEvents`) |
| 10 | `ai_client_channel.csv` | Defender XDR Advanced Hunting (Browser / Desktop / API split from UserAgent) |

**Then create 3 MDA stub files** (header-only CSVs):

`ai_appgov_alerts.csv`:
```csv
Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description
```

`ai_cloud_discovery.csv`:
```csv
AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus
```

`ai_mda_sessions.csv`:
```csv
Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount
```
For populated rows, `PolicyHit` must be `TRUE` or `FALSE`, and `PolicyAction` must be `Allow`, `Warn`, or `Block`.

MDA-backed visuals remain empty when these files contain only headers. MDE, Entra, and Purview-backed visuals continue to refresh.

See [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) for the complete PowerShell scripts, KQL queries, and step-by-step export procedures for each CSV.

</details>

---

#### Path B — Setup with Full MDA (M365 E5 + MDE Plan 2 + MDA)

Collect all 10 baseline CSVs from Path A, then populate the 3 MDA CSVs with real data from App Governance alerts, Cloud Discovery exports, and Conditional Access App Control session logs.

<details>
<summary><strong>Detailed step-by-step guide</strong></summary>

<br>

Complete all 10 baseline CSVs from Path A, then populate these 3 additional files:

| # | File | Source |
|---|---|---|
| 11 | `ai_appgov_alerts.csv` | Defender XDR Advanced Hunting (`AppGovernanceAlert` table, filtered for AI apps) |
| 12 | `ai_cloud_discovery.csv` | MDA portal → Cloud Discovery → Discovered Apps → Filter `Category = Generative AI` → Export CSV → reshape with PowerShell |
| 13 | `ai_mda_sessions.csv` | Defender XDR Advanced Hunting (`CloudAppEvents` with Conditional Access App Control session policies) |

**Prerequisites for Path B:**

- Microsoft Defender for Cloud Apps service activated (sign in to https://security.microsoft.com with Global Admin)
- App Governance enabled and 24-hour ML baseline warmup completed
- Cloud Discovery log uploader configured (or MDE integration enabled for auto-discovery)
- Conditional Access App Control policies configured for your AI apps (e.g., ChatGPT Enterprise, Microsoft 365 Copilot)

See [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) for the complete KQL queries and export procedures.

</details>

---

### Step 2. Verify Prerequisites & Permissions

Ensure you have the required software, roles, and (optionally) Defender services enabled before collecting data.

<details>
<summary><strong>Detailed step-by-step guide</strong></summary>

<br>

#### Option A: Software Requirements

- [Power BI Desktop](https://www.microsoft.com/en-us/download/details.aspx?id=58494) (latest version)
- PowerShell 7+ with the [Microsoft.Graph](https://learn.microsoft.com/powershell/microsoftgraph/installation) and [ExchangeOnlineManagement](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2) modules
- One folder for all CSVs, e.g. `C:\AI_Usage_Data\` (Windows) or `~/AI_Usage_Data/` (macOS)

#### Option B: Roles & Portal Permissions

| Portal | Minimum Role | Used For |
|---|---|---|
| Microsoft Entra admin centre | Reports Reader + Security Reader | EntraUsers, Sign-Ins, Audit Logs |
| Microsoft Purview portal | Audit Reader / eDiscovery Manager | Copilot prompts (`CopilotInteraction`) |
| Microsoft Defender XDR | Security Reader | Advanced Hunting queries |
| Defender for Cloud Apps (MDA) | Cloud App Security Reader | App Governance, Cloud Discovery |
| Microsoft Graph | `User.Read.All`, `LicenseAssignment.Read.All`, `AuditLog.Read.All`, `ThreatHunting.Read.All` | Entra users and licenses, OAuth, sign-ins, Defender hunting |

---

#### Option C: Enable Microsoft Defender for Endpoint (MDE Plan 2)

Required for the Behavioral Risk and Shadow AI pages.

1. **Verify licence** — Microsoft 365 admin centre → Billing → Your products. Confirm you have M365 E5, or E3 + MDE Plan 2 add-on.
2. **Onboard devices** — Defender XDR portal → Settings → Endpoints → Onboarding. Use Intune (simplest), Group Policy, or local script.
3. **Verify Advanced Hunting tables** — run `DeviceFileEvents | take 1` and `DeviceNetworkEvents | take 1` in Defender XDR → Hunting. If "table not found", wait 24 hours after onboarding.

📚 [Microsoft docs: Onboard devices to Defender for Endpoint](https://learn.microsoft.com/defender-endpoint/onboarding)

</details>

---

### Step 3. Open the Report in Power BI Desktop and Set Parameters

<details>
<summary><strong>Detailed step-by-step guide</strong></summary>

<br>

1. Download [AI-Solutions-Intelligence-Dashboard V26 Validated.pbit](AI-Solutions-Intelligence-Dashboard%20V26%20Validated.pbit)
2. Double-click the file → Power BI Desktop opens
3. When prompted for **`AI_Data_Folder_Path`**, paste your folder path:
   - Windows: `C:\AI_Usage_Data`
   - macOS: `/Users/yourname/AI_Usage_Data`
4. Click **Load** → wait 1–3 minutes for refresh
5. **File → Save As** → save as `.pbix` with a descriptive name (e.g. `AI_Solutions_<TenantName>_<YYYY-MM-DD>.pbix`)

</details>

---

## Next Steps

<details>
<summary><strong>Validation & Troubleshooting</strong></summary>

| Check | Path A (No MDA) | Path B (Full MDA) |
|---|---|---|
| Identity and Copilot KPI cards populated | ✅ | ✅ |
| Dept Intensity bubble chart, X-axis 0–7 | Empty without `CloudAppEvents` | ✅ |
| Behavioral Risk per-user averages displayed | Partial: MDE + Entra signals | ✅ |
| Shadow AI page, unmanaged AI metrics | Empty without `CloudAppEvents` | ✅ |
| Shadow AI Catalog (MDA) | Yellow callout + empty visuals | Yellow callout + populated visuals |
| Benchmarks & Targets sliders | ✅ | ✅ |

| Symptom | Cause | Fix |
|---|---|---|
| "We couldn't find the file" on load | Folder path is incorrect or the expected CSV is missing | Confirm the folder and CSV filename shown in the error |
| Shadow AI Catalog (MDA) visuals blank but no yellow callout | Stub CSV missing | Create the header-only CSVs from Path A instructions |
| All Copilot prompt counts = 0 | Used Defender CloudAppEvents instead of Purview | Re-export both Copilot CSVs with `Collect-AICopilotUsage.ps1` |
| Weekly Days Used per User > 7 | Old PBIT version | Re-download the latest PBIT; the measure is hard-capped at 7 |
| "Behavioral Risk" page empty | Missing MDE Plan 2 export | Re-export `ai_file_proximity.csv` and `ai_offhours_geo.csv` |
| Calendar slicer day-grain doesn't filter | Expected — fact tables are at month grain | Use Year / Quarter / Month slicer instead |
| `AppGovernanceAlert` table not found | App Governance not enabled | Enable App Governance in Defender XDR → Settings → Cloud Apps |
| Cloud Discovery page empty with MDA | Log uploader not configured | Configure Cloud Discovery via MDE integration or log uploader |

</details>

<details>
<summary><strong>Publish / Distribute</strong></summary>

1. Publish the `.pbix` to Power BI Service via **Home → Publish**
2. Configure scheduled refresh against OneDrive / SharePoint hosting the CSVs
3. Share the workspace or create an app for stakeholders
4. Consider row-level security if department-scoped access is needed

</details>

<details>
<summary><strong>Interpretation & Action Planning</strong></summary>

- **Low adoption + high license count** → Focus enablement efforts; consider targeted training by department
- **High shadow AI usage** → Review the solutions catalog; consider sanctioning popular tools or tightening controls
- **Elevated behavioral risk scores** → Investigate file-proximity patterns and off-hours sessions; engage security team
- **OAuth permission weight spikes** → Review consent grants in Entra; consider admin consent workflow

</details>

<details>
<summary><strong>Monitor with Automatic Refresh</strong></summary>

1. Re-run the data collection queries on your preferred cadence (weekly is typical)
2. Overwrite the CSVs in your data folder with the new exports
3. In Power BI Desktop: **Home → Refresh** → Save
4. (Or publish to Power BI Service and configure scheduled refresh against OneDrive / SharePoint hosting the CSVs)

When upgrading from No-MDA to Full MDA later: overwrite the 3 stub CSVs with real exports, refresh the report — MDA pages light up automatically. **No PBIT change needed.**

</details>

</details>

---

<details>
<summary><strong style="font-size:1.5em;">🤓 Nerd Corner</strong></summary>

<br>

**Architecture:** The v26 Unified PBIT replaces two parallel reports (`v22_E5_NoMDA_v2` and `v22_E5V3`) with a single template that gracefully handles whatever tier the customer owns. MDA-specific pages are clearly suffixed `(MDA)` and display a friendly yellow overlay when the underlying data is empty. No conditional DAX logic is needed — empty CSVs simply produce empty visuals.

**Tier model:** The report contains 10 pages total. Executive Summary, Copilot Deep Dive, Benchmarks & Targets, and the reference pages use Graph/Purview or static data. Behavioral Risk uses MDE and Entra signals. Activity, Shadow AI, department-intensity, and department-breakdown visuals depend on `CloudAppEvents` from Defender for Cloud Apps. Shadow AI Catalog (MDA) uses Cloud Discovery.

**Measures:** 123 total measures across 7 tables, including 5 interactive what-if parameter sliders, executive narrative verdicts, risk funnels, department-level scatter quadrant analysis, and the dynamic Copilot-surface measure.

**Empty-CSV fallback:** Rather than `try ... otherwise` in M (which can mask real refresh errors), customers create header-only stub CSVs. When MDA is later deployed, simply overwrite the stubs with real exports — same PBIT, no changes needed.

**Generator pipeline:**
```powershell
python .\generate_pbit_v26_unified.py
Get-FileHash '.\AI-Solutions-Intelligence-Dashboard V26 Validated.pbit' -Algorithm SHA256
```

The deterministic transformer:

```
generate_pbit_v26_unified.py
  ├─ Reads AI-Solutions-Intelligence-Dashboard V26.pbit without modifying it
  ├─ Patches DataModelSchema and synchronized UnappliedChanges metadata
  ├─ Removes stale report-formatting selectors
  ├─ Removes user-specific security bindings and MSIP sensitivity-label metadata
  ├─ Preserves all remaining package entries and ZIP metadata
  └─ Outputs AI-Solutions-Intelligence-Dashboard V26 Validated.pbit
```

**CSV count:** 13 total. `ai_copilot_surface_usage.csv` adds a normalized, future-compatible Copilot surface fact; the three MDA CSVs are `ai_appgov_alerts.csv`, `ai_cloud_discovery.csv`, and `ai_mda_sessions.csv`.

</details>

---

<details>
<summary><strong style="font-size:1.5em;">💬 Feedback</strong></summary>

<br>

Managed and released by the Microsoft Copilot Growth ROI Advisory Team. Please reach out to [copilot-roi-advisory-team-gh@microsoft.com](mailto:copilot-roi-advisory-team-gh@microsoft.com) with any feedback.

</details>

---

<details>
<summary><strong style="font-size:1.5em;">🔔 Stay Updated</strong></summary>

<br>

- ⭐ **Star this repository** to receive notifications about new template versions
- 👀 **Watch** for updates and announcements
- 🔄 Check back regularly for new features and improvements

</details>

---
