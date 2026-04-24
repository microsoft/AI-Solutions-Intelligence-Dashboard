# AI Solutions Intelligence Dashboard

<div align="center">

![Current Version](https://img.shields.io/badge/version-v26%20Unified-blue)

**A single Power BI report that delivers a complete, defensible view of AI usage across your Microsoft 365 tenant — Copilot adoption, shadow AI, OAuth risk, off-hours/geo anomalies, and (optionally) MDA App Governance & Cloud Discovery — all in one PBIT.**

### 📥 [Click Here to Download All Files](https://github.com/microsoft/AI-Solutions-Intelligence-Dashboard/archive/refs/heads/main.zip)

**Related Templates & Tools:**

[![v26 Unified PBIT](https://img.shields.io/badge/Report-v26%20Unified%20PBIT-003087)](AI_Usage_v26_Unified.pbit)
[![Architecture Blueprint](https://img.shields.io/badge/Report-Architecture%20Blueprint-teal)](AI_Usage_v26_Blueprint.md)
[![Setup Instructions](https://img.shields.io/badge/Report-Setup%20Instructions-purple)](INSTRUCTIONS_v26.md)
[![Sample Data Generator](https://img.shields.io/badge/Report-Sample%20Data%20Generator-orange)](build_v26_sample_data.py)
[![PBIT Generator](https://img.shields.io/badge/Tool-PBIT%20Generator-red)](generate_pbit_v26_unified.py)

**Additional Resources:**
[Defender for Endpoint docs](https://learn.microsoft.com/defender-endpoint/) · [Defender for Cloud Apps docs](https://learn.microsoft.com/defender-cloud-apps/) · [Microsoft Purview Audit docs](https://learn.microsoft.com/purview/audit-solutions-overview) · [Microsoft Graph Reports API](https://learn.microsoft.com/graph/api/resources/report)

⭐ **Star this repository** to receive notifications about new template versions
👀 **Watch** for updates and announcements

</div>

---

<details open>
<summary><strong>📊 Why Use This Report & Insights You Can Explore</strong></summary>

<br>

This dashboard replaces fragmented, surface-level AI adoption reports with a single, unified view that spans Copilot usage, shadow AI detection, OAuth risk scoring, behavioral anomalies, and (optionally) Microsoft Defender for Cloud Apps signals — all from one Power BI template. Whether your tenant runs M365 E3 + Copilot or the full E5 + MDA stack, the same PBIT adapts automatically to whatever data you provide.

**Executive Overview:**
Track total AI users, adoption rate, license utilization, top tools, and monthly trends at a glance. Identify the gap between licensed capacity and actual usage with KPI cards that surface workforce adoption, per-surface Copilot prompt counts (Teams, Word, Excel, Outlook, PowerPoint, Chat), and department-level activity breakdowns.

**AI Adoption Strategy:**
Detect shadow AI usage across unsanctioned tools, assess behavioral risk through file-proximity analysis and off-hours/geo anomalies, and review OAuth consent patterns with permission-weighted risk scores. Pages are tiered by license — E3+Copilot pages work out of the box, MDE Plan 2 pages light up with endpoint data, and MDA pages activate when Defender for Cloud Apps is deployed.

**Solution Priority:**
Prioritize AI tool governance with the solutions catalog (Sanctioned / Conditional / Unsanctioned tiers), benchmark adoption against configurable targets, and use the tier comparison matrix to understand exactly which pages and signals map to your current license level.

**AI Solutions Usage Activity & Trends:**
Drill into per-user activity across all signals, visualize department intensity with bubble charts (weekly days vs. weekly actions per user, capped at 7), and break down AI client channels (Browser / Desktop / API) by AI site. Optional MDA pages provide OAuth anomaly alerts, cloud discovery shadow AI catalogs with risk scores, and per-session DLP/policy enforcement intelligence.

</details>

---

<details>
<summary><strong style="font-size:1.5em;">🖥️ Report Pages Overview</strong></summary>

<br>

The dashboard includes **18** interactive report pages. A detailed analysis guide will be available separately.

---

### 1. AI Solutions Executive Summary

KPI cards showing total AI users, adoption rate, top tools, and monthly trends. Includes workforce adoption donut, license utilization gauge, gap-to-target indicators, and an executive dashboard with 6 headline metrics. Works on E3 + Copilot baseline tier.

*Screenshot coming soon*
*Click image to enlarge*

---

### 2. AI Solutions Usage Trends

Per-surface Copilot prompt breakdowns (Teams / Word / Excel / Outlook / PowerPoint / Chat) sourced from Purview Audit `CopilotInteraction` records, department intensity bubble charts (weekly days vs. weekly actions per user), and department-level activity tables with weekly trend filtering. Combines data from Purview Audit, Defender CloudAppEvents, and Entra user profiles.

*Screenshot coming soon*
*Click image to enlarge*

---

### 3. AI License Recommendations

Adoption-vs-target gap analysis, threshold cards for configurable benchmarks, and license utilization metrics comparing Copilot-licensed users against active usage. Helps identify underutilized licenses and expansion opportunities across the tenant.

*Screenshot coming soon*
*Click image to enlarge*

---

### 4. AI Enablement Strategy

Shadow AI detection showing unsanctioned/unmanaged AI usage, behavioral risk scoring with file-proximity analysis (files accessed within 5 minutes of AI site visits), off-hours session percentages, and geo anomaly counts. OAuth consent patterns with permission-weighted risk scores. Requires MDE Plan 2 for full population.

*Screenshot coming soon*
*Click image to enlarge*

---

### 5. AI Enablement Strategy Tiers

Tier comparison coverage matrix mapping each report page to its required license level (E3+Copilot → E5/MDE P2 → MDA). Data Source Health page showing row counts and refresh status per CSV. Self-service tier identification — which pages have data vs. empty visuals tells you exactly where your tenant stands.

*Screenshot coming soon*
*Click image to enlarge*

---

### 6. AI Solutions Usage Activity

Per-user drilldown across all signals, AI client channel breakdown (Browser / Desktop / API stacked bar per AI site), and the three optional MDA-powered pages: OAuth Anomaly Alerts with ML-driven alert tables, Cloud Discovery shadow AI catalog with risk-scored domains and traffic volumes, and MDA Session Intelligence showing per-session DLP/policy enforcement actions (file uploads, sensitive paste, downloads).

*Screenshot coming soon*
*Click image to enlarge*

---

### 7. Glossary & Metric Definitions

Three dedicated glossary pages providing plain-language definitions for adoption metrics, risk metrics, and shadow AI terminology. Static reference pages that work on every license tier with no data dependency.

*Screenshot coming soon*
*Click image to enlarge*

</details>

---

<details>
<summary><strong style="font-size:1.5em;">📨 Everything Your IT Admin Needs to Get Started</strong></summary>

<br>

Copy and send this pre-written email to your IT administrator or security team to request the access and permissions needed to populate the dashboard. It covers Microsoft Graph, Defender XDR, Purview, and (optionally) MDA portal access.

**[📧 Open as Outlook Draft →](mailto:?subject=Access%20Request%3A%20AI%20Solutions%20Intelligence%20Dashboard%20Setup&body=Hi%20%5BIT%20Admin%20Name%5D%2C%0A%0AI%27m%20setting%20up%20the%20AI%20Solutions%20Intelligence%20Dashboard%20to%20provide%20visibility%20into%20AI%20usage%20across%20our%20Microsoft%20365%20tenant.%20I%20need%20the%20following%20access%20to%20collect%20the%20required%20data%3A%0A%0A1.%20Microsoft%20Graph%20API%20permissions%3A%20User.Read.All%2C%20Directory.Read.All%2C%20Reports.Read.All%2C%20AuditLog.Read.All%2C%20Application.Read.All%0A2.%20Microsoft%20Entra%20admin%20centre%3A%20Reports%20Reader%20%2B%20Security%20Reader%20role%0A3.%20Microsoft%20Purview%20portal%3A%20Audit%20Reader%20or%20eDiscovery%20Manager%20role%0A4.%20Microsoft%20Defender%20XDR%3A%20Security%20Reader%20(Advanced%20Hunting%20access)%0A5.%20(Optional)%20Defender%20for%20Cloud%20Apps%3A%20Cloud%20App%20Security%20Reader%0A%0AThe%20dashboard%20uses%20read-only%20access%20to%20generate%20CSV%20exports.%20No%20write%20permissions%20are%20required.%0A%0ASetup%20instructions%3A%20https%3A%2F%2Fgithub.com%2Fmicrosoft%2FAI-Solutions-Intelligence-Dashboard%0A%0APlease%20let%20me%20know%20if%20you%20need%20additional%20details.%0A%0AThank%20you!)**

---

```
Subject: Access Request: AI Solutions Intelligence Dashboard Setup

Hi [IT Admin Name],

I'm setting up the AI Solutions Intelligence Dashboard to provide visibility
into AI usage across our Microsoft 365 tenant. I need the following access
to collect the required data:

1. Microsoft Graph API permissions:
   - User.Read.All, Directory.Read.All, Reports.Read.All,
     AuditLog.Read.All, Application.Read.All

2. Microsoft Entra admin centre: Reports Reader + Security Reader role

3. Microsoft Purview portal: Audit Reader or eDiscovery Manager role

4. Microsoft Defender XDR: Security Reader (Advanced Hunting access)

5. (Optional) Defender for Cloud Apps: Cloud App Security Reader

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

The dashboard is powered by 13 CSV files. Depending on your tenant's license tier, you'll populate 10 baseline CSVs and either stub or populate 3 MDA-specific CSVs. Save all files in a single folder (e.g., `C:\AI_Usage_Data\` on Windows or `~/AI_Usage_Data/` on macOS).

#### Method 1: Path A — Setup without MDA (M365 E3/E5 + MDE Plan 2)

Collect the 10 baseline CSVs using Microsoft Graph PowerShell, Purview Audit exports, and Defender Advanced Hunting KQL queries, then create 3 header-only MDA stub files so Power Query loads cleanly. Estimated time: 30–45 minutes.

<details>
<summary><strong>Detailed step-by-step guide</strong></summary>

<br>

**Baseline CSVs to collect:**

| # | File | Source |
|---|---|---|
| 1 | `EntraUsers.csv` | Microsoft Graph (`Get-MgUser` with `-ExpandProperty manager`) |
| 2 | `ai_solutions_catalog.csv` | Manual — Excel → CSV with columns: `AISolution,Category,Vendor,RiskTier,DefaultDataHandling` |
| 3 | `ai_copilot_prompts.csv` | Microsoft Purview Audit (`CopilotInteraction` records, flattened via PowerShell) |
| 4 | `ai_activity_sessions.csv` | Defender XDR Advanced Hunting (`CloudAppEvents`) |
| 5 | `ai_oauth_consents.csv` | Entra Audit Logs via Graph (`Get-MgAuditLogDirectoryAudit`) |
| 6 | `ai_sso_signins.csv` | Entra Sign-In Logs via Graph (`Get-MgAuditLogSignIn`) |
| 7 | `ai_file_proximity.csv` | Defender XDR Advanced Hunting (`DeviceFileEvents` joined with `DeviceNetworkEvents`) |
| 8 | `ai_offhours_geo.csv` | Defender XDR Advanced Hunting (`AADSignInEventsBeta`) |
| 9 | `ai_copilot_usage_graph.csv` | Microsoft Graph Reports API — `getMicrosoft365CopilotUsageUserDetail(period='D90')` (optional but recommended) |
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

The three MDA pages will display a yellow "MDA Required" callout and empty visuals. Everything else works normally.

See [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) for the complete PowerShell scripts, KQL queries, and step-by-step export procedures for each CSV.

</details>

---

#### Method 2: Path B — Setup with Full MDA (M365 E5 + MDE Plan 2 + MDA)

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
| Microsoft Graph | `User.Read.All`, `Directory.Read.All`, `Reports.Read.All`, `AuditLog.Read.All`, `Application.Read.All` | EntraUsers, Copilot snapshot, OAuth, Sign-Ins |

---

#### Option C: Enable Microsoft Defender for Endpoint (MDE Plan 2)

Required for pages 4 (Shadow AI), 7 (Behavioral Risk), 8 (User Drilldown), and 11 (AI Client Channel).

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

1. Download [AI_Usage_v26_Unified.pbit](AI_Usage_v26_Unified.pbit)
2. Double-click the file → Power BI Desktop opens
3. When prompted for **`AI_Data_Folder_Path`**, paste your folder path **with a trailing slash**:
   - Windows: `C:\AI_Usage_Data\`
   - macOS: `/Users/yourname/AI_Usage_Data/`
4. Click **Load** → wait 1–3 minutes for refresh
5. **File → Save As** → save as `.pbix` with a descriptive name (e.g. `AI_Usage_v26_<TenantName>_<YYYY-MM-DD>.pbix`)

</details>

---

## Next Steps

<details>
<summary><strong>Validation & Troubleshooting</strong></summary>

| Check | Path A (No MDA) | Path B (Full MDA) |
|---|---|---|
| Page 1 KPI cards populated | ✅ | ✅ |
| Page 5 bubble chart, X-axis 0–7 | ✅ | ✅ |
| Page 7 per-user averages displayed | ✅ | ✅ |
| Page 11 stacked bar by AI site | ✅ | ✅ |
| Pages 12–14 MDA callout + visuals | Yellow callout + empty visuals | Yellow callout + populated visuals |

| Symptom | Cause | Fix |
|---|---|---|
| "We couldn't find the file" on load | Folder path missing trailing slash | Add trailing `\` (Windows) or `/` (macOS) |
| Pages 12/13/14 visuals blank but no yellow callout | Stub CSV missing | Create the header-only CSVs from Path A instructions |
| All Copilot prompt counts = 0 | Used Defender CloudAppEvents instead of Purview | Re-export `ai_copilot_prompts.csv` from Purview Audit |
| Weekly Days Used per User > 7 | Old PBIT version | Re-download v26; the measure is hard-capped at 7 |
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

When upgrading from No-MDA to Full MDA later: overwrite the 3 stub CSVs with real exports, refresh the report — pages 12, 13, 14 light up automatically. **No PBIT change needed.**

</details>

</details>

---

<details>
<summary><strong style="font-size:1.5em;">🤓 Nerd Corner</strong></summary>

<br>

**Architecture:** The v26 Unified PBIT replaces two parallel reports (`v22_E5_NoMDA_v2` and `v22_E5V3`) with a single template that gracefully handles whatever tier the customer owns. MDA-specific pages are clearly suffixed `(MDA)` and display a friendly yellow overlay when the underlying data is empty. No conditional DAX logic is needed — empty CSVs simply produce empty visuals.

**Tier model:** Only 3 net-new pages truly require MDA. The other 15 work on E5 + MDE Plan 2 alone — which is what most enterprise customers already own. Pages 1–3, 5, 6, 9, 10 work on E3+Copilot baseline. Pages 4, 7, 8, 11 need MDE Plan 2. Pages 12–14 need MDA.

**Empty-CSV fallback:** Rather than `try ... otherwise` in M (which can mask real refresh errors), customers create header-only stub CSVs. When MDA is later deployed, simply overwrite the stubs with real exports — same PBIT, no changes needed.

**Generator pipeline:**
```
generate_pbit_v26_unified.py
  ├─ Imports and extends the v22 NoMDA v2 generator
  ├─ Adds 3 new tables: AI_AppGovAlerts, AI_CloudDiscovery, AI_MDA_Sessions
  ├─ Defines 3 new MDA page builders + mda_callout helper
  ├─ Patches page list: renames, appends MDA pages, rewrites Tier Comparison
  └─ Outputs AI_Usage_v26_Unified.pbit
```

**CSV count:** 13 total (was 9 in v22 NoMDA). The 3 new MDA CSVs are `ai_appgov_alerts.csv`, `ai_cloud_discovery.csv`, and `ai_mda_sessions.csv`.

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
