#!/usr/bin/env python3
"""Deterministic, stdlib-only synthetic test-data generator.

Writes 13 CSV files whose headers EXACTLY match the V26 data contract used by
"AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit" into a
`sample_data_v26/` folder located next to this script. Output is reproducible
via SEED = 20260504.
"""

import csv
import os
import random
from datetime import datetime, timedelta

SEED = 20260504
random.seed(SEED)

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample_data_v26")
os.makedirs(OUT_DIR, exist_ok=True)


def write_csv(filename, header, rows):
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    return path, len(rows)


def iso_dt(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_date(dt):
    return dt.strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# Shared dimensions
# ---------------------------------------------------------------------------

DEPARTMENTS = ["Sales", "Engineering", "Finance", "HR",
               "Marketing", "Legal", "Operations", "IT"]
JOB_TITLES = ["Analyst", "Manager", "Engineer", "Director",
              "Specialist", "Lead", "Coordinator", "Associate"]
CITIES = ["Seattle", "London", "New York", "Austin", "Dublin",
          "Sydney", "Toronto", "Berlin"]
COUNTRIES = ["US", "GB", "US", "US", "IE", "AU", "CA", "DE"]

FIRST = ["Alex", "Bria", "Cory", "Dana", "Evan", "Faye", "Gabe", "Hana",
         "Ivan", "Jade", "Kyle", "Lena", "Mason", "Nora", "Omar", "Priya",
         "Quinn", "Ravi", "Sara", "Tom", "Uma", "Vera", "Will", "Xena",
         "Yara", "Zane", "Beth", "Cole", "Drew", "Ella", "Finn", "Gwen",
         "Hugo", "Iris", "Jack", "Kara", "Liam", "Mira", "Noah", "Olga",
         "Pete", "Rosa", "Seth", "Tina", "Ueli", "Vlad", "Wade", "Ximena",
         "Yuki", "Zoey", "Adam", "Bella", "Caleb", "Dora", "Eli", "Fern",
         "Gus", "Holly", "Ian", "Jenna"]
LAST = ["Park", "Lee", "Vance", "Cole", "Reed", "Diaz", "Khan", "Wong",
        "Petrov", "Singh", "Brown", "Mori", "Cruz", "Hale", "Said", "Rao",
        "Ford", "Iyer", "Bell", "Frey", "Roy", "Bose", "Toney", "Marsh",
        "Adler", "Voss", "Quinn", "Page", "Shaw", "Hart", "Nash", "Webb",
        "Cano", "Lund", "Tate", "Yost", "Beck", "Funk", "Holt", "Pace",
        "Rios", "Snow", "Vogt", "Wynn", "Zane", "Boyd", "Crum", "Dent",
        "Egan", "Frye", "Gore", "Hobbs", "Ives", "Judd", "Kemp", "Lowe",
        "Mata", "Otto", "Pratt", "Sims"]


def build_users(n=60):
    users = []
    seen = set()
    i = 0
    while len(users) < n:
        fn = FIRST[i % len(FIRST)]
        ln = LAST[i % len(LAST)]
        i += 1
        upn = f"{fn.lower()}.{ln.lower()}@contoso.com"
        if upn in seen:
            upn = f"{fn.lower()}.{ln.lower()}{i}@contoso.com"
        seen.add(upn)
        users.append({
            "upn": upn,
            "displayName": f"{fn} {ln}",
            "department": random.choice(DEPARTMENTS),
        })
    return users


USERS = build_users(60)
UPNS = [u["upn"] for u in USERS]

# Managers: first 6 users are managers; the rest report to one of them.
MANAGERS = USERS[:6]

# Licensed-Copilot subset (~40 users) — these carry the literal "Copilot"
LICENSED_COPILOT = set(u["upn"] for u in USERS[:40])

# ---------------------------------------------------------------------------
# AISolution catalog
# ---------------------------------------------------------------------------

CATALOG_ROWS = [
    # AISolution, Category, Vendor, RiskTier, DefaultDataHandling
    ("Microsoft 365 Copilot", "Productivity", "Microsoft", "Sanctioned",
     "Internal Only"),
    ("GitHub Copilot", "Development", "Microsoft", "Sanctioned",
     "Code Context"),
    ("ChatGPT", "General AI", "OpenAI", "Conditional",
     "Public Cloud"),
    ("Claude", "General AI", "Anthropic", "Unsanctioned",
     "Public Cloud"),
    ("Gemini", "General AI", "Google", "Unsanctioned",
     "Public Cloud"),
    ("Perplexity", "Search AI", "Perplexity", "Unsanctioned",
     "Public Cloud"),
    ("DeepSeek", "General AI", "DeepSeek", "Unsanctioned",
     "Public Cloud"),
    ("Midjourney", "Image Generation", "Midjourney", "Unsanctioned",
     "Public Cloud"),
]

# Lookup: solution -> (Category, RiskTier)
SOL_META = {r[0]: (r[1], r[3]) for r in CATALOG_ROWS}
SOLUTIONS = [r[0] for r in CATALOG_ROWS]
THIRD_PARTY = ["ChatGPT", "Claude", "Gemini", "Perplexity",
               "DeepSeek", "Midjourney"]
CLIENT_CHANNELS = ["Browser", "API", "Desktop"]
FOLDER_CATEGORIES = ["Desktop", "Downloads", "Documents", "OneDrive",
                     "SharePoint", "Other"]

# ---------------------------------------------------------------------------
# YearMonth helpers
# ---------------------------------------------------------------------------

# Concentrated window 2025-09 .. 2026-06
YM_WINDOW = []
for (y, m) in [(2025, 9), (2025, 10), (2025, 11), (2025, 12),
               (2026, 1), (2026, 2), (2026, 3), (2026, 4),
               (2026, 5), (2026, 6)]:
    YM_WINDOW.append(f"{y:04d}-{m:02d}")


def ym_to_dt(ym, day=None, hour=None):
    y, m = ym.split("-")
    y, m = int(y), int(m)
    d = day if day else random.randint(1, 27)
    h = hour if hour is not None else random.randint(0, 23)
    return datetime(y, m, d, h, random.randint(0, 59), random.randint(0, 59))


# ===========================================================================
# 1) EntraUsers.csv
# ===========================================================================

def gen_entra():
    header = ["userPrincipalName", "displayName", "department", "jobTitle",
              "city", "country", "companyName", "accountEnabled", "userType",
              "createdDateTime", "hasLicense", "assignedLicenses",
              "manager_displayName", "manager_userPrincipalName"]
    rows = []
    guest_idxs = set(random.sample(range(len(USERS)), 4))
    disabled_idxs = set(random.sample(range(len(USERS)), 2))
    base = datetime(2022, 1, 1, 8, 0, 0)
    for idx, u in enumerate(USERS):
        city_i = random.randrange(len(CITIES))
        is_guest = idx in guest_idxs
        is_disabled = idx in disabled_idxs
        mgr = random.choice(MANAGERS)
        if u in MANAGERS:
            mgr_dn, mgr_upn = "", ""
        else:
            mgr_dn, mgr_upn = mgr["displayName"], mgr["upn"]
        if u["upn"] in LICENSED_COPILOT:
            lic = "SPE_E5;Microsoft_365_Copilot"
            has_lic = "TRUE"
        else:
            lic = random.choice(["SPE_E5", "SPE_E3"])
            has_lic = random.choice(["TRUE", "FALSE"])
        created = base + timedelta(days=random.randint(0, 1200))
        rows.append([
            u["upn"], u["displayName"], u["department"],
            random.choice(JOB_TITLES), CITIES[city_i], COUNTRIES[city_i],
            "Contoso Ltd", "FALSE" if is_disabled else "TRUE",
            "Guest" if is_guest else "Member", iso_dt(created),
            has_lic, lic, mgr_dn, mgr_upn,
        ])
    return write_csv("EntraUsers.csv", header, rows)


# ===========================================================================
# 2) ai_solutions_catalog.csv
# ===========================================================================

def solution_group(risk_tier, vendor):
    if vendor == "Microsoft":
        return "Microsoft Copilot"
    if risk_tier == "Conditional":
        return "Licensed Third-Party"
    return "Shadow AI"


def gen_catalog():
    header = ["AISolution", "Category", "Vendor", "RiskTier",
              "DefaultDataHandling", "SolutionGroup"]
    rows = [list(r) + [solution_group(r[3], r[2])] for r in CATALOG_ROWS]
    return write_csv("ai_solutions_catalog.csv", header, rows)


# ===========================================================================
# 3) ai_activity_sessions.csv
# ===========================================================================

def gen_activity():
    header = ["UPN", "AISolution", "YearMonth", "Sessions", "ActiveDays",
              "EstimatedPrompts", "DistinctDevices", "Category", "RiskTier"]
    rows = []

    # ~45 distinct active users. Assign each a tool-count bucket.
    active_users = UPNS[:45]
    # buckets: 10 -> 1 tool, 12 -> 2, 10 -> 3, 6 -> 4, 7 -> 5+
    buckets = ([1] * 10) + ([2] * 12) + ([3] * 10) + ([4] * 6) + ([5] * 7)
    random.shuffle(buckets)

    for user, ntools in zip(active_users, buckets):
        # Most users use Microsoft 365 Copilot — force it in.
        chosen = ["Microsoft 365 Copilot"]
        others = [s for s in SOLUTIONS if s != "Microsoft 365 Copilot"]
        random.shuffle(others)
        need = max(0, ntools - 1)
        chosen += others[:need]
        # if bucket==1 keep just copilot (already 1)
        chosen = chosen[:ntools]
        for sol in chosen:
            cat, risk = SOL_META[sol]
            # multiple months per user/solution
            nmonths = random.randint(2, 5)
            months = random.sample(YM_WINDOW, min(nmonths, len(YM_WINDOW)))
            for ym in months:
                sessions = random.randint(1, 400)
                rows.append([
                    user, sol, ym,
                    sessions,
                    random.randint(1, min(22, sessions)),
                    random.randint(1, sessions),
                    random.randint(1, min(3, sessions)),
                    cat, risk,
                ])
    return write_csv("ai_activity_sessions.csv", header, rows)


# ===========================================================================
# 4) ai_oauth_consents.csv
# ===========================================================================

def gen_oauth():
    header = ["UPN", "AppName", "YearMonth", "ConsentCount", "LastConsent",
              "PermissionWeight", "Permissions"]
    perms_pool = ["User.Read", "Mail.Read", "Files.ReadWrite.All",
                  "Sites.Read.All", "offline_access", "Calendars.Read",
                  "Contacts.Read", "Directory.Read.All"]
    rows = []
    for _ in range(70):
        upn = random.choice(UPNS)
        app = random.choice(THIRD_PARTY)
        ym = random.choice(YM_WINDOW)
        # ~40% high-risk weight >= 10
        if random.random() < 0.40:
            weight = random.randint(10, 20)
        else:
            weight = random.randint(1, 9)
        nperm = random.randint(1, 4)
        perms = ";".join(random.sample(perms_pool, nperm))
        rows.append([
            upn, app, ym, random.randint(1, 5),
            iso_dt(ym_to_dt(ym)), weight, perms,
        ])
    return write_csv("ai_oauth_consents.csv", header, rows)


# ===========================================================================
# 5) ai_sso_signins.csv
# ===========================================================================

def gen_sso():
    header = ["UPN", "Application", "YearMonth", "SignInCount", "DistinctDays",
              "IsGuest", "Countries", "HasConditionalAccess", "LastSignIn"]
    country_sets = ["US", "US;GB", "US;DE", "GB;IE", "US;CA", "AU;US"]
    rows = []
    for _ in range(80):
        upn = random.choice(UPNS)
        app = random.choice(THIRD_PARTY)
        ym = random.choice(YM_WINDOW)
        sign_in_count = random.randint(1, 200)
        rows.append([
            upn, app, ym,
            sign_in_count, random.randint(1, min(22, sign_in_count)),
            random.choice(["TRUE", "FALSE", "FALSE", "FALSE"]),
            random.choice(country_sets),
            random.choice(["TRUE", "TRUE", "FALSE"]),
            iso_dt(ym_to_dt(ym)),
        ])
    return write_csv("ai_sso_signins.csv", header, rows)


# ===========================================================================
# 6) ai_file_proximity.csv
# ===========================================================================

def gen_proximity():
    header = ["Timestamp", "UPN", "AISolution", "YearMonth", "FileName",
              "FolderCategory", "FolderPath", "SecondsToAI",
              "NameMatchesSensitivePattern", "FolderMatchesSensitive"]
    fnames = ["Q3_Forecast.xlsx", "Salary_Bands.xlsx", "NDA_Draft.docx",
              "Roadmap.pptx", "Notes.docx", "Budget_2026.xlsx",
              "Contract_v2.docx", "Specs.md", "Headcount.xlsx",
              "Review.docx"]
    rows = []
    for _ in range(200):
        upn = random.choice(UPNS)
        sol = random.choice(SOLUTIONS)
        ym = random.choice(YM_WINDOW)
        cat = random.choice(FOLDER_CATEGORIES)
        ts = ym_to_dt(ym)
        sensitive = 1 if random.random() < 0.25 else 0
        name_match = sensitive if random.random() < 0.6 else 0
        folder_match = sensitive if name_match == 0 else (1 if random.random() < 0.5 else 0)
        rows.append([
            iso_dt(ts), upn, sol, ym,
            random.choice(fnames), cat,
            f"C:/Users/{upn.split('@')[0]}/Documents/{cat}",
            random.randint(1, 300), name_match, folder_match,
        ])
    return write_csv("ai_file_proximity.csv", header, rows)


# ===========================================================================
# 7) ai_offhours_geo.csv
# ===========================================================================

def gen_offhours():
    header = ["UPN", "YearMonth", "TotalSessions", "OffHoursSessions",
              "OffHoursPct", "DistinctCountries", "AnomalousCountryCount",
              "AnomalousCountries"]
    anom_pool = ["RU", "IR", "KP", "CN", "BY"]
    rows = []
    for _ in range(90):
        upn = random.choice(UPNS)
        ym = random.choice(YM_WINDOW)
        total = random.randint(5, 300)
        off = random.randint(0, total)
        pct = round(off / total, 4)
        distinct_countries = random.randint(1, 4)
        max_anomalous = min(3, distinct_countries - 1)
        anom_count = random.choice(([0, 0, 0] +
                                    list(range(1, max_anomalous + 1))))
        if anom_count > 0:
            anoms = ";".join(random.sample(anom_pool, anom_count))
        else:
            anoms = ""
        rows.append([
            upn, ym, total, off, pct,
            distinct_countries, anom_count, anoms,
        ])
    return write_csv("ai_offhours_geo.csv", header, rows)


# ===========================================================================
# 8) ai_copilot_usage_graph.csv + ai_copilot_surface_usage.csv
# ===========================================================================

def gen_copilot_usage():
    usage_header = ["UserPrincipalName", "YearMonth", "TeamsPrompts",
                    "WordPrompts", "ExcelPrompts", "OutlookPrompts",
                    "PowerPointPrompts", "ChatPrompts", "TotalPrompts",
                    "ActiveDays", "LastActivityDate"]
    surface_header = ["UserPrincipalName", "YearMonth", "Surface",
                      "SourceWorkload", "SourceAppHost", "PromptCount",
                      "ActiveDays", "LastActivityDate"]
    surface_specs = [
        ("Teams", "MicrosoftTeams", "MicrosoftTeams"),
        ("Word", "Microsoft365", "Word"),
        ("Excel", "Microsoft365", "Excel"),
        ("Outlook", "Microsoft365", "Outlook"),
        ("PowerPoint", "Microsoft365", "PowerPoint"),
        ("Chat", "Microsoft365", "M365Chat"),
        ("Loop", "Microsoft365", "Loop"),
        ("OneNote", "Microsoft365", "OneNote"),
        ("SharePoint", "Microsoft365", "SharePoint"),
        ("Edge", "Microsoft365", "Edge"),
    ]
    usage_rows = []
    surface_rows = []
    licensed = sorted(LICENSED_COPILOT)
    for upn in licensed:
        nmonths = random.randint(3, 6)
        months = random.sample(YM_WINDOW, min(nmonths, len(YM_WINDOW)))
        for ym in months:
            counts = {}
            all_days = set()
            for surface, workload, app_host in surface_specs:
                upper = 200 if surface in {"Teams", "Word", "Excel", "Outlook",
                                           "PowerPoint", "Chat"} else 60
                prompt_count = random.randint(1, upper)
                active_day_count = random.randint(1, min(22, prompt_count))
                active_days = set(random.sample(range(1, 28), active_day_count))
                all_days.update(active_days)
                counts[surface] = prompt_count
                surface_rows.append([
                    upn, ym, surface, workload, app_host, prompt_count,
                    len(active_days), iso_date(ym_to_dt(ym, day=max(active_days))),
                ])

            usage_rows.append([
                upn, ym, counts["Teams"], counts["Word"], counts["Excel"],
                counts["Outlook"], counts["PowerPoint"], counts["Chat"],
                sum(counts.values()), len(all_days),
                iso_date(ym_to_dt(ym, day=max(all_days))),
            ])
    return [
        write_csv("ai_copilot_usage_graph.csv", usage_header, usage_rows),
        write_csv("ai_copilot_surface_usage.csv", surface_header, surface_rows),
    ]


# ===========================================================================
# 9) ai_client_channel.csv
# ===========================================================================

def gen_client_channel():
    header = ["AISite", "Channel", "YearMonth", "EventCount"]
    sites = ["chat.openai.com", "claude.ai", "gemini.google.com",
             "perplexity.ai", "deepseek.com", "midjourney.com",
             "copilot.microsoft.com"]
    rows = []
    for _ in range(60):
        rows.append([
            random.choice(sites), random.choice(CLIENT_CHANNELS),
            random.choice(YM_WINDOW), random.randint(1, 5000),
        ])
    return write_csv("ai_client_channel.csv", header, rows)


# ===========================================================================
# 10) ai_appgov_alerts.csv
# ===========================================================================

def gen_appgov():
    header = ["Timestamp", "YearMonth", "UPN", "AppName", "AlertType",
              "Severity", "Description"]
    alert_types = ["Risky OAuth Grant", "Data Exfiltration",
                   "Suspicious Sign-in", "Excessive Permissions"]
    sevs = ["Low", "Medium", "High"]
    descs = {
        "Risky OAuth Grant": "App granted broad mailbox access",
        "Data Exfiltration": "Large outbound file transfer to AI app",
        "Suspicious Sign-in": "Sign-in from anomalous location",
        "Excessive Permissions": "App requested high-privilege scopes",
    }
    rows = []
    for _ in range(50):
        ym = random.choice(YM_WINDOW)
        at = random.choice(alert_types)
        rows.append([
            iso_dt(ym_to_dt(ym)), ym, random.choice(UPNS),
            random.choice(THIRD_PARTY), at, random.choice(sevs), descs[at],
        ])
    return write_csv("ai_appgov_alerts.csv", header, rows)


# ===========================================================================
# 11) ai_cloud_discovery.csv
# ===========================================================================

def gen_cloud_discovery():
    header = ["AIDomain", "AppCategory", "YearMonth", "RiskScore",
              "UploadVolumeMB", "DownloadVolumeMB", "TransactionCount",
              "DistinctUsers", "SanctionStatus"]
    domains = ["chat.openai.com", "claude.ai", "gemini.google.com",
               "perplexity.ai", "deepseek.com"]
    statuses = ["Sanctioned", "Unsanctioned", "Under Review"]
    rows = []
    for _ in range(40):
        rows.append([
            random.choice(domains), "Generative AI",
            random.choice(YM_WINDOW), random.randint(1, 10),
            round(random.uniform(0, 5000), 2),
            round(random.uniform(0, 5000), 2),
            random.randint(10, 5000), random.randint(1, 60),
            random.choice(statuses),
        ])
    return write_csv("ai_cloud_discovery.csv", header, rows)


# ===========================================================================
# 12) ai_mda_sessions.csv
# ===========================================================================

def gen_mda():
    header = ["Timestamp", "YearMonth", "UPN", "AppName", "ActionType",
              "PolicyHit", "PolicyAction", "IPAddress", "CountryCode",
              "EventCount"]
    actions = ["Upload", "Download", "Share", "Login"]
    policy_actions = ["Allow", "Warn", "Block"]
    ccodes = ["US", "GB", "DE", "IE", "CA", "AU"]
    rows = []
    for _ in range(80):
        ym = random.choice(YM_WINDOW)
        hit = random.choice(["TRUE", "FALSE"])
        rows.append([
            iso_dt(ym_to_dt(ym)), ym, random.choice(UPNS),
            random.choice(THIRD_PARTY), random.choice(actions),
            hit, random.choice(policy_actions),
            f"13.64.{random.randint(0,255)}.{random.randint(0,255)}",
            random.choice(ccodes), random.randint(1, 500),
        ])
    return write_csv("ai_mda_sessions.csv", header, rows)


# ===========================================================================
# Run all + verify
# ===========================================================================

def main():
    expected_headers = {
        "EntraUsers.csv": ["userPrincipalName", "displayName", "department",
                           "jobTitle", "city", "country", "companyName",
                           "accountEnabled", "userType", "createdDateTime",
                           "hasLicense", "assignedLicenses",
                           "manager_displayName", "manager_userPrincipalName"],
        "ai_solutions_catalog.csv": ["AISolution", "Category", "Vendor",
                                     "RiskTier", "DefaultDataHandling",
                                     "SolutionGroup"],
        "ai_activity_sessions.csv": ["UPN", "AISolution", "YearMonth",
                                     "Sessions", "ActiveDays",
                                     "EstimatedPrompts", "DistinctDevices",
                                     "Category", "RiskTier"],
        "ai_oauth_consents.csv": ["UPN", "AppName", "YearMonth",
                                  "ConsentCount", "LastConsent",
                                  "PermissionWeight", "Permissions"],
        "ai_sso_signins.csv": ["UPN", "Application", "YearMonth",
                               "SignInCount", "DistinctDays", "IsGuest",
                               "Countries", "HasConditionalAccess",
                               "LastSignIn"],
        "ai_file_proximity.csv": ["Timestamp", "UPN", "AISolution",
                                  "YearMonth", "FileName", "FolderCategory",
                                  "FolderPath", "SecondsToAI",
                                  "NameMatchesSensitivePattern",
                                  "FolderMatchesSensitive"],
        "ai_offhours_geo.csv": ["UPN", "YearMonth", "TotalSessions",
                                "OffHoursSessions", "OffHoursPct",
                                "DistinctCountries",
                                "AnomalousCountryCount",
                                "AnomalousCountries"],
        "ai_copilot_usage_graph.csv": ["UserPrincipalName", "YearMonth",
                                       "TeamsPrompts", "WordPrompts",
                                       "ExcelPrompts", "OutlookPrompts",
                                       "PowerPointPrompts", "ChatPrompts",
                                       "TotalPrompts", "ActiveDays",
                                       "LastActivityDate"],
        "ai_copilot_surface_usage.csv": ["UserPrincipalName", "YearMonth",
                                         "Surface", "SourceWorkload",
                                         "SourceAppHost", "PromptCount",
                                         "ActiveDays", "LastActivityDate"],
        "ai_client_channel.csv": ["AISite", "Channel", "YearMonth",
                                  "EventCount"],
        "ai_appgov_alerts.csv": ["Timestamp", "YearMonth", "UPN", "AppName",
                                 "AlertType", "Severity", "Description"],
        "ai_cloud_discovery.csv": ["AIDomain", "AppCategory", "YearMonth",
                                   "RiskScore", "UploadVolumeMB",
                                   "DownloadVolumeMB", "TransactionCount",
                                   "DistinctUsers", "SanctionStatus"],
        "ai_mda_sessions.csv": ["Timestamp", "YearMonth", "UPN", "AppName",
                                "ActionType", "PolicyHit", "PolicyAction",
                                "IPAddress", "CountryCode", "EventCount"],
    }
    results = []
    results.append(gen_entra())
    results.append(gen_catalog())
    results.append(gen_activity())
    results.append(gen_oauth())
    results.append(gen_sso())
    results.append(gen_proximity())
    results.append(gen_offhours())
    results.extend(gen_copilot_usage())
    results.append(gen_client_channel())
    results.append(gen_appgov())
    results.append(gen_cloud_discovery())
    results.append(gen_mda())

    # Build verification report
    lines = []
    lines.append("AI Solutions Test Data - Verification Report")
    lines.append("Generated: deterministic")
    lines.append(f"Seed: {SEED}")
    lines.append(f"Output folder: {os.path.basename(OUT_DIR)}")
    lines.append("=" * 70)
    failures = []
    for path, nrows in results:
        with open(path, "r", encoding="utf-8", newline="") as f:
            actual_header = next(csv.reader(f))
        fname = os.path.basename(path)
        header_ok = actual_header == expected_headers[fname]
        if not header_ok:
            failures.append(f"{fname}: unexpected header")
        lines.append(f"FILE: {fname}")
        lines.append(f"  ROWS (excl header): {nrows}")
        lines.append(f"  HEADER: {','.join(actual_header)}")
        lines.append(f"  HEADER CONTRACT: {'PASS' if header_ok else 'FAIL'}")
        lines.append("-" * 70)

    # Referential integrity checks
    lines.append("REFERENTIAL INTEGRITY CHECKS")
    upn_set = set(UPNS)
    sol_set = set(SOLUTIONS)

    def col_values(fname, col):
        p = os.path.join(OUT_DIR, fname)
        vals = []
        with open(p, "r", encoding="utf-8") as f:
            r = csv.DictReader(f)
            for row in r:
                vals.append(row[col])
        return vals

    def dict_rows(fname):
        p = os.path.join(OUT_DIR, fname)
        with open(p, "r", encoding="utf-8") as f:
            return list(csv.DictReader(f))

    def check_constraint(fname, label, predicate):
        invalid_count = sum(1 for row in dict_rows(fname)
                            if not predicate(row))
        valid = invalid_count == 0
        if not valid:
            failures.append(f"{fname}: {label} ({invalid_count} invalid rows)")
        lines.append(f"  {fname} {label}: "
                     f"{'PASS' if valid else 'FAIL ' + str(invalid_count)}")

    # AI_Activity AISolution -> catalog
    act_sols = set(col_values("ai_activity_sessions.csv", "AISolution"))
    missing_sol = act_sols - sol_set
    lines.append(f"  ai_activity_sessions AISolution all in catalog: "
                 f"{'PASS' if not missing_sol else 'FAIL ' + str(missing_sol)}")

    # AI_Activity UPN -> Entra
    act_upns = set(col_values("ai_activity_sessions.csv", "UPN"))
    missing_upn = act_upns - upn_set
    lines.append(f"  ai_activity_sessions UPN all in EntraUsers: "
                 f"{'PASS' if not missing_upn else 'FAIL ' + str(missing_upn)}")

    # file_proximity AISolution -> catalog
    prox_sols = set(col_values("ai_file_proximity.csv", "AISolution"))
    missing_prox = prox_sols - sol_set
    lines.append(f"  ai_file_proximity AISolution all in catalog: "
                 f"{'PASS' if not missing_prox else 'FAIL ' + str(missing_prox)}")

    # copilot usage UPN -> Entra
    cop_upns = set(col_values("ai_copilot_usage_graph.csv", "UserPrincipalName"))
    missing_cop = cop_upns - upn_set
    lines.append(f"  ai_copilot_usage_graph UPN all in EntraUsers: "
                 f"{'PASS' if not missing_cop else 'FAIL ' + str(missing_cop)}")

    surface_upns = set(col_values("ai_copilot_surface_usage.csv",
                                  "UserPrincipalName"))
    missing_surface_upn = surface_upns - upn_set
    lines.append(f"  ai_copilot_surface_usage UPN all in EntraUsers: "
                 f"{'PASS' if not missing_surface_upn else 'FAIL ' + str(missing_surface_upn)}")

    usage_totals = {}
    with open(os.path.join(OUT_DIR, "ai_copilot_usage_graph.csv"),
              "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            usage_totals[(row["UserPrincipalName"], row["YearMonth"])] = int(
                row["TotalPrompts"])
    surface_totals = {}
    with open(os.path.join(OUT_DIR, "ai_copilot_surface_usage.csv"),
              "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            key = (row["UserPrincipalName"], row["YearMonth"])
            surface_totals[key] = surface_totals.get(key, 0) + int(
                row["PromptCount"])
    copilot_totals_match = usage_totals == surface_totals
    if not copilot_totals_match:
        failures.append("Copilot legacy and normalized totals do not match")
    lines.append(f"  Copilot legacy totals match normalized surface totals: "
                 f"{'PASS' if copilot_totals_match else 'FAIL'}")

    # Exporter risk-tier contract present in activity
    act_risk = set(col_values("ai_activity_sessions.csv", "RiskTier"))
    canonical_risk = {"Sanctioned", "Conditional", "Unsanctioned"}
    activity_risk_ok = act_risk <= canonical_risk
    if not activity_risk_ok:
        failures.append("ai_activity_sessions.csv: non-canonical RiskTier")
    lines.append(f"  Activity RiskTier values are canonical: "
                 f"{'PASS' if activity_risk_ok else 'FAIL'}")

    catalog_risk = set(col_values("ai_solutions_catalog.csv", "RiskTier"))
    catalog_risk_ok = catalog_risk <= canonical_risk
    if not catalog_risk_ok:
        failures.append("ai_solutions_catalog.csv: non-canonical RiskTier")
    lines.append(f"  Catalog RiskTier values are canonical: "
                 f"{'PASS' if catalog_risk_ok else 'FAIL'}")

    boolean_checks = [
        ("EntraUsers.csv", "accountEnabled"),
        ("EntraUsers.csv", "hasLicense"),
        ("ai_sso_signins.csv", "IsGuest"),
        ("ai_sso_signins.csv", "HasConditionalAccess"),
        ("ai_mda_sessions.csv", "PolicyHit"),
    ]
    for fname, column in boolean_checks:
        values = set(col_values(fname, column))
        valid = values <= {"TRUE", "FALSE"}
        if not valid:
            failures.append(f"{fname}: {column} is not TRUE/FALSE")
        lines.append(f"  {fname} {column} uses TRUE/FALSE: "
                     f"{'PASS' if valid else 'FAIL ' + str(values)}")

    policy_actions = set(col_values("ai_mda_sessions.csv", "PolicyAction"))
    valid_policy_actions = policy_actions <= {"Allow", "Warn", "Block"}
    if not valid_policy_actions:
        failures.append("ai_mda_sessions.csv: non-canonical PolicyAction")
    lines.append(f"  ai_mda_sessions.csv PolicyAction values are canonical: "
                 f"{'PASS' if valid_policy_actions else 'FAIL ' + str(policy_actions)}")

    # Production-query invariants used by the report measures.
    check_constraint(
        "ai_activity_sessions.csv",
        "ActiveDays, EstimatedPrompts, and DistinctDevices do not exceed Sessions",
        lambda row: (
            int(row["ActiveDays"]) <= int(row["Sessions"])
            and int(row["EstimatedPrompts"]) <= int(row["Sessions"])
            and int(row["DistinctDevices"]) <= int(row["Sessions"])
        ),
    )
    check_constraint(
        "ai_sso_signins.csv",
        "DistinctDays does not exceed SignInCount",
        lambda row: int(row["DistinctDays"]) <= int(row["SignInCount"]),
    )
    check_constraint(
        "ai_offhours_geo.csv",
        "AnomalousCountryCount does not exceed DistinctCountries minus one",
        lambda row: (
            int(row["AnomalousCountryCount"])
            <= int(row["DistinctCountries"]) - 1
        ),
    )
    check_constraint(
        "ai_file_proximity.csv",
        "SecondsToAI is within the production 300-second window",
        lambda row: 0 <= int(row["SecondsToAI"]) <= 300,
    )
    check_constraint(
        "ai_file_proximity.csv",
        "FolderCategory uses production values",
        lambda row: row["FolderCategory"] in FOLDER_CATEGORIES,
    )
    check_constraint(
        "ai_client_channel.csv",
        "Channel uses production values",
        lambda row: row["Channel"] in CLIENT_CHANNELS,
    )

    # Managed Copilot string present
    has_managed = "Microsoft 365 Copilot" in sol_set
    lines.append(f"  'Microsoft 365 Copilot' exact in catalog: "
                 f"{'PASS' if has_managed else 'FAIL'}")

    # Licensed Copilot users in Entra (assignedLicenses contains Copilot)
    lic_count = 0
    for v in col_values("EntraUsers.csv", "assignedLicenses"):
        if "Copilot" in v:
            lic_count += 1
    lines.append(f"  EntraUsers with 'Copilot' in assignedLicenses: {lic_count}")

    report = "\n".join(lines)
    vpath = os.path.join(OUT_DIR, "_VERIFY.txt")
    with open(vpath, "w", encoding="utf-8") as f:
        f.write(report + "\n")

    print(report)
    print(f"\nVERIFY FILE: {vpath}")
    if failures:
        raise RuntimeError("Sample-data validation failed: " + "; ".join(failures))


if __name__ == "__main__":
    main()
