# PAX Exporter â€” get all 12 AI Solutions dashboard files

This tool collects the **twelve CSV files** the AI Solutions Intelligence Dashboard (`.pbit`) needs, straight from your Microsoft 365 tenant. It is the automated path for organizations with **more than ~10,000 rows** of AI activity (the manual portal-export path hits a 10,000-row wall).

> **TL;DR:** run three short PowerShell commands, point the dashboard at the output folder, done. No coding required.

> **Just exploring?** You don't need this tool to try the dashboard â€” the repo ships sample data. See the top-level [DATA_SETUP_START_HERE.md](../DATA_SETUP_START_HERE.md).

---

## What this produces

The dashboard imports twelve CSVs. Here is exactly where each one comes from:

| # | File | Produced by | What it needs |
| --- | --- | --- | --- |
| 1 | EntraUsers.csv | `Collect-AISolutionsGraph.ps1` | User.Read.All, Directory.Read.All |
| 2 | ai_copilot_usage_graph.csv | `Collect-AICopilotUsage.ps1` | Exchange Online sign-in (see prereqs) |
| 3 | ai_activity_sessions.csv | `Invoke-AISolutionsExport.ps1` | ThreatHunting.Read.All |
| 4 | ai_oauth_consents.csv | `Collect-AISolutionsGraph.ps1` | AuditLog.Read.All, Application.Read.All |
| 5 | ai_sso_signins.csv | `Collect-AISolutionsGraph.ps1` | AuditLog.Read.All, Directory.Read.All |
| 6 | ai_file_proximity.csv | `Invoke-AISolutionsExport.ps1` | ThreatHunting.Read.All |
| 7 | ai_offhours_geo.csv | `Invoke-AISolutionsExport.ps1` | ThreatHunting.Read.All |
| 8 | ai_solutions_catalog.csv | `Collect-AISolutionsGraph.ps1` (auto-seeded) | nothing â€” review & customize |
| 9 | ai_client_channel.csv | `Invoke-AISolutionsExport.ps1` | ThreatHunting.Read.All |
| 10 | ai_appgov_alerts.csv | `Invoke-AISolutionsExport.ps1` (placeholder) | Microsoft Defender for Cloud Apps â€” optional |
| 11 | ai_cloud_discovery.csv | `Invoke-AISolutionsExport.ps1` (placeholder) | Microsoft Defender for Cloud Apps â€” optional |
| 12 | ai_mda_sessions.csv | `Invoke-AISolutionsExport.ps1` (placeholder) | Microsoft Defender for Cloud Apps â€” optional |

**Files 10â€“12** are written as **empty placeholder files** (header row only) so the dashboard always opens, even if you don't have Microsoft Defender for Cloud Apps (MDA). If you *do* have MDA data, drop your real CSVs into the output folder with those exact names and the tool will leave them untouched. See [How the MDA files work](#how-the-mda-files-work) below.

**File 8** (`ai_solutions_catalog.csv`) is your list of known AI tools. The tool writes a ready-to-use starter version for you â€” you can edit it. See [The AI solutions catalog](#the-ai-solutions-catalog).

---

## Before you start (prerequisites)

Work through this list once. It takes a few minutes.

### 1. PowerShell 7 or newer

Open PowerShell and check your version:

```powershell
$PSVersionTable.PSVersion
```

`Major` must be `7` or higher. If not, install [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell), then close and reopen your terminal.

### 2. One module (only for the Copilot usage file)

Two of the three scripts use built-in commands and need **no** modules. The Copilot usage script (file #2) reads Microsoft Purview audit data and needs one module:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

If asked to trust the PSGallery repository, answer **Y**. You only do this once.

### 3. Permissions

The identity you sign in with must have these **Microsoft Graph** permissions, all **admin-consented**:

- `ThreatHunting.Read.All` â€” files 3, 6, 7, 9 (Defender Advanced Hunting)
- `User.Read.All` and `Directory.Read.All` â€” file 1 (users)
- `AuditLog.Read.All` and `Application.Read.All` â€” files 4 and 5 (consents, sign-ins)

For file #2 (Copilot usage) you also need an account that can run Exchange Online audit searches (Purview Audit / `Search-UnifiedAuditLog`).

If you can't grant these yourself, send the list to your Microsoft 365 administrator.

### 4. How you'll sign in (pick one)

You prove who you are to Microsoft Graph one of two ways:

- **Access token** â€” fastest to try. You paste a bearer token on the command line. Tokens expire after about an hour.
- **App registration (recommended for a full run)** â€” register an app once, grant the permissions above, create a client secret. Best for repeatable runs and long windows.

Full walk-throughs for both are in [docs/authentication.md](docs/authentication.md).

> **Never** paste a token or secret into a file. You pass it on the command line at runtime only. Nothing is written to disk or logged.

---

## Run it â€” step by step

You'll run three scripts into the **same output folder**. Together they produce all twelve files.

### Step 1 â€” Open PowerShell 7 in this folder

```powershell
cd "PAX_Exporter"
```

(Use the full path to wherever you cloned the repo, ending in `\PAX_Exporter`.)

### Step 2 â€” Pick your date window

Decide the start and end of the period you want to report on, for example the last six months. Dates are written `YYYY-MM-DD`. The end date is **exclusive** (not included).

### Step 3 â€” Get your Graph credentials ready

Follow [docs/authentication.md](docs/authentication.md) to either grab an **access token** or set up an **app registration**. Keep the values handy for the commands below. The examples use `<PLACEHOLDERS>` â€” replace them with your real values.

### Step 4 â€” Files 3, 6, 7, 9 (+ the 3 placeholders): Defender Advanced Hunting

Using an access token:

```powershell
.\Invoke-AISolutionsExport.ps1 -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory '.\dashboard_data' -AccessToken '<YOUR_ACCESS_TOKEN>'
```

Or using an app registration:

```powershell
$secret = Read-Host -AsSecureString 'Client secret'
.\Invoke-AISolutionsExport.ps1 -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory '.\dashboard_data' -TenantId '<TENANT_ID>' -ClientId '<CLIENT_ID>' -ClientSecret $secret
```

This writes the four Defender files plus the three MDA placeholder files into `.\dashboard_data`. You'll see progress as each time window is queried.

### Step 5 â€” Files 1, 4, 5, 8: Microsoft Graph

Same folder, same credentials:

```powershell
.\Collect-AISolutionsGraph.ps1 -OutputDirectory '.\dashboard_data' -AccessToken '<YOUR_ACCESS_TOKEN>'
```

(Swap in `-TenantId / -ClientId / -ClientSecret` if you're using an app registration, exactly like Step 4.)

This writes `EntraUsers.csv`, `ai_oauth_consents.csv`, `ai_sso_signins.csv`, and â€” if one isn't already there â€” a starter `ai_solutions_catalog.csv`.

### Step 6 â€” File 2: Copilot usage (Microsoft Purview)

This one signs in to Exchange Online interactively:

```powershell
Connect-ExchangeOnline
.\Collect-AICopilotUsage.ps1 -OutputDirectory '.\dashboard_data'
```

A sign-in window appears; complete it. The script then writes `ai_copilot_usage_graph.csv`.

### Step 7 â€” Review the AI solutions catalog

Open `.\dashboard_data\ai_solutions_catalog.csv` and adjust it to your organization (see the next section). If you edit it in Excel, use **File â†’ Save As â†’ CSV UTF-8** to keep it a plain CSV.

### Step 8 â€” Open the dashboard

Open the dashboard `.pbit` in Power BI Desktop and point it at your `dashboard_data` folder. All twelve files are there.

> **Tip:** if a file comes back empty because there was no matching activity in your window, that's expected â€” the dashboard still loads. Choose a window you know has AI activity for the richest results.

---

## The AI solutions catalog

`ai_solutions_catalog.csv` is the one file that describes *your* AI landscape â€” which tools are approved and which are shadow IT. Step 5 writes a starter version with 20 common tools so you're never staring at a blank file.

Its columns are:

```
AISolution,Category,Vendor,RiskTier,DefaultDataHandling,SolutionGroup
```

- **RiskTier** is one of `Sanctioned`, `Conditional`, `Unsanctioned`. The dashboard uses this to split tools into **Licensed** vs **Shadow** AI.
- **SolutionGroup** is a display label such as `Microsoft Copilot`, `Licensed Third-Party`, or `Shadow AI`.

Add, remove, or re-classify rows to match your organization, then save it back as CSV. The tool **never overwrites** a catalog that already exists, so your edits are safe on future runs.

---

## How the MDA files work

`ai_appgov_alerts.csv`, `ai_cloud_discovery.csv`, and `ai_mda_sessions.csv` come from **Microsoft Defender for Cloud Apps (MDA)**, which is a separate product from Defender Advanced Hunting. This tool cannot pull them for you, so it writes **empty placeholder files** (just the header row) so the dashboard still opens.

If you have MDA, export those three reports yourself and save them into your output folder using those exact filenames **before** you run Step 4 â€” the tool will detect them and leave them untouched. If you don't have MDA, leave the placeholders as-is; the dashboard degrades gracefully.

---

## âš ï¸ Sensitive data warning

**The CSVs this tool produces contain raw audit data** â€” user identifiers, IP addresses, geolocation, user agents, and resource names, depending on the query.

- Treat all exported output as **Highly Confidential**.
- **You are responsible** for storing, transmitting, and disposing of this data securely and in line with your organization's policies and applicable law.
- **Never commit exported CSVs** or credentials to source control (see [.gitignore](.gitignore)).
- **Never paste tokens or secrets into files** â€” pass them at runtime only.

See [SECURITY.md](SECURITY.md) for responsible-use guidance.

---

## Advanced â€” run a single Defender query yourself

Under the hood, the four Defender files are produced by `Export-DefenderAdvancedHunting.ps1`, which solves the **10,000-row problem**.

> Microsoft Defender Advanced Hunting returns a **hard maximum of 10,000 rows per query** with no paging token â€” extra rows are silently dropped. This exporter defeats that with **adaptive time-slicing**: it splits your date range into windows, and any window that comes back full (at the cap) is automatically subdivided until every piece is under the cap. All pieces merge into one complete CSV, with no duplicates (each window is a half-open interval).

You normally don't need to call it directly â€” `Invoke-AISolutionsExport.ps1` runs it for all four presets with the right settings. But if you want to run one query yourself:

```powershell
$kql = Get-Content .\presets\CloudAppEvents_ai_activity_sessions.kql -Raw
.\Export-DefenderAdvancedHunting.ps1 -Query $kql -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputPath '.\ai_activity_sessions.csv' -AccessToken '<YOUR_ACCESS_TOKEN>'
```

More detail:

| Page | What it covers |
| --- | --- |
| [docs/quickstart.md](docs/quickstart.md) | The long, step-by-step single-query first run |
| [docs/authentication.md](docs/authentication.md) | Access token vs. app registration |
| [docs/how-it-works.md](docs/how-it-works.md) | The time-slicing algorithm + a worked example |
| [docs/parameters.md](docs/parameters.md) | Full parameter reference |
| [docs/presets-and-kql.md](docs/presets-and-kql.md) | Using and editing the KQL presets |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Fixes for common errors |

---

## Repository layout

```
PAX_Exporter/
â”œâ”€â”€ README.md                          â† you are here
â”œâ”€â”€ Invoke-AISolutionsExport.ps1       â† Defender files 3,6,7,9 + MDA placeholders 10â€“12
â”œâ”€â”€ Collect-AISolutionsGraph.ps1       â† Graph files 1,4,5 + catalog seed 8
â”œâ”€â”€ Collect-AICopilotUsage.ps1         â† Purview file 2 (Copilot usage)
â”œâ”€â”€ Export-DefenderAdvancedHunting.ps1 â† low-level single-query exporter (called by the orchestrator)
â”œâ”€â”€ Invoke-SmokeTest.ps1               â† validation harness (Defender path)
â”œâ”€â”€ Invoke-FullExportSmokeTest.ps1     â† validation harness (all 12 files)
â”œâ”€â”€ LICENSE                            â† MIT
â”œâ”€â”€ SECURITY.md                        â† reporting + data-handling
â”œâ”€â”€ .gitignore                         â† keeps exported data/secrets out of git
â”œâ”€â”€ docs/
â”‚   â”œâ”€â”€ quickstart.md
â”‚   â”œâ”€â”€ authentication.md
â”‚   â”œâ”€â”€ how-it-works.md
â”‚   â”œâ”€â”€ parameters.md
â”‚   â”œâ”€â”€ presets-and-kql.md
â”‚   â””â”€â”€ troubleshooting.md
â”œâ”€â”€ presets/
â”‚   â”œâ”€â”€ AADSignInEventsBeta_ai_offhours_geo.kql
â”‚   â”œâ”€â”€ CloudAppEvents_ai_activity_sessions.kql
â”‚   â”œâ”€â”€ DeviceNetworkEvents_ai_client_channel.kql
â”‚   â””â”€â”€ DeviceNetworkEvents_ai_file_proximity.kql
â””â”€â”€ Tests/
```

---

## License & attribution

Licensed under the [MIT License](LICENSE) â€” Copyright (c) Microsoft Corporation.

Built on the time-slicing approach from the Microsoft PAX project (MIT).

