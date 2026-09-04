# AI Usage Dashboard v26 — Unified Edition Blueprint

> **⚠️ Historical design document.** This blueprint captures the original design and planning rationale (a draft 16–18 page layout and the `v21`/`v22` generator lineage). The **shipped template** is `AI-Solutions-Intelligence-Dashboard V26 Validated.pbit` with **10 pages**: Executive Summary, Copilot Deep Dive, Behavioral Risk, Shadow AI, Dept Intensity by Solution, Department Breakdown, Shadow AI Catalog (MDA), Benchmarks & Targets, Glossary & Data Dictionary, Tier Comparison. See `README.md` → *Report Pages Overview* for the current layout. The page-tier table below is retained for design history only.

**Goal:** Replace the two parallel reports (`v22_E5_NoMDA_v2` and `v22_E5V3`) with a **single PBIT** that gracefully handles whatever tier the customer owns. MDA-specific pages are clearly suffixed `(MDA)` and display a friendly overlay when the underlying data is empty.

**Output file:** `AI-Solutions-Intelligence-Dashboard V26 Validated.pbit`

---

## 1. Tier model (what data source maps to what license)

| License/Component | Tables it unlocks | Pages it powers |
|---|---|---|
| **M365 E3 + Copilot** (baseline) | `EntraUsers`, `AI_OAuthConsents`, `AI_SSO_SignIns`, `AI_Solutions` | Identity, consent, sign-in, benchmarks, and reference visuals |
| **+ Purview Audit** | `AI_CopilotUsage` and normalized `AI_CopilotSurfaceUsage` from `CopilotInteraction` records | Dynamic per-surface Copilot prompt counts; retention depends on licensing and audit policy |
| **+ MDE Plan 2** (or E5) | `AI_FileProximity` (DeviceFileEvents + DeviceNetworkEvents), `AI_ClientChannel` (DeviceNetworkEvents) | File-proximity and client-channel signals |
| **+ Entra data in Defender XDR** | `AI_OffHoursGeo` (`EntraIdSignInEvents`) | Off-hours and geographic anomaly signals |
| **+ Defender for Cloud Apps** | `AI_Activity` (`CloudAppEvents`) | Activity, Shadow AI, and department activity visuals |
| **+ MDA App Governance** (premium) | `AI_AppGovAlerts` | OAuth Anomaly Alerts (MDA) |
| **+ MDA Cloud Discovery** (log uploader) | `AI_CloudDiscovery` | Cloud Discovery Catalog (MDA) |
| **+ MDA-connected apps** (CASB) | `AI_MDA_Sessions` (CloudAppEvents enriched + CASSessionEvents) | MDA Session Intelligence (MDA) |

The report loads with header-only files, but each visual only populates when its listed source is licensed, connected, and retained.

---

## 2. Page-by-page dependency analysis

Legend: ✅ works on baseline · ⚙️ needs MDE P2 · 🛡️ needs MDA

| # | Page | Visuals | Data tables touched | Requires |
|---|---|---|---|---|
| 1 | Executive Dashboard | 6 KPI cards, adoption rate, trend, donut, tool-count chart | EntraUsers, AI_Activity, AI_CopilotUsage, AI_Solutions, Calendar | ✅ |
| 2 | Executive Summary | KPIs, adoption %, top tools, license gap | Same as above | ✅ |
| 3 | Copilot Deep Dive | Dynamic per-surface prompts for all Purview-observed workloads, license utilization | AI_CopilotUsage, AI_CopilotSurfaceUsage, EntraUsers | ✅ |
| 4 | Shadow AI | Unmanaged AI users, Non-Microsoft activity, % using unmanaged | AI_Activity, AI_Solutions | ⚙️ MDA required — populated from `CloudAppEvents`; MDE-only file-proximity and client-channel data do not populate this page. |
| 5 | Dept Intensity by Solution | Bubble chart (weekly days vs weekly actions, capped at 7), tool slicer, dept ranking | AI_Activity, EntraUsers, AI_Solutions, Calendar | ✅ |
| 6 | Department Breakdown | Dept × activity table, weekly action trend by AI site (filtered by dept) | Same as #5 | ✅ |
| 7 | Behavioral Risk | Per-user-avg KPIs (activity, OAuth weight, risk score), file-proximity table, anomaly explanation, calc note | AI_Activity, AI_OAuthConsents, AI_FileProximity, AI_OffHoursGeo | ⚙️ MDE provides file proximity; `EntraIdSignInEvents` provides off-hours/geo; MDA provides activity. |
| 8 | AI Client Channel | Stacked bar Browser/Desktop/API per AISite | AI_ClientChannel (DeviceNetworkEvents process data) | ⚙️ |
| 9 | User Drilldown | Per-user table with all signals | All UPN-keyed tables | ✅ partial / ⚙️ full |
| 10 | Benchmarks & Targets | Adoption-vs-target gaps, threshold cards | AI Measures (constants) | ✅ |
| **11** | **OAuth Anomaly Alerts (MDA)** | Alert table, severity breakdown, top apps, alert trend | **AI_AppGovAlerts** | 🛡️ |
| **12** | **Cloud Discovery — Shadow AI Catalog (MDA)** | Discovered AI domains, risk-score table, traffic volume per domain | **AI_CloudDiscovery** | 🛡️ |
| **13** | **MDA Session Intelligence (MDA)** | Per-session activities (file uploads blocked, sensitive paste, downloads), session policy hits | **AI_MDA_Sessions** | 🛡️ |
| 14 | Tier Comparison | Coverage matrix across E3 / +MDE / +MDA / E5 | static | ✅ (rewrite for unified) |
| 15 | Data Source Health | Row counts, last-refresh per CSV | All tables | ✅ |
| 16–18 | Glossaries (Adoption / Risk / Shadow AI) | static | static | ✅ |

### Decision: rename the existing "Behavioral Risk MDA" page

The user's PBIX renamed page 7 to "Behavioral Risk MDA". The shipped page is **"Behavioral Risk"** because its signals span MDE, Entra, Graph audit, and optional MDA activity rather than one product.

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
Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description
```

The instructions document provides the exact stub content for each MDA CSV. Customers who later enable MDA simply overwrite the stub with the real export. **Reasoning:** simpler than `try ... otherwise` in M (which can mask real refresh errors).

---

## 5. New CSVs introduced in v26 (beyond what NoMDA v2 already had)

| CSV | KQL Section | Required for | Stub OK if missing |
|---|---|---|---|
| `ai_appgov_alerts.csv` | B6 | OAuth Anomaly Alerts (MDA) | yes |
| `ai_cloud_discovery.csv` | B7 | Cloud Discovery Catalog (MDA) | yes |
| `ai_mda_sessions.csv` | B8 | MDA Session Intelligence (MDA) | yes |
| `ai_copilot_surface_usage.csv` | A2 | Dynamic Copilot surface chart | no |

Total CSV count in the validated template = **13**. The normalized `ai_copilot_surface_usage.csv` preserves all Purview-observed surfaces and raw `AppHost`/`Workload` provenance; `ai_copilot_usage_graph.csv` remains for compatibility. Both use Purview Audit because the Graph Reports endpoint does not expose the required per-surface count schema.

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

The validated package uses a unique month-grain Calendar built from the `YearMonth` values present across all fact tables. Relationships are many-to-one and single-direction.

---

## 8. Generator architecture

```
generate_pbit_v26_unified.py
  │
  ├─ reads the committed V26 PBIT without modifying it
  ├─ patches DataModelSchema and synchronized UnappliedChanges
  ├─ removes stale report formatting selectors
  ├─ removes user-specific security bindings and MSIP sensitivity-label metadata
  ├─ preserves all remaining package entries and ZIP metadata
  └─ outputs AI-Solutions-Intelligence-Dashboard V26 Validated.pbit
```

---

## 9. Acceptance criteria

A v26 build is "done" when:

- [ ] PBIT opens cleanly when all 13 expected filenames exist, using exact header-only stubs for unavailable sources
- [ ] All 10 baseline pages render data
- [ ] All 3 MDA pages render their yellow overlay + visuals (visuals empty)
- [ ] When real MDA CSVs are dropped in, the same PBIT lights up the visuals on next refresh — no PBIT change needed
- [ ] `INSTRUCTIONS_v26.md` covers both paths (MDA / No-MDA) end-to-end
- [ ] Old `v22_E5*` PBITs marked DEPRECATED in their script comments
