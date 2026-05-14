#!/usr/bin/env python3
"""
Generate two demo data folders for AI_Usage_v26_Unified.pbit:

  sample_data_v26_no_mda/   — 8 baseline reused + 2 new baseline + 3 MDA stubs
  sample_data_v26_with_mda/ — 8 baseline reused + 2 new baseline + 3 MDA populated

Run from /Users/luzlorenz/Downloads/StudioProjects.
"""
import csv, os, random, shutil
from datetime import datetime, timedelta

random.seed(42)

BASE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(BASE, "sample_data_v22_E5V3")
NOMDA = os.path.join(BASE, "sample_data_v26_no_mda")
WITH  = os.path.join(BASE, "sample_data_v26_with_mda")

REUSE = [
    "EntraUsers.csv","ai_solutions_catalog.csv","ai_copilot_usage_graph.csv",
    "ai_sso_signins.csv","ai_oauth_consents.csv","ai_offhours_geo.csv",
    "ai_file_proximity.csv","ai_activity_sessions.csv",
]

# -- Reset folders ----------------------------------------------------
for d in (NOMDA, WITH):
    if os.path.exists(d): shutil.rmtree(d)
    os.makedirs(d)

# -- Copy the 8 reusable baseline files into BOTH folders -------------
for fn in REUSE:
    shutil.copy(os.path.join(SRC, fn), os.path.join(NOMDA, fn))
    shutil.copy(os.path.join(SRC, fn), os.path.join(WITH,  fn))

# Months we'll synthesize for: last 6
def months(n=6):
    today = datetime.today().replace(day=1)
    out = []
    for i in range(n,0,-1):
        d = today.replace(year=today.year, month=today.month) - timedelta(days=30*i)
        out.append(d.strftime("%Y-%m"))
    return sorted(set(out))
MONTHS = months(6)

# Pull a UPN list from the existing EntraUsers.csv
upns = []
with open(os.path.join(SRC, "EntraUsers.csv"), newline="") as f:
    r = csv.DictReader(f)
    for row in r:
        upns.append(row["userPrincipalName"])
upns = upns[:60]   # trim to keep CSVs small

DEPARTMENTS = ["Sales","Marketing","Engineering","Finance","HR","IT","Legal","Operations","Support","Executive","R&D","Product"]

# ============================================================
# 1. ai_copilot_prompts.csv  (Purview Audit pivot output)
# ============================================================
def write_copilot_prompts(folder):
    path = os.path.join(folder, "ai_copilot_prompts.csv")
    with open(path,"w",newline="") as f:
        w = csv.writer(f)
        w.writerow(["UserPrincipalName","YearMonth","TeamsPrompts","WordPrompts",
                    "ExcelPrompts","OutlookPrompts","PowerPointPrompts","ChatPrompts",
                    "TotalPrompts","ActiveDays","LastActivityDate"])
        for upn in upns:
            for ym in MONTHS:
                t = random.randint(0,40); wd = random.randint(0,30)
                e = random.randint(0,25); o = random.randint(0,35)
                p = random.randint(0,15); c = random.randint(5,80)
                tot = t+wd+e+o+p+c
                if tot == 0: continue
                w.writerow([upn,ym,t,wd,e,o,p,c,tot,
                            random.randint(1, min(20, tot)),
                            f"{ym}-{random.randint(10,28):02d}"])

# ============================================================
# 2. ai_client_channel.csv  (CloudAppEvents.UserAgent split)
# ============================================================
AI_SITES = ["ChatGPT","Claude","Copilot","DeepSeek","Gemini","HuggingFace",
            "Jasper AI","Midjourney","Perplexity","Character.AI"]
CHANNELS = ["Browser","Desktop App","API/Script"]
CHANNEL_WEIGHTS = {"ChatGPT":[60,40,45], "Claude":[20,5,12], "Copilot":[35,28,3],
                   "DeepSeek":[8,2,5], "Gemini":[28,4,2], "HuggingFace":[3,1,1],
                   "Jasper AI":[6,1,0], "Midjourney":[3,1,0],
                   "Perplexity":[14,3,2], "Character.AI":[5,0,0]}
def write_client_channel(folder):
    path = os.path.join(folder, "ai_client_channel.csv")
    with open(path,"w",newline="") as f:
        w = csv.writer(f)
        w.writerow(["AISite","Channel","YearMonth","EventCount"])
        for site in AI_SITES:
            for i,ch in enumerate(CHANNELS):
                base = CHANNEL_WEIGHTS[site][i]
                if base == 0: continue
                for ym in MONTHS:
                    cnt = max(0, base + random.randint(-5,8))
                    if cnt: w.writerow([site, ch, ym, cnt])

# ============================================================
# 3. MDA stubs (No-MDA version) — header rows only
# ============================================================
MDA_HEADERS = {
    "ai_appgov_alerts.csv":
        "Timestamp,YearMonth,UPN,AppName,AlertType,Severity,Description",
    "ai_cloud_discovery.csv":
        "AIDomain,AppCategory,YearMonth,RiskScore,UploadVolumeMB,DownloadVolumeMB,TransactionCount,DistinctUsers,SanctionStatus",
    "ai_mda_sessions.csv":
        "Timestamp,YearMonth,UPN,AppName,ActionType,PolicyHit,PolicyAction,IPAddress,CountryCode,EventCount",
}
def write_mda_stubs(folder):
    for fn, header in MDA_HEADERS.items():
        with open(os.path.join(folder, fn),"w") as f:
            f.write(header + "\n")

# ============================================================
# 4. MDA populated (With-MDA version)
# ============================================================
def write_mda_appgov(folder):
    alert_types = [
        ("Suspicious OAuth app",        "High"),
        ("App with high privilege",     "Medium"),
        ("Risky API usage pattern",     "High"),
        ("Unusual app data download",   "Medium"),
        ("Anomalous user agent",        "Low"),
        ("Token reuse from new geo",    "High"),
    ]
    apps = ["ChatGPT (community plugin)","Claude.ai connector","Perplexity Browser",
            "Notion AI Workspace","Zapier OpenAI step","Gemini for Workspace",
            "Jasper Brand Voice","Copy.ai Workflows"]
    path = os.path.join(folder, "ai_appgov_alerts.csv")
    with open(path,"w",newline="") as f:
        w = csv.writer(f)
        w.writerow(MDA_HEADERS["ai_appgov_alerts.csv"].split(","))
        for _ in range(120):
            ym = random.choice(MONTHS)
            day = random.randint(1,27); hr = random.randint(0,23)
            ts = f"{ym}-{day:02d}T{hr:02d}:{random.randint(0,59):02d}:00Z"
            at, sev = random.choice(alert_types)
            app = random.choice(apps)
            desc = f"{at} detected for {app} — review consent and revoke if untrusted."
            w.writerow([ts, ym, random.choice(upns), app, at, sev, desc])

def write_mda_cloud_discovery(folder):
    domains = [
        ("chatgpt.com","Generative AI",3,"Sanctioned"),
        ("openai.com","Generative AI",4,"Sanctioned"),
        ("claude.ai","Generative AI",4,"Sanctioned"),
        ("perplexity.ai","Generative AI",5,"Sanctioned"),
        ("gemini.google.com","Generative AI",4,"Sanctioned"),
        ("character.ai","Generative AI",8,"Unsanctioned"),
        ("janitorai.com","Generative AI",9,"Unsanctioned"),
        ("poe.com","Generative AI",7,"Unsanctioned"),
        ("deepseek.com","Generative AI",7,"Unsanctioned"),
        ("you.com","Generative AI",6,"Monitored"),
        ("huggingface.co","Generative AI",5,"Monitored"),
        ("midjourney.com","Generative AI",6,"Unsanctioned"),
        ("notion.so","Productivity AI",4,"Sanctioned"),
        ("jasper.ai","Generative AI",6,"Unsanctioned"),
        ("copy.ai","Generative AI",6,"Unsanctioned"),
        ("writer.com","Generative AI",4,"Sanctioned"),
        ("grok.x.ai","Generative AI",7,"Unsanctioned"),
        ("mistral.ai","Generative AI",5,"Monitored"),
    ]
    path = os.path.join(folder, "ai_cloud_discovery.csv")
    with open(path,"w",newline="") as f:
        w = csv.writer(f)
        w.writerow(MDA_HEADERS["ai_cloud_discovery.csv"].split(","))
        for d, cat, risk, status in domains:
            for ym in MONTHS:
                up   = round(random.uniform(50, 4500), 1)
                down = round(random.uniform(20, 1800), 1)
                tx   = random.randint(150, 12000)
                users= random.randint(2, 80)
                w.writerow([d, cat, ym, risk, up, down, tx, users, status])

def write_mda_sessions(folder):
    apps = ["ChatGPT Enterprise","Claude for Work","Microsoft 365 Copilot",
            "GitHub Copilot","Perplexity Enterprise","Notion AI"]
    actions = ["FileUpload","FileDownload","SensitivePaste","PolicyMatch","SessionPolicyApplied"]
    policies = [("DLP-Confidential-Block","Block"),
                ("DLP-PII-Warn","Warn"),
                ("Allow-Sanctioned","Allow"),
                ("Block-PersonalEmail","Block"),
                ("Warn-LargeUpload","Warn")]
    countries = ["US","GB","DE","SG","AU","IE","FR"]
    path = os.path.join(folder, "ai_mda_sessions.csv")
    with open(path,"w",newline="") as f:
        w = csv.writer(f)
        w.writerow(MDA_HEADERS["ai_mda_sessions.csv"].split(","))
        for _ in range(800):
            ym = random.choice(MONTHS)
            day = random.randint(1,27); hr = random.randint(7,20)
            ts = f"{ym}-{day:02d}T{hr:02d}:00:00Z"
            pol_name, pol_act = random.choice(policies)
            w.writerow([ts, ym, random.choice(upns), random.choice(apps),
                        random.choice(actions), pol_name, pol_act,
                        f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}",
                        random.choice(countries),
                        random.randint(1,12)])

# -- Run --------------------------------------------------------------
print("Building sample_data_v26_no_mda/ ...")
write_copilot_prompts(NOMDA)
write_client_channel(NOMDA)
write_mda_stubs(NOMDA)

print("Building sample_data_v26_with_mda/ ...")
write_copilot_prompts(WITH)
write_client_channel(WITH)
write_mda_appgov(WITH)
write_mda_cloud_discovery(WITH)
write_mda_sessions(WITH)

print("\nFolder contents:")
for d in (NOMDA, WITH):
    print(f"\n{d}:")
    for fn in sorted(os.listdir(d)):
        sz = os.path.getsize(os.path.join(d, fn))
        print(f"  {fn:34s}  {sz:>8,} B")
