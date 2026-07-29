# AI Usage Dashboard v26 — Unified Edition Blueprint

> **⚠️ Historical design document.** This blueprint captures the original design and planning rationale (a draft 16–18 page layout and the `v21`/`v22` generator lineage). The **shipped template** is `AI-Solutions-Intelligence-Dashboard V26.pbit` with **10 pages**: Executive Summary, Copilot Deep Dive, Behavioral Risk, Shadow AI, Dept Intensity by Solution, Department Breakdown, Shadow AI Catalog (MDA), Benchmarks & Targets, Glossary & Data Dictionary, Tier Comparison. See `README.md` → *Report Pages Overview* for the current layout. The page-tier table below is retained for design history only.

**Goal:** Replace the two parallel reports (`v22_E5_NoMDA_v2` and `v22_E5V3`) with a **single PBIT** that gracefully handles whatever tier the customer owns. MDA-specific pages are clearly suffixed `(MDA)` and display a friendly overlay when the underlying data is empty.

**Output file:** `AI_Usage_v26_Unified.pbit`

---

## 1. Tier model (what data source maps to what license)

| License/Component | Tables it unlocks | Pages it powers |
|---|---|---|
| **M365 E3 + Copilot** (baseline) | `EntraUsers`, `AI_CopilotUsage` (Graph), `AI_OAuthConsents` (Entra), `AI_SSO_SignIns` (Entra), `AI_Solutions` (manual) | Exec Summary, Copilot Deep Dive, Benchmarks, Glossaries |
| **+ Purview Audit** (E3 retains 180 d, E5 retains 365 d) | `AI_Activity` from `CopilotInteraction` records | Powers per-surface Copilot prompt counts (replaces Graph last-activity) |
| **+ MDE Plan 2** (or E5) | `AI_FileProximity` (DeviceFileEvents), `AI_OffHoursGeo` (AADSignInEventsBeta), `AI_ClientChannel` (CloudAppEvents.UserAgent) | Behavioral Risk, Shadow AI, AI Client Channel, Dept Intensity |
| **+ MDA App Governance** (premium) | `AI_AppGovAlerts` | OAuth Anomaly Alerts (MDA) |
| **+ MDA Cloud Discovery** (log uploader) | `AI_CloudDiscovery` | Cloud Discovery Catalog (MDA) |
| **+ MDA-connected apps** (CASB) | `AI_MDA_Sessions` (CloudAppEvents enriched + CASSessionEvents) | MDA Session Intelligence (MDA) |

Key insight: **only 3 net-new pages truly require MDA**. The other 10 work on E5 + MDE P2 alone — which is what most enterprise customers already own.

---

## 2. Page-by-page dependency analysis

Legend: ✅ works on baseline · ⚙️ needs MDE P2 · 🛡️ needs MDA

| # | Page | Visuals | Data tables touched | Requires |
|---|---|---|---|---|
| 1 | Executive Dashboard | 6 KPI cards, adoption rate, trend, donut, tool-count chart | EntraUsers, AI_Activity, AI_CopilotUsage, AI_Solutions, Calendar | ✅ |
| 2 | Executive Summary | KPIs, adoption %, top tools, license gap | Same as above | ✅ |
| 3 | Copilot Deep Dive | Per-surface prompts, Teams/Word/Excel/Outlook/PPT, license utilization | AI_CopilotUsage, EntraUsers | ✅ |
| 4 | Shadow AI | Unmanaged AI users, Non-Microsoft activity, % using unmanaged | AI_Activity, AI_Solutions | ⚙️ partial — fully populated only with MDE P2 (DeviceNetworkEvents detects unsanctioned domains) |
| 5 | Dept Intensity by Solution | Bubble chart (weekly days vs weekly actions, capped at 7), tool slicer, dept ranking | AI_Activity, EntraUsers, AI_Solutions, Calendar | ✅ |
| 6 | Department Breakdown | Dept × activity table, weekly action trend by AI site (filtered by dept) | Same as #5 | ✅ |
| 7 | Behavioral Risk | Per-user-avg KPIs (activity, OAuth weight, risk score), file-proximity table, anomaly explanation, calc note | AI_Activity, AI_OAuthConsents, AI_FileProximity, AI_OffHoursGeo | ⚙️ FileProximity + OffHoursGeo come from MDE P2 / AADSignInEventsBeta (NOT MDA). Page name will not have MDA suffix. |
| 8 | AI Client Channel | Stacked bar Browser/Desktop/API per AISite | AI_ClientChannel (CloudAppEvents.UserAgent) | ⚙️ |
| 9 | User Drilldown | Per-user table with all signals | All UPN-keyed tables | ✅ partial / ⚙️ full |
| 10 | Benchmarks & Targets | Adoption-vs-target gaps, threshold cards | AI Measures (constants) | ✅ |
| **11** | **OAuth Anomaly Alerts (MDA)** | Alert table, severity breakdown, top apps, alert trend | **AI_AppGovAlerts** | 🛡️ |
| **12** | **Cloud Discovery — Shadow AI Catalog (MDA)** | Discovered AI domains, risk-score table, traffic volume per domain | **AI_CloudDiscovery** | 🛡️ |
| **13** | **MDA Session Intelligence (MDA)** | Per-session activities (file uploads blocked, sensitive paste, downloads), session policy hits | **AI_MDA_Sessions** | 🛡️ |
| 14 | Tier Comparison | Coverage matrix across E3 / +MDE / +MDA / E5 | static | ✅ (rewrite for unified) |
| 15 | Data Source Health | Row counts, last-refresh per CSV | All tables | ✅ |
| 16–18 | Glossaries (Adoption / Risk / Shadow AI) | static | static | ✅ |

### Decision: rename the existing "Behavioral Risk MDA" page

The user's PBIX renamed page 7 to "Behavioral Risk MDA", but the page **doesn't actually need MDA** — it uses MDE P2 (DeviceFileEvents) + Entra Audit Logs + AADSignInEventsBeta. Renaming it back to **"Behavioral Risk"** in the unified report. The new MDA pages get the `(MDA)` suffix.

---

## 3. "MDA Required" overlay specification

Every page suffixed `(MDA)` gets a top-of-page yellow callout (~80 px tall):

```
┌─────────────────────────────────────────────────────────────────┐
│ 🛡️  Microsoft Defender for Cloud Apps required                  │
│ This page reads from <table_name> sourced from <kql_table>.     │
│ If MDA is not deployed in your tenant, the visuals below will   │
│ render with whatever data is present (typically empty). To      │
│ enable, see INSTRUCTIONS_v26.md → Section "Enabling MDA Pages". │
│                                                                 │
│ Quick KQL preview:                                              │
│   <one-liner KQL>                                               │
└─────────────────────────────────────────────────────────────────┘
```

The visuals beneath render normally — empty if no data, populated if data is present. No conditional logic needed in DAX.

---

## 4. Empty-CSV fallback strategy

To avoid Power Query errors when MDA CSVs are missing, the customer creates **header-only stub CSVs** (just the column row, no data). Example for `ai_appgov_alerts.csv`:

```csv
Timestamp,UPN,AppName,AlertType,Severity,Description
```

The instructions document provides the exact stub content for each MDA CSV. Customers who later enable MDA simply overwrite the stub with the real export. **Reasoning:** simpler than `try ... otherwise` in M (which can mask real refresh errors).

---

## 5. New CSVs introduced in v26 (beyond what NoMDA v2 already had)

| CSV | KQL Section | Required for | Stub OK if missing |
|---|---|---|---|
| `ai_appgov_alerts.csv` | B6 | OAuth Anomaly Alerts (MDA) | yes |
| `ai_cloud_discovery.csv` | B7 | Cloud Discovery Catalog (MDA) | yes |
| `ai_mda_sessions.csv` | B8 | MDA Session Intelligence (MDA) | yes |

Total CSV count in v26 = **12** (was 9 in v2 NoMDA). The 3 new MDA CSVs are `ai_appgov_alerts.csv`, `ai_cloud_discovery.csv`, and `ai_mda_sessions.csv`. Note: `ai_copilot_usage_graph.csv` can be sourced from either Purview Audit (recommended) or the Graph Reports API.

---

## 6. Tier Comparison page rewrite

Replace the "you are here" highlight with a **legend that maps to page numbers**:

```
PAGES 1, 2, 3, 5, 6, 9, 10  →  Work on E3 + Copilot
PAGES 4, 7, 8               →  Need E5 or MDE Plan 2
PAGES 11, 12, 13            →  Need MDA (these are clearly labeled "(MDA)")
```

Customer's "tier" is now self-evident: which pages have data vs empty visuals.

---

## 7. Calendar table

Already extended in v2 NoMDA to daily grain with Year/Quarter/Month/Day hierarchy. **Carries over unchanged.**

---

## 8. Generator architecture

```
generate_pbit_v26_unified.py
  │
  ├─ imports generate_pbit_v22_E5_NoMDA_v2.py  (which imports v21)
  │       → reuses build_model_v2(), all rebuilt pages, all measures
  │
  ├─ extends model with 3 new tables:
  │       AI_AppGovAlerts, AI_CloudDiscovery, AI_MDA_Sessions
  │
  ├─ defines 3 new page builders + 1 helper (mda_callout)
  │
  ├─ patches PAGES list:
  │       - rename "Behavioral Risk MDA" → "Behavioral Risk"
  │       - append: OAuth Anomaly Alerts (MDA)
  │                 Cloud Discovery — Shadow AI Catalog (MDA)
  │                 MDA Session Intelligence (MDA)
  │       - rewrite: Tier Comparison (unified version)
  │
  └─ outputs AI_Usage_v26_Unified.pbit
```

Old v22 generators stay in repo but are flagged DEPRECATED.

---

## 9. Acceptance criteria

A v26 build is "done" when:

- [ ] PBIT opens cleanly when only the 9 baseline CSVs are present (3 MDA stubs OK)
- [ ] All 10 baseline pages render data
- [ ] All 3 MDA pages render their yellow overlay + visuals (visuals empty)
- [ ] When real MDA CSVs are dropped in, the same PBIT lights up the visuals on next refresh — no PBIT change needed
- [ ] `INSTRUCTIONS_v26.md` covers both paths (MDA / No-MDA) end-to-end
- [ ] Old `v22_E5*` PBITs marked DEPRECATED in their script comments
