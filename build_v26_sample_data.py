#!/usr/bin/env python3
"""Deterministic, stdlib-only synthetic test-data generator.

Writes 12 CSV files whose headers EXACTLY match the columns expected by
"AI-Solutions-Intelligence-Dashboard V1.pbit" into a `sample_data_v26/` folder
located next to this script. Output is reproducible via SEED = 20260504.
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
    ("Microsoft 365 Copilot", "Managed Copilot", "Microsoft", "Low",
     "Does not train on data"),
    ("GitHub Copilot", "Developer AI", "Microsoft", "Low",
     "Does not train on data"),
    ("ChatGPT", "Unmanaged AI", "OpenAI", "High",
     "Trains on data unless opted out"),
    ("Claude", "Unmanaged AI", "Anthropic", "Medium",
     "Does not train on data"),
    ("Google Gemini", "Unmanaged AI", "Google", "Medium",
     "Trains on data unless opted out"),
    ("Perplexity", "Unmanaged AI", "Perplexity", "High",
     "Trains on data"),
    ("DeepSeek", "Unmanaged AI", "DeepSeek", "High",
     "Trains on data"),
    ("Midjourney", "Unmanaged AI", "Midjourney", "Medium",
     "Trains on data unless opted out"),
]

# Lookup: solution -> (Category, RiskTier)
SOL_META = {r[0]: (r[1], r[3]) for r in CATALOG_ROWS}
SOLUTIONS = [r[0] for r in CATALOG_ROWS]
THIRD_PARTY = ["ChatGPT", "Claude", "Google Gemini", "Perplexity",
               "DeepSeek", "Midjourney"]

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
              "manager_displayName", "manager_userPrincipalName", "hasLicense",
              "assignedLicenses", "createdDateTime"]
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
            lic = "Microsoft 365 E5;Microsoft 365 Copilot"
            has_lic = "true"
        else:
            lic = random.choice(["Microsoft 365 E5", "Microsoft 365 E3"])
            has_lic = random.choice(["true", "false"])
        created = base + timedelta(days=random.randint(0, 1200))
        rows.append([
            u["upn"], u["displayName"], u["department"],
            random.choice(JOB_TITLES), CITIES[city_i], COUNTRIES[city_i],
            "Contoso Ltd", "false" if is_disabled else "true",
            "Guest" if is_guest else "Member",
            mgr_dn, mgr_upn, has_lic, lic, iso_dt(created),
        ])
    return write_csv("EntraUsers.csv", header, rows)


# ===========================================================================
# 2) ai_solutions_catalog.csv
# ===========================================================================

def solution_group(category):
    if category == "Managed Copilot":
        return "Microsoft Copilot"
    if category == "Developer AI":
        return "Developer AI"
    return "Shadow AI"


def gen_catalog():
    header = ["AISolution", "Category", "Vendor", "RiskTier",
              "DefaultDataHandling", "SolutionGroup"]
    rows = [list(r) + [solution_group(r[1])] for r in CATALOG_ROWS]
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
                rows.append([
                    user, sol, ym,
                    random.randint(1, 400),
                    random.randint(1, 22),
                    random.randint(1, 1500),
                    random.randint(1, 3),
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
        rows.append([
            upn, app, ym,
            random.randint(1, 200), random.randint(1, 22),
            random.choice(["true", "false", "false", "false"]),
            random.choice(country_sets),
            random.choice(["Yes", "Yes", "No"]),  # meaningful share of No
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
    folders = ["Finance", "HR", "Legal", "Engineering", "General"]
    fnames = ["Q3_Forecast.xlsx", "Salary_Bands.xlsx", "NDA_Draft.docx",
              "Roadmap.pptx", "Notes.docx", "Budget_2026.xlsx",
              "Contract_v2.docx", "Specs.md", "Headcount.xlsx",
              "Review.docx"]
    rows = []
    for _ in range(200):
        upn = random.choice(UPNS)
        sol = random.choice(SOLUTIONS)
        ym = random.choice(YM_WINDOW)
        cat = random.choice(folders)
        ts = ym_to_dt(ym)
        sensitive = 1 if random.random() < 0.25 else 0
        name_match = sensitive if random.random() < 0.6 else 0
        folder_match = sensitive if name_match == 0 else (1 if random.random() < 0.5 else 0)
        rows.append([
            iso_dt(ts), upn, sol, ym,
            random.choice(fnames), cat,
            f"C:/Users/{upn.split('@')[0]}/Documents/{cat}",
            random.randint(1, 600), name_match, folder_match,
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
        anom_count = random.choice([0, 0, 0, 1, 1, 2, 3])
        if anom_count > 0:
            anoms = ";".join(random.sample(anom_pool, anom_count))
        else:
            anoms = ""
        rows.append([
            upn, ym, total, off, pct,
            random.randint(1, 4), anom_count, anoms,
        ])
    return write_csv("ai_offhours_geo.csv", header, rows)


# ===========================================================================
# 8) ai_copilot_usage_graph.csv
# ===========================================================================

def gen_copilot_usage():
    header = ["UserPrincipalName", "YearMonth", "TeamsPrompts", "WordPrompts",
              "ExcelPrompts", "OutlookPrompts", "PowerPointPrompts",
              "ChatPrompts", "TotalPrompts", "ActiveDays", "LastActivityDate"]
    rows = []
    licensed = sorted(LICENSED_COPILOT)
    for upn in licensed:
        nmonths = random.randint(3, 6)
        months = random.sample(YM_WINDOW, min(nmonths, len(YM_WINDOW)))
        for ym in months:
            ch = [random.randint(0, 200) for _ in range(6)]
            total = sum(ch)
            rows.append([
                upn, ym, ch[0], ch[1], ch[2], ch[3], ch[4], ch[5],
                total, random.randint(1, 22), iso_date(ym_to_dt(ym)),
            ])
    return write_csv("ai_copilot_usage_graph.csv", header, rows)


# ===========================================================================
# 9) ai_client_channel.csv
# ===========================================================================

def gen_client_channel():
    header = ["AISite", "Channel", "YearMonth", "EventCount"]
    sites = ["chat.openai.com", "claude.ai", "gemini.google.com",
             "perplexity.ai", "deepseek.com", "midjourney.com",
             "copilot.microsoft.com"]
    channels = ["Web", "Desktop", "Mobile", "API"]
    rows = []
    for _ in range(60):
        rows.append([
            random.choice(sites), random.choice(channels),
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
    policy_actions = ["Allow", "Block", "Monitor"]
    ccodes = ["US", "GB", "DE", "IE", "CA", "AU"]
    rows = []
    for _ in range(80):
        ym = random.choice(YM_WINDOW)
        hit = random.choice(["Yes", "No"])
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
    results = []
    results.append(gen_entra())
    results.append(gen_catalog())
    results.append(gen_activity())
    results.append(gen_oauth())
    results.append(gen_sso())
    results.append(gen_proximity())
    results.append(gen_offhours())
    results.append(gen_copilot_usage())
    results.append(gen_client_channel())
    results.append(gen_appgov())
    results.append(gen_cloud_discovery())
    results.append(gen_mda())

    # Build verification report
    lines = []
    lines.append("AI Solutions Test Data - Verification Report")
    lines.append(f"Generated: {datetime.now().isoformat()}")
    lines.append(f"Seed: {SEED}")
    lines.append(f"Output folder: {OUT_DIR}")
    lines.append("=" * 70)
    for path, nrows in results:
        with open(path, "r", encoding="utf-8") as f:
            header_line = f.readline().rstrip("\r\n")
        fname = os.path.basename(path)
        lines.append(f"FILE: {fname}")
        lines.append(f"  ROWS (excl header): {nrows}")
        lines.append(f"  HEADER: {header_line}")
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

    # Category strings present in activity
    act_cats = set(col_values("ai_activity_sessions.csv", "Category"))
    has_unmanaged = "Unmanaged AI" in act_cats
    has_dev = "Developer AI" in act_cats
    lines.append(f"  'Unmanaged AI' present in activity Category: "
                 f"{'PASS' if has_unmanaged else 'FAIL'}")
    lines.append(f"  'Developer AI' present in activity Category: "
                 f"{'PASS' if has_dev else 'FAIL'}")

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


if __name__ == "__main__":
    main()
