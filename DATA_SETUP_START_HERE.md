# Get Your Data — Start Here 🟢

A friendly, step-by-step guide to collecting the data the **AI Solutions Intelligence Dashboard** needs — written for people who are **not** IT experts. No prior scripting experience required.

By the end you'll have **12 CSV files** in one folder and an open Power BI report showing your organization's AI usage.

> **Two detailed guides already exist** if you want the deep version:
> - Manual, click-by-click: [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md)
> - Automated exporter: [PAX_Exporter/README.md](PAX_Exporter/README.md)
>
> This page is the gentle overview that ties them together. Start here.

---

## Choose your method

There are two ways to collect the data. Both produce the **same 12 CSV files** and open the **same** report. Pick **one** option below and follow it from top to bottom — every step you need is inside that option, so you never have to jump back and forth.

- **Option 1 — Manual (copy & paste)** — best for organizations under ~10,000 users or a one-time pull. Mostly copy-paste from the Defender portal; a few files need PowerShell.
- **Option 2 — Automated exporter (run a script)** — best for 10,000+ users or repeat pulls. A little scripting; handles Defender's 10,000-row limit for you.

> Not sure? Pick Option 1.

Go to [Option 1](#option-1--manual-step-by-step) · Go to [Option 2](#option-2--automated-step-by-step)

> **Heads-up on wording:** the detailed guide [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) uses **"Path A / Path B"** to mean something different — whether your tenant has **MDA** (Microsoft Defender for Cloud Apps). That is a separate choice from **Option 1 vs Option 2** here.

---

## Option 1 — Manual (step by step)

Follow these steps in order. The full click-by-click detail (with every query) is in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) and the query pack [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql).

> **Good news:** most of this option is just copy-paste from the Defender portal — no tools needed. Only the Microsoft Graph files (Step 4) need PowerShell 7, and you'll install it right before that step.

### Step 1 — Make one folder for your data

Create a single, empty folder to hold all 12 CSV files. For example:
```
C:\AI_Usage_Data\
```
Remember this path — you'll type it into the report at the end. **Keep the trailing backslash.**

### Step 2 — Six files from Microsoft Defender (copy & paste queries)
For each of the six Defender queries (no PowerShell needed for these — they come straight from the portal):
1. Go to **https://security.microsoft.com**
2. In the left menu, open **Hunting → Advanced Hunting**
3. Click **+ New query**
4. Open [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql), copy one query, and paste it in
5. Click **Run query**
6. Click **Export → Export to CSV**
7. **Rename** the downloaded file to the exact name listed for that query (e.g. `ai_activity_sessions.csv`) and move it into your data folder

> **If you see "result set size exceeded the allowed limit":** your query returned too much data for the portal. Near the top of the query, change the time window — for example change `ago(180d)` (or `ago(90d)`) to `ago(30d)` or `ago(7d)` — and Run again. For a full pull, use the **Run query as a search job** button shown in the error.

> **If you see "Failed to resolve table ...":** that data table isn't available in your tenant's license (common in smaller or trial tenants). It's safe to **skip that one file** — the report still opens. See the stub-file note in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md).

> **If you see "No results found in the specified time frame":** that's **fine** — the query ran correctly, there just wasn't matching activity. Save it as an empty (header-only) file or skip it.

### Which AI tools does it collect?

By default the exporter looks for 60+ of the most common AI tools (Microsoft 365
Copilot, ChatGPT, Claude, Gemini, GitHub Copilot, Perplexity, and many more).

Want to add your own or narrow the list? It is a quick edit — open the preset
files in the `PAX_Exporter/presets` folder and change the list at the top marked
`EDIT HERE`. Step-by-step instructions are in
`PAX_Exporter/docs/presets-and-kql.md` under "Customize which AI tools are
collected."

### Step 3 — Install PowerShell 7

The next five files come from Microsoft Graph, which needs **PowerShell 7** (this is newer than the "Windows PowerShell" that ships with Windows). The Defender files above did not need it. Installing it is quick — pick **one** option:

**Option A — Microsoft Store (easiest):**
1. Open the **Microsoft Store** app.
2. Search for **PowerShell**.
3. Click the one published by **Microsoft** and press **Get / Install**.

**Option B — One command (if you have `winget`):**
```powershell
winget install --id Microsoft.PowerShell --source winget
```

**Option C — Download the installer:**
1. Go to the official install page: https://aka.ms/powershell-release?tag=stable
2. Download the **Windows x64 .msi** installer.
3. Double-click it and click **Next** through the wizard.

**Now confirm it worked:**
1. Press the **Start** menu and type **PowerShell 7**, then open the app named **PowerShell 7 (x64)**.
2. Paste this and press Enter:
   ```powershell
   $PSVersionTable.PSVersion
   ```
3. You should see a version starting with **7** (e.g. `7.4.x`). If you do, you're ready. ✅

> From here on, always use the **PowerShell 7** window (the one you just opened), not the older blue "Windows PowerShell".

### Step 4 — Five files from Microsoft Graph (PowerShell 7)
These come from your **PowerShell 7** window. The exact commands are in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) (sections A1–A5). They cover your user list, Copilot usage, app consents, and sign-ins.

### Step 5 — One file you fill in by hand
`ai_solutions_catalog.csv` is a small reference list of AI tools. A ready-to-use starter version is in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) — copy it into your data folder and adjust for your organization.

### Step 6 — Open the dashboard

1. Make sure Power BI Desktop is installed (get it free from the Microsoft Store).
2. Double-click the report template: **AI Solutions Unified May 4th v5.pbit** (in this folder).
3. When it asks for **AI_Data_Folder_Path**, type the folder from Step 1 **with a trailing slash**, for example:
   ```
   C:\AI_Usage_Data\
   ```
4. Click **Load**. Power BI reads your 12 CSV files and builds the report. 🎉

> To refresh later with new data, replace the CSV files in the folder and click **Refresh** in Power BI Desktop.

---

## Option 2 — Automated (step by step)

Follow these steps in order. This path runs scripts that pull everything for you, including automatically handling Defender's 10,000-row limit. Full detail is in [PAX_Exporter/README.md](PAX_Exporter/README.md).

### Step 1 — Install PowerShell 7

The exporter scripts run in **PowerShell 7** (this is newer than the "Windows PowerShell" that ships with Windows). It's the same installer as Option 1 — pick **one** option:

**Option A — Microsoft Store (easiest):**
1. Open the **Microsoft Store** app.
2. Search for **PowerShell**.
3. Click the one published by **Microsoft** and press **Get / Install**.

**Option B — One command (if you have `winget`):**
```powershell
winget install --id Microsoft.PowerShell --source winget
```

**Option C — Download the installer:**
1. Go to the official install page: https://aka.ms/powershell-release?tag=stable
2. Download the **Windows x64 .msi** installer.
3. Double-click it and click **Next** through the wizard.

**Now confirm it worked:**
1. Press the **Start** menu and type **PowerShell 7**, then open the app named **PowerShell 7 (x64)**.
2. Paste this and press Enter:
   ```powershell
   $PSVersionTable.PSVersion
   ```
3. You should see a version starting with **7** (e.g. `7.4.x`). If you do, you're ready. ✅

> From here on, always use the **PowerShell 7** window (the one you just opened), not the older blue "Windows PowerShell".

### Step 2 — Make one folder for your data

Create a single, empty folder to hold all 12 CSV files. For example:
```
C:\AI_Usage_Data\
```
Remember this path — you'll type it into the report at the end. **Keep the trailing backslash.**

### Step 3 — Get permission to read the data
The scripts sign in to Microsoft Graph and need these permissions **granted and admin-consented** by your tenant admin:
- `ThreatHunting.Read.All` (for the Defender data)
- `User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`, `Application.Read.All` (for the Graph data)

> If a run stops with **HTTP 403**, it means these permissions haven't been granted yet — send the list above to your IT/security admin and ask them to consent.

### Step 4 — Sign in and get an access token
The most reliable option for repeat runs is an **app registration** (your admin creates one and gives you a Tenant ID, Client ID, and Client Secret). See [PAX_Exporter/docs/authentication.md](PAX_Exporter/docs/authentication.md) for both options explained simply.

### Step 5 — Run the two scripts
In your **PowerShell 7** window, change into the exporter folder, then run the two collectors (replace the `<PLACEHOLDERS>`; your data folder is the one from Step 2):

```powershell
cd "PAX_Exporter"
```
```powershell
.\Invoke-AISolutionsExport.ps1 -TenantId <TENANT_ID> -ClientId <CLIENT_ID> -ClientSecret (Read-Host -AsSecureString 'Client secret') -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory 'C:\AI_Usage_Data'
```
```powershell
.\Collect-AISolutionsGraph.ps1 -TenantId <TENANT_ID> -ClientId <CLIENT_ID> -ClientSecret (Read-Host -AsSecureString 'Client secret') -OutputDirectory 'C:\AI_Usage_Data'
```

The first script writes the Defender-based files (plus small placeholder files for anything your tenant doesn't have); the second writes the Microsoft Graph files. When both finish, all 12 files are in your data folder.

> **Never type your secret or token directly into a file.** The `Read-Host -AsSecureString` prompt above keeps it out of scripts and logs.

### Step 6 — Open the dashboard

1. Make sure Power BI Desktop is installed (get it free from the Microsoft Store).
2. Double-click the report template: **AI Solutions Unified May 4th v5.pbit** (in this folder).
3. When it asks for **AI_Data_Folder_Path**, type the folder from Step 2 **with a trailing slash**, for example:
   ```
   C:\AI_Usage_Data\
   ```
4. Click **Load**. Power BI reads your 12 CSV files and builds the report. 🎉

> To refresh later with new data, replace the CSV files in the folder and click **Refresh** in Power BI Desktop.

---

## Quick help

| You saw... | What it means | What to do |
|---|---|---|
| "result set size exceeded the allowed limit" | Too much data for one screen | Shrink the time window (e.g. `ago(7d)`) or use **Run query as a search job** |
| "Failed to resolve table ..." | That table/license isn't in your tenant | Skip that file — the report still opens |
| "No results found in the specified time frame" | Query ran fine, no matching activity | Save an empty header-only file or skip it |
| **HTTP 403** when running a script | Missing admin-consented permissions | Send the Option 2 → Step 3 permission list to your admin |
| Report can't find files | Wrong folder path | Re-enter the folder path with a trailing slash |

---

*Need the fully detailed versions? Manual: [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) · Automated: [PAX_Exporter/README.md](PAX_Exporter/README.md)*
