#!/usr/bin/env python3
"""
AI Usage Dashboard v26 — Unified Edition
=========================================
ONE PBIT for every tier. Pages 1-10 work on E3+Copilot / E5 / E5+MDE P2.
Pages 11-13 are explicitly marked "(MDA)" and render a yellow callout
when their data is empty (no MDA deployed).

See AI_Usage_v26_Blueprint.md for the full page-by-page tier mapping
and INSTRUCTIONS_v26.md for the two parallel collection paths.

Output: AI_Usage_v26_Unified.pbit
"""
import json, os, zipfile, io, uuid, importlib.util

BASE = os.path.dirname(os.path.abspath(__file__))
OUTPUT_PBIT = os.path.join(BASE, "AI_Usage_v26_Unified.pbit")

# Inherit from v22 NoMDA v2 (which inherits from v21).
spec = importlib.util.spec_from_file_location(
    "v22v2", os.path.join(BASE, "generate_pbit_v22_E5_NoMDA_v2.py"))
v22v2 = importlib.util.module_from_spec(spec); spec.loader.exec_module(v22v2)

v21 = v22v2.v21
COL, PAGE_W, PAGE_H, THEME = v21.COL, v21.PAGE_W, v21.PAGE_H, v21.THEME
_shape, _text_box, _page_header = v21._shape, v21._text_box, v21._page_header
card, chart, slicer, table_visual = v21.card, v21.chart, v21.slicer, v21.table_visual


# ============================================================
# MODEL EXTENSION — 3 MDA-only tables
# ============================================================
def build_model_v26():
    m = v22v2.build_model_v2()
    m["name"] = "AI Usage Dashboard v26 — Unified"

    def tbl(name, filename, cols):
        col_types = ",\n        ".join(f'{{"{c["name"]}", {c["pqtype"]}}}' for c in cols)
        return {
            "name": name,
            "columns": [
                {"name": c["name"], "dataType": c["dtype"], "sourceColumn": c["name"],
                 **({"summarizeBy": c["summarize"]} if c.get("summarize") else {}),
                 **({"formatString": c["fmt"]} if c.get("fmt") else {}),
                 "annotations":[{"name":"SummarizationSetBy","value":"Automatic"}]}
                for c in cols
            ],
            "partitions":[{
                "name": f"{name}-partition","mode":"import",
                "source":{"type":"m","expression":[
                    "let",
                    f"    Source = Csv.Document(File.Contents(AI_Data_Folder_Path & \"{filename}\"), [Delimiter=\",\", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),",
                    "    Headers = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),",
                    "    Typed = Table.TransformColumnTypes(Headers, {",
                    f"        {col_types}",
                    "    })",
                    "in Typed",
                ]},
            }],
        }

    # AI_AppGovAlerts ── MDA App Governance
    m["model"]["tables"].append(tbl("AI_AppGovAlerts", "ai_appgov_alerts.csv", [
        {"name":"Timestamp","dtype":"string","pqtype":"type text"},
        {"name":"YearMonth","dtype":"string","pqtype":"type text"},
        {"name":"UPN","dtype":"string","pqtype":"type text"},
        {"name":"AppName","dtype":"string","pqtype":"type text"},
        {"name":"AlertType","dtype":"string","pqtype":"type text"},
        {"name":"Severity","dtype":"string","pqtype":"type text"},
        {"name":"Description","dtype":"string","pqtype":"type text"},
    ]))

    # AI_CloudDiscovery ── MDA Cloud Discovery (uploaded firewall logs)
    m["model"]["tables"].append(tbl("AI_CloudDiscovery", "ai_cloud_discovery.csv", [
        {"name":"AIDomain","dtype":"string","pqtype":"type text"},
        {"name":"AppCategory","dtype":"string","pqtype":"type text"},
        {"name":"YearMonth","dtype":"string","pqtype":"type text"},
        {"name":"RiskScore","dtype":"int64","pqtype":"Int64.Type","summarize":"average","fmt":"0"},
        {"name":"UploadVolumeMB","dtype":"double","pqtype":"type number","summarize":"sum","fmt":"#,0.0"},
        {"name":"DownloadVolumeMB","dtype":"double","pqtype":"type number","summarize":"sum","fmt":"#,0.0"},
        {"name":"TransactionCount","dtype":"int64","pqtype":"Int64.Type","summarize":"sum","fmt":"#,0"},
        {"name":"DistinctUsers","dtype":"int64","pqtype":"Int64.Type","summarize":"max","fmt":"#,0"},
        {"name":"SanctionStatus","dtype":"string","pqtype":"type text"},
    ]))

    # AI_MDA_Sessions ── per-session activities from MDA-connected apps
    m["model"]["tables"].append(tbl("AI_MDA_Sessions", "ai_mda_sessions.csv", [
        {"name":"Timestamp","dtype":"string","pqtype":"type text"},
        {"name":"YearMonth","dtype":"string","pqtype":"type text"},
        {"name":"UPN","dtype":"string","pqtype":"type text"},
        {"name":"AppName","dtype":"string","pqtype":"type text"},
        {"name":"ActionType","dtype":"string","pqtype":"type text"},
        {"name":"PolicyHit","dtype":"string","pqtype":"type text"},
        {"name":"PolicyAction","dtype":"string","pqtype":"type text"},
        {"name":"IPAddress","dtype":"string","pqtype":"type text"},
        {"name":"CountryCode","dtype":"string","pqtype":"type text"},
        {"name":"EventCount","dtype":"int64","pqtype":"Int64.Type","summarize":"sum","fmt":"#,0"},
    ]))

    # Relationships → Calendar
    for src in ("AI_AppGovAlerts","AI_CloudDiscovery","AI_MDA_Sessions"):
        m["model"]["relationships"].append({
            "name":str(uuid.uuid4()),"fromTable":src,"fromColumn":"YearMonth",
            "toTable":"Calendar","toColumn":"YearMonth",
            "crossFilteringBehavior":"oneDirection",
        })
    # Relate alerts/sessions to EntraUsers for dept slicing
    for src in ("AI_AppGovAlerts","AI_MDA_Sessions"):
        m["model"]["relationships"].append({
            "name":str(uuid.uuid4()),"fromTable":src,"fromColumn":"UPN",
            "toTable":"EntraUsers","toColumn":"userPrincipalName",
            "crossFilteringBehavior":"oneDirection",
        })

    # MDA-specific measures
    measures_table = next(t for t in m["model"]["tables"] if t["name"] == "AI Measures")
    measures_table["measures"].extend([
        {"name":"MDA Alerts",          "expression":"COUNTROWS(AI_AppGovAlerts)",                 "formatString":"#,0"},
        {"name":"MDA High-Sev Alerts",
         "expression":'CALCULATE(COUNTROWS(AI_AppGovAlerts), AI_AppGovAlerts[Severity] = "High")', "formatString":"#,0"},
        {"name":"Discovered AI Domains","expression":"DISTINCTCOUNT(AI_CloudDiscovery[AIDomain])", "formatString":"#,0"},
        {"name":"Shadow AI Domains",
         "expression":'CALCULATE(DISTINCTCOUNT(AI_CloudDiscovery[AIDomain]), AI_CloudDiscovery[SanctionStatus] = "Unsanctioned")',
         "formatString":"#,0"},
        {"name":"AI Upload MB",        "expression":"SUM(AI_CloudDiscovery[UploadVolumeMB])",     "formatString":"#,0.0"},
        {"name":"MDA Session Events",  "expression":"SUM(AI_MDA_Sessions[EventCount])",           "formatString":"#,0"},
        {"name":"MDA Policy Blocks",
         "expression":'CALCULATE(SUM(AI_MDA_Sessions[EventCount]), AI_MDA_Sessions[PolicyAction] = "Block")',
         "formatString":"#,0"},
    ])

    # FIX: Calendar is daily-grain, so Calendar[YearMonth] is not unique.
    # Force EVERY relationship pointing at Calendar[YearMonth] to be
    # many-to-many (including the 3 MDA relationships just added above).
    for r in m["model"]["relationships"]:
        if r.get("toTable") == "Calendar" and r.get("toColumn") == "YearMonth":
            r["fromCardinality"] = "many"
            r["toCardinality"] = "many"
            r["securityFilteringBehavior"] = "oneDirection"

    return m


# ============================================================
# "MDA Required" overlay helper
# ============================================================
def mda_callout(prefix, y, table_name, kql_table, kql_oneliner):
    """Yellow banner placed at the top of every (MDA) page."""
    h = 92
    bg = _shape(prefix+"_oBg", 20, y, PAGE_W-40, h, 150,
                fill="#FFF8E6", stroke=COL["estimated"])
    title = _text_box(prefix+"_oT", 32, y+8, PAGE_W-60, 22, 151,
        f"🛡️  Microsoft Defender for Cloud Apps required",
        font_size=12, color=COL["primary"], bold=True)
    body = _text_box(prefix+"_oB", 32, y+30, PAGE_W-60, 32, 152,
        f"This page reads from {table_name} (KQL: {kql_table}). "
        "If MDA is not deployed in your tenant, the visuals below render empty. "
        "See INSTRUCTIONS_v26.md → \"Enabling MDA Pages\" for setup.",
        font_size=10, color=COL["text"])
    kql = _text_box(prefix+"_oK", 32, y+62, PAGE_W-60, 24, 153,
        f"KQL preview:  {kql_oneliner}",
        font_size=9, color=COL["primary"])
    return [bg, title, body, kql], h + 12   # bottom-padding


# ============================================================
# 3 NEW MDA PAGES
# ============================================================
def page_oauth_anomaly_mda():
    vcs = _page_header("p_amda","OAuth Anomaly Alerts (MDA)",
        "Pre-built ML alerts from Microsoft Defender for Cloud Apps — App Governance.")
    y0 = 70
    overlay, dy = mda_callout("p_amda", y0,
        "AI_AppGovAlerts", "AppGovernanceAlert",
        "AppGovernanceAlert | where AppName matches regex \"chatgpt|openai|claude|...\" | summarize by AlertType, Severity")
    vcs += overlay
    y = y0 + dy

    # KPI row
    kw = (PAGE_W - 40 - 2*8) // 3
    vcs.append(card("p_amdak1", 20,        y, kw, 96, 200,
                    "AI Measures","MDA Alerts","TOTAL MDA ALERTS",
                    value_color=COL["primary"]))
    vcs.append(card("p_amdak2", 28+kw,     y, kw, 96, 201,
                    "AI Measures","MDA High-Sev Alerts","HIGH-SEVERITY ALERTS",
                    value_color=COL["unavailable"]))
    vcs.append(card("p_amdak3", 36+2*kw,   y, kw, 96, 202,
                    "AI Measures","Avg AI Risk Score per User","AVG RISK SCORE / USER",
                    value_color=COL["estimated"]))

    # Trend + breakdown
    y2 = y + 110
    half = (PAGE_W - 40 - 8) // 2
    vcs.append(chart("p_amdaTrend", 20, y2, half, 220, 210, "lineChart",
        categories=[("Calendar","MonthLabel")],
        measures=[("AI Measures","MDA Alerts"),
                  ("AI Measures","MDA High-Sev Alerts")],
        title="MDA Alert Trend (Monthly)"))
    vcs.append(chart("p_amdaSev", 28+half, y2, half, 220, 211, "donutChart",
        categories=[("AI_AppGovAlerts","Severity")],
        measures=[("AI Measures","MDA Alerts")],
        title="Alert Severity Mix"))

    # Detail table
    y3 = y2 + 230
    vcs.append(table_visual("p_amdaTbl", 20, y3, PAGE_W-40, 220, 220, [
        ("AI_AppGovAlerts","Timestamp",False),
        ("AI_AppGovAlerts","UPN",False),
        ("AI_AppGovAlerts","AppName",False),
        ("AI_AppGovAlerts","AlertType",False),
        ("AI_AppGovAlerts","Severity",False),
        ("AI_AppGovAlerts","Description",False),
    ], title="Alert Detail"))
    return vcs


def page_cloud_discovery_mda():
    vcs = _page_header("p_dmda","Cloud Discovery — Shadow AI Catalog (MDA)",
        "AI domains discovered across the tenant from firewall / proxy logs uploaded to MDA. Risk scored against the Microsoft cloud app catalog.")
    y0 = 70
    overlay, dy = mda_callout("p_dmda", y0,
        "AI_CloudDiscovery", "MDA Cloud Discovery report export",
        "Defender XDR → Cloud Apps → Cloud Discovery → Filter Category=Generative AI → Export")
    vcs += overlay
    y = y0 + dy

    # KPI row
    kw = (PAGE_W - 40 - 3*8) // 4
    vcs.append(card("p_dmdak1", 20,        y, kw, 96, 200,
                    "AI Measures","Discovered AI Domains","DISCOVERED AI DOMAINS",
                    value_color=COL["primary"]))
    vcs.append(card("p_dmdak2", 28+kw,     y, kw, 96, 201,
                    "AI Measures","Shadow AI Domains","UNSANCTIONED AI DOMAINS",
                    value_color=COL["unavailable"]))
    vcs.append(card("p_dmdak3", 36+2*kw,   y, kw, 96, 202,
                    "AI Measures","AI Upload MB","TOTAL UPLOAD (MB)",
                    value_color=COL["estimated"]))
    vcs.append(card("p_dmdak4", 44+3*kw,   y, kw, 96, 203,
                    "AI_CloudDiscovery","DistinctUsers","DISTINCT USERS"))

    # Catalog table
    y2 = y + 110
    vcs.append(table_visual("p_dmdaTbl", 20, y2, PAGE_W-40, 320, 210, [
        ("AI_CloudDiscovery","AIDomain",False),
        ("AI_CloudDiscovery","SanctionStatus",False),
        ("AI_CloudDiscovery","RiskScore",True),
        ("AI_CloudDiscovery","DistinctUsers",True),
        ("AI_CloudDiscovery","UploadVolumeMB",True),
        ("AI_CloudDiscovery","DownloadVolumeMB",True),
        ("AI_CloudDiscovery","TransactionCount",True),
    ], title="Discovered AI Apps — Risk Scored"))

    # Risk-vs-volume bubble
    y3 = y2 + 330
    vcs.append(chart("p_dmdaBar", 20, y3, PAGE_W-40, 200, 230, "clusteredBarChart",
        categories=[("AI_CloudDiscovery","AIDomain")],
        measures=[("AI Measures","AI Upload MB")],
        title="Top AI Domains by Upload Volume"))
    return vcs


def page_mda_session_intel():
    vcs = _page_header("p_smda","MDA Session Intelligence (MDA)",
        "Per-session activities recorded by MDA Conditional Access App Control — useful for proving DLP / paste-block policies fired during AI sessions.")
    y0 = 70
    overlay, dy = mda_callout("p_smda", y0,
        "AI_MDA_Sessions", "CloudAppEvents (MDA-enriched)",
        "CloudAppEvents | where Application in (AIApps) | where ActionType in ('FileUpload','SensitivePaste','PolicyMatch')")
    vcs += overlay
    y = y0 + dy

    # Slicers
    vcs.append(slicer("p_smdaSlA", 20,  y, 240, 50, 199,
                      "AI_MDA_Sessions","AppName","AI App"))
    vcs.append(slicer("p_smdaSlP", 268, y, 240, 50, 200,
                      "AI_MDA_Sessions","PolicyAction","Policy Action"))
    vcs.append(slicer("p_smdaSlM", 516, y, 200, 50, 201,
                      "Calendar","MonthLabel","Month"))

    # KPIs
    y2 = y + 60
    kw = (PAGE_W - 40 - 2*8) // 3
    vcs.append(card("p_smdak1", 20,        y2, kw, 96, 210,
                    "AI Measures","MDA Session Events","TOTAL SESSION EVENTS",
                    value_color=COL["primary"]))
    vcs.append(card("p_smdak2", 28+kw,     y2, kw, 96, 211,
                    "AI Measures","MDA Policy Blocks","POLICY BLOCKS",
                    value_color=COL["unavailable"]))
    vcs.append(card("p_smdak3", 36+2*kw,   y2, kw, 96, 212,
                    "AI_MDA_Sessions","UPN","DISTINCT USERS"))

    # Action-type breakdown + policy hit rate
    y3 = y2 + 110
    half = (PAGE_W - 40 - 8) // 2
    vcs.append(chart("p_smdaAct", 20, y3, half, 240, 220, "clusteredBarChart",
        categories=[("AI_MDA_Sessions","ActionType")],
        measures=[("AI Measures","MDA Session Events")],
        title="Session Activity by Action Type"))
    vcs.append(chart("p_smdaPol", 28+half, y3, half, 240, 221, "donutChart",
        categories=[("AI_MDA_Sessions","PolicyAction")],
        measures=[("AI Measures","MDA Session Events")],
        title="Policy Action Mix (Allow / Warn / Block)"))
    return vcs


# ============================================================
# Tier Comparison rewrite (unified version)
# ============================================================
def page_tier_compare_unified():
    vcs = _page_header("p_tcU","Tier Comparison — Unified Report Coverage",
        "This single report covers every tier. Pages with the (MDA) suffix render an overlay if MDA isn't deployed.")
    y0 = 78
    rows = [
        ("Capability",                                   "E3 + Copilot",   "+ MDE Plan 2",       "+ MDA",                 "M365 E5 (full)"),
        ("Copilot prompt counts (Purview audit)",        "✓ Verified",     "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("OAuth consent risk on AI plugins",             "✓ Verified",     "✓ Verified",         "✓ Verified + alerts",   "✓ Verified + alerts"),
        ("Sign-in hygiene (CA bypass)",                  "✓ Verified",     "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("Sanctioned 3P AI sign-ins (SSO)",              "✓ Verified",     "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("Unsanctioned 3P AI on managed devices",        "— not visible",  "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("File activity near AI prompt",                 "— not visible",  "✓ Behavioral",       "✓ Verified",            "✓ Verified"),
        ("Browser / Desktop / API channel split",        "— not visible",  "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("Behavioral Risk composite",                    "— partial",      "✓ Verified",         "✓ Verified",            "✓ Verified"),
        ("OAuth anomaly alerts (App Governance)",        "— not visible",  "— not visible",      "✓ Verified",            "✓ Verified"),
        ("Cloud Discovery (Shadow AI catalog)",          "— not visible",  "— not visible",      "✓ Verified",            "✓ Verified"),
        ("MDA session intelligence (paste / upload)",    "— not visible",  "— not visible",      "✓ Verified",            "✓ Verified"),
        ("Sensitive file label classification",          "— not visible",  "— not visible",      "— not visible",         "✓ Verified (MIP)"),
        ("DLP Warn/Block on Copilot prompt",             "— not visible",  "— not visible",      "— not visible",         "✓ Verified"),
        ("Audit log retention",                          "180 days",       "365 days (E5)",      "365 days",              "365 days"),
    ]
    col_xs = [20, 460, 660, 880, 1080]
    col_ws = [440, 200, 220, 200, 180]
    head_h = 32
    vcs.append(_shape("p_tcU_hbg", 20, y0, PAGE_W-40, head_h, 200, fill=COL["primary"]))
    for i,(x,w,h) in enumerate(zip(col_xs, col_ws, rows[0])):
        vcs.append(_text_box(f"p_tcU_h{i}", x+8, y0+8, w-10, head_h-10, 202+i,
                             h, font_size=11, color="#FFFFFF", bold=True))
    row_h = 28
    for r,row in enumerate(rows[1:]):
        y = y0 + head_h + r*row_h
        vcs.append(_shape(f"p_tcU_r{r}", 20, y, PAGE_W-40, row_h-2, 220+r*5,
                          fill="#F8F6FB" if r%2==0 else "#FFFFFF"))
        for i,(x,w,v) in enumerate(zip(col_xs, col_ws, row)):
            color = COL["text"]
            if v.startswith("—"):
                color = COL["unavailable"]
            elif v.startswith("✓"):
                color = COL["exact"]
            vcs.append(_text_box(f"p_tcU_c_{r}_{i}", x+8, y+6, w-10, row_h-10, 230+r*5+i,
                                 v, font_size=10, color=color, bold=(i==0)))
    callout_y = y0 + head_h + len(rows[1:])*row_h + 12
    vcs.append(_shape("p_tcU_kbg", 20, callout_y, PAGE_W-40, 96, 800,
                      fill="#E8F8EE", stroke=COL["exact"]))
    vcs.append(_text_box("p_tcU_kt", 32, callout_y+8, PAGE_W-60, 22, 801,
        "How to read this report", font_size=12, color=COL["primary"], bold=True))
    vcs.append(_text_box("p_tcU_kb", 32, callout_y+30, PAGE_W-60, 64, 802,
        "Pages 1–10 work on every tier (E3 → E5). "
        "Pages suffixed (MDA) — OAuth Anomaly Alerts, Cloud Discovery, MDA Session Intelligence — "
        "render a yellow callout when MDA isn't deployed and their visuals stay empty until MDA CSVs are populated. "
        "Drop the new CSVs into your data folder, refresh, and those pages light up automatically.",
        font_size=10, color=COL["text"]))
    return vcs


# ============================================================
# Patch page list
# ============================================================
PAGES = list(v22v2.PAGES)

# Rename "Behavioral Risk" page back from any "MDA" variant the user
# may have applied — it doesn't actually require MDA.
for i,(n,b) in enumerate(PAGES):
    if "Behavioral Risk" in n and "(MDA)" not in n and n != "Behavioral Risk":
        PAGES[i] = ("Behavioral Risk", b)

# Replace Tier Comparison with the unified version
for i,(n,b) in enumerate(PAGES):
    if n.startswith("Tier Comparison"):
        PAGES[i] = ("Tier Comparison", page_tier_compare_unified)
        break

# Insert MDA pages just before Tier Comparison
mda_pages = [
    ("OAuth Anomaly Alerts (MDA)",                page_oauth_anomaly_mda),
    ("Cloud Discovery — Shadow AI Catalog (MDA)", page_cloud_discovery_mda),
    ("MDA Session Intelligence (MDA)",            page_mda_session_intel),
]
insert_at = next((i for i,(n,_) in enumerate(PAGES) if n == "Tier Comparison"), len(PAGES))
for j,p in enumerate(mda_pages):
    PAGES.insert(insert_at + j, p)


def build_sections():
    sections = []
    for ordinal,(name,builder) in enumerate(PAGES):
        vcs = builder()
        sections.append({
            "name": uuid.uuid4().hex,
            "displayName": name,
            "displayOption": 1,
            "width": PAGE_W, "height": PAGE_H, "filters": "[]",
            "ordinal": ordinal,
            "visualContainers": vcs,
            "config": json.dumps({
                "layouts":[{"id":0,"position":{"x":0,"y":0,"z":0,"width":PAGE_W,"height":PAGE_H}}],
                "pageBinding":{"name":f"PB_{ordinal}","type":"Default","parameters":[],"acceptsFilterContext":"None"}
            }),
        })
    return sections


def generate_pbit():
    print("Building v26 Unified .pbit ...")
    model = build_model_v26()

    for t in model["model"]["tables"]:
        if t["name"] == "AI_Solutions":
            t["columns"] = [c for c in t["columns"]
                            if not (c.get("name") == "SolutionGroup"
                                    and c.get("type") == "calculated")]
            break

    def u16(s): return s.encode("utf-16-le")
    model_bytes = u16(json.dumps(model, indent=2, ensure_ascii=False))
    layout = {
        "id":0, "reportId": str(uuid.uuid4()),
        "config": json.dumps({
            "version":"5.54",
            "themeCollection":{"baseTheme":{"name":THEME,"version":"5.54","type":2}},
            "activeSectionIndex":0,"defaultDrillFilterOtherVisuals":True,
        }),
        "layoutOptimization":0,"filters":"[]","resourcePackages":[],
        "sections": build_sections(),
    }
    layout_bytes = u16(json.dumps(layout, ensure_ascii=False))
    rels = (
        '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '</Relationships>'
    ).encode("utf-8")
    ct = (
        '<?xml version="1.0" encoding="utf-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="json" ContentType=""/>'
        '<Default Extension="xml" ContentType=""/>'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Override PartName="/Version" ContentType=""/>'
        '<Override PartName="/DataModelSchema" ContentType=""/>'
        '<Override PartName="/DiagramState" ContentType=""/>'
        '<Override PartName="/Report/Layout" ContentType=""/>'
        '</Types>'
    ).encode("utf-8")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", ct)
        z.writestr("_rels/.rels",         rels)
        z.writestr("Version",             u16("1.0"))
        z.writestr("DataModelSchema",     model_bytes)
        z.writestr("DiagramState",        u16("{}"))
        z.writestr("Report/Layout",       layout_bytes)
    with open(OUTPUT_PBIT, "wb") as f:
        f.write(buf.getvalue())
    print(f"  Created: {OUTPUT_PBIT}  ({os.path.getsize(OUTPUT_PBIT):,} bytes)")


if __name__ == "__main__":
    print("=" * 64)
    print("  AI Usage Dashboard v26 — Unified")
    print("=" * 64)
    generate_pbit()
    print("\nPages:")
    for i,(n,_) in enumerate(PAGES,1):
        marker = "  🛡️" if "(MDA)" in n else "    "
        print(f"  {i:2d}.{marker} {n}")
    print("\nCSVs required (12 total — 9 baseline + 3 MDA stubs):")
    print("  baseline (always populate): EntraUsers, ai_solutions_catalog,")
    print("    ai_copilot_prompts, ai_activity_sessions, ai_oauth_consents,")
    print("    ai_sso_signins, ai_file_proximity, ai_offhours_geo,")
    print("    ai_copilot_usage_graph, ai_client_channel")
    print("  MDA (header-only stub if MDA not deployed):")
    print("    ai_appgov_alerts, ai_cloud_discovery, ai_mda_sessions")
    print("\nSee INSTRUCTIONS_v26.md and AI_Usage_v26_Blueprint.md")
