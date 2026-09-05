# Get Your Data — Start Here 🟢

A friendly, step-by-step guide to collecting the data the **AI Solutions Intelligence Dashboard** needs — written for people who are **not** IT experts. No prior scripting experience required.

By the end you'll have **13 CSV files** in one folder and an open Power BI report showing your organization's AI usage.

> **Two detailed guides already exist** if you want the deep version:
> - Manual, click-by-click: [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md)
> - Automated exporter: [PAX_Exporter/README.md](PAX_Exporter/README.md)
>
> This page is the gentle overview that ties them together. Start here.

---

## Choose your method

There are two ways to collect the data. Both produce the **same 13 CSV files** and open the **same** report. Pick **one** option below and follow it from top to bottom — every step you need is inside that option, so you never have to jump back and forth.

- **Option 1 — Manual (copy & paste)** — best for a one-time pull when the expected event volume fits the portal export limits. Mostly copy-paste from the Defender portal; a few files need PowerShell.
- **Option 2 — Automated exporter (run a script)** — best for repeat or high-volume pulls. It conservatively partitions Advanced Hunting queries into smaller time windows and surfaces saturation warnings.

> Not sure? Pick Option 1.

Go to [Option 1](#option-1--manual-step-by-step) · Go to [Option 2](#option-2--automated-step-by-step)

> **Heads-up on wording:** the detailed guide [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) uses **"Path A / Path B"** to mean something different — whether your tenant has **MDA** (Microsoft Defender for Cloud Apps). That is a separate choice from **Option 1 vs Option 2** here.

---

## Option 1 — Manual (step by step)

Follow these steps in order. The full click-by-click detail (with every query) is in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) and the query pack [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql).

> **What to expect — this option has two parts:**
> - **Part 1 (Steps 2–3): portal exports and one catalog file.** Collect the Defender data available under your licenses and create exact header-only files for unavailable sources.
> - **Part 2 (Steps 4–5): PowerShell.** Collect Entra users, audit logs, and Purview Copilot interactions with the supplied collectors.
>
> You install PowerShell only when you reach Part 2 — Part 1 doesn't need it.

### Step 1 — Make one folder for your data

Create a single, empty folder to hold all 13 CSV files. For example:
```
C:\AI_Usage_Data\
```
Remember this path — you'll type it into the report at the end. **Keep the trailing backslash.**

---

**Part 1 — Portal exports and the catalog**

### Step 2 — Six files from Microsoft Defender (copy & paste queries)
For each of the six Defender queries (no PowerShell needed for these — they come straight from the portal):
1. Go to **https://security.microsoft.com**
2. In the left menu, open **Hunting → Advanced Hunting**
3. Click **+ New query**
4. Open [kql_queries_v22_E5V3.kql](kql_queries_v22_E5V3.kql), copy one query, and paste it in
5. Click **Run query**
6. Click **Export → Export to CSV**
7. **Rename** the downloaded file to the exact name listed for that query (e.g. `ai_activity_sessions.csv`) and move it into your data folder

> **If you see "result set size exceeded the allowed limit":** narrow the time range or use the PAX exporter, which partitions queries and detects saturated windows. Native Defender Advanced Hunting commonly retains about 30 days; a wider query cannot recover expired data.

> **If you see "Failed to resolve table ...":** that table isn't available under your tenant's licenses or connected products. Do not omit the file; create the exact header-only stub documented in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) so Power Query can refresh.

> **If you see "No results found in the specified time frame":** that's **fine** — the query ran correctly, there just wasn't matching activity. Save the exact header-only file so Power Query can refresh.

### Which AI tools does it collect?

By default the exporter looks for 60+ of the most common AI tools (Microsoft 365
Copilot, ChatGPT, Claude, Gemini, GitHub Copilot, Perplexity, and many more).

Want to add your own or narrow the list? It is a quick edit — open the preset
files in the `PAX_Exporter/presets` folder and change the list at the top marked
`EDIT HERE`. Step-by-step instructions are in
`PAX_Exporter/docs/presets-and-kql.md` under "Customize which AI tools are
collected."

### Step 3 — One file you fill in by hand
`ai_solutions_catalog.csv` is a small reference list of AI tools. A ready-to-use starter version is in [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) — copy it into your data folder and adjust for your organization. No tools needed — it's just a short list you edit.

---

**Part 2 — Files that need PowerShell**

### Step 4 — Install PowerShell 7

The remaining live files come from Microsoft Graph and Microsoft Purview, which are collected through **PowerShell 7** (newer than the Windows PowerShell included with Windows). Installing it is quick — pick **one** option:

**Option A — Microsoft Store (easiest):**
1. Open the **Microsoft Store** app.
2. Search for **PowerShell**.
3. Click the one published by **Microsoft** and press **Get / Install**.

**Option B — One command (if you have `winget`):**
```powershell
winget install --id Microsoft.PowerShell --source winget
```

**Option C — Download the installer:**
1. Go to the official [PowerShell installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).
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

**Optional install — the Microsoft Graph module**

The supplied `Collect-AISolutionsGraph.ps1` script uses Microsoft Graph REST and
does not require the Microsoft.Graph PowerShell module. Install the module only
if you plan to follow the manual `Connect-MgGraph` / `Get-MgUser` example in
`INSTRUCTIONS_v26.md`:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```
- If it asks to trust the **PSGallery** repository, type **Y** and press Enter.
- It takes a couple of minutes and only needs to be done **once**.

> `ai_copilot_usage_graph.csv` and `ai_copilot_surface_usage.csv` require Purview Audit and the Exchange module: `Install-Module ExchangeOnlineManagement -Scope CurrentUser`. The normalized surface file retains every workload Purview reports rather than limiting the dashboard to a fixed app list.

### Step 5 — Graph and Purview files (PowerShell 7)
Use `Collect-AISolutionsGraph.ps1` for Entra users, license SKU names, app consents, sign-ins, and the catalog seed. Use `Collect-AICopilotUsage.ps1` for both Purview Copilot files. The collector can return more than 50,000 records overall by adaptively splitting saturated date windows; it stops with an error rather than silently truncating if even a one-minute window reaches the service ceiling. The exact commands are in [PAX_Exporter/README.md](PAX_Exporter/README.md).

---

### Step 6 — Open the dashboard

1. Make sure Power BI Desktop is installed (get it free from the Microsoft Store).
2. Double-click **AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit**, the repository's only published template.
3. When it asks for **AI_Data_Folder_Path**, type the folder from Step 1, for example:
   ```
   C:\AI_Usage_Data
   ```
4. Click **Load**. Power BI reads your 13 CSV files and builds the report. 🎉

> To refresh later with new data, replace the CSV files in the folder and click **Refresh** in Power BI Desktop.

---

## Option 2 — Automated (step by step)

Follow these steps in order. This path runs scripts that produce the 13-file contract and conservatively partition Advanced Hunting requests. Current service quotas include result-count and result-size limits, so review any saturation warning before treating an export as complete. Full detail is in [PAX_Exporter/README.md](PAX_Exporter/README.md).

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
1. Go to the official [PowerShell installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).
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

Create a single, empty folder to hold all 13 CSV files. For example:
```
C:\AI_Usage_Data\
```
Remember this path — you'll type it into the report at the end. **Keep the trailing backslash.**

### Step 3 — Get permission to read the data
The scripts sign in to Microsoft Graph and need these permissions **granted and admin-consented** by your tenant admin:
- `ThreatHunting.Read.All` (for the Defender data)
- `User.Read.All`, `LicenseAssignment.Read.All`, `AuditLog.Read.All` (for the Graph data)

These are **Application permissions** for the documented app-only path. A
Privileged Role Administrator or Global Administrator must grant tenant-wide
admin consent. The interactive Copilot collector separately requires
`Search-UnifiedAuditLog` access: **View-Only Audit Logs** or **Audit Logs** in
Exchange Online. Purview portal search/export uses **Audit Reader** or **Audit
Manager**; eDiscovery roles alone are not sufficient.

> If a run stops with **HTTP 403**, verify both the app permission and admin-consent status. A 403 in the Purview step can instead mean the signed-in collector does not have the audit-log role.

### Step 4 — Sign in and get an access token
The most reliable option for repeat runs is an **app registration** (your admin creates one and gives you a Tenant ID, Client ID, and Client Secret). See [PAX_Exporter/docs/authentication.md](PAX_Exporter/docs/authentication.md) for both options explained simply.

### Step 5 — Run the exporter scripts (three scripts)
In your **PowerShell 7** window, change into the exporter folder, then run the three collector commands (replace the `<PLACEHOLDERS>`; your data folder is the one from Step 2):

<small style='color:#666'>Tip: copy each single-line command below, paste it into PowerShell, then press Enter. For the Copilot usage collect, run `Connect-ExchangeOnline` interactively before the Purview command.</small>

Open **PowerShell 7** and navigate to the `PAX_Exporter` folder using the **full path** to wherever you downloaded or cloned the repository:

```powershell
# Replace YourName and the folder path to match where you saved the repo
cd "C:\Users\YourName\Downloads\AI-Solutions-Intelligence-Dashboard\PAX_Exporter"
```

> When the command works, your prompt will end with `...\PAX_Exporter>`. If you see a *"Cannot find path"* error, the path doesn't match — check the folder name and location and try again.

```powershell
.\Invoke-AISolutionsExport.ps1 -TenantId <TENANT_ID> -ClientId <CLIENT_ID> -ClientSecret (Read-Host -AsSecureString 'Client secret') -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory 'C:\AI_Usage_Data'
```

If Defender for Cloud Apps or `CloudAppEvents` is unavailable, add
`-SkipActivitySessions` to that command. The script then creates the exact
header-only `ai_activity_sessions.csv` and continues with the other three
Advanced Hunting exports.

```powershell
.\Collect-AISolutionsGraph.ps1 -TenantId <TENANT_ID> -ClientId <CLIENT_ID> -ClientSecret (Read-Host -AsSecureString 'Client secret') -OutputDirectory 'C:\AI_Usage_Data'
```

```powershell
Connect-ExchangeOnline; .\Collect-AICopilotUsage.ps1 -OutputDirectory 'C:\AI_Usage_Data'
```

The first script writes four Defender-based files and three MDA placeholders.
With `-SkipActivitySessions`, one of those four is an exact header-only file and
the other three are queried normally. It fails loudly if any non-skipped
Advanced Hunting table is unavailable. The second and third scripts write the
Microsoft Graph and Purview files. Use the exact header-only stubs in
[INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) for other unavailable sources.

> **Never type your secret or token directly into a file.** The `Read-Host -AsSecureString` prompt above keeps it out of scripts and logs.

### Step 6 — Open the dashboard

1. Make sure Power BI Desktop is installed (get it free from the Microsoft Store).
2. Double-click **AI-Solutions-Intelligence-Dashboard V27 In Testing.pbit**, the repository's only published template.
3. When it asks for **AI_Data_Folder_Path**, type the folder from Step 2, for example:
   ```
   C:\AI_Usage_Data
   ```
4. Click **Load**. Power BI reads your 13 CSV files and builds the report. 🎉

> To refresh later with new data, replace the CSV files in the folder and click **Refresh** in Power BI Desktop.

---

## Quick help

| You saw... | What it means | What to do |
|---|---|---|
| "result set size exceeded the allowed limit" | Too much data for one screen | Shrink the time window (e.g. `ago(7d)`) or use **Run query as a search job** |
| "Failed to resolve table ..." | That table/license isn't in your tenant | Create the exact header-only stub; do not omit the file |
| "No results found in the specified time frame" | Query ran fine, no matching activity | Save the exact header-only file |
| **HTTP 403** when running a script | Missing admin-consented permissions | Send the Option 2 → Step 3 permission list to your admin |
| Report can't find files | Wrong folder path or missing CSV | Confirm the folder and CSV filename shown in the error |

---

## Before you interpret or share results

- `ai_offhours_geo.csv` requires Microsoft Entra ID P2, Advanced Hunting access,
  and retained `EntraIdSignInEvents` data.
- `CloudAppEvents` requires Defender for Cloud Apps data and the Microsoft 365
  activities connector; MDE Plan 2 alone does not provide it.
- Copilot values derived from Purview audit logs are directional and can differ
  from the official Microsoft 365 Copilot usage report.
- Risk scores, geo anomalies, file proximity, and estimated prompts are triage
  signals, not proof of misuse, disclosure, or data leakage.
- Exported CSVs and derived reports are not automatically labeled or encrypted.
  Apply your organization's access, retention, and sensitivity controls.
- For Power BI Service refresh, a local/UNC Folder source requires an on-premises
  gateway. Publishing does not convert `C:\AI_Usage_Data` into a
  SharePoint/OneDrive connector.

Read the complete [V27 interpretation and compliance guide](INTERPRETATION_GUIDE.md)
before operational use.

---

*Need the fully detailed versions? Manual: [INSTRUCTIONS_v26.md](INSTRUCTIONS_v26.md) · Automated: [PAX_Exporter/README.md](PAX_Exporter/README.md)*
