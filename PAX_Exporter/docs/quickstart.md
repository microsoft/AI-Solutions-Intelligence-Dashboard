# Quickstart — your first export, step by step

This is the long-form version of the [README step-by-step workflow](../README.md#run-it--step-by-step). It assumes nothing and walks you through a full first run.

---

## Step 1 — Check your prerequisites

**PowerShell 7 or newer.** Open a terminal and run:

```powershell
$PSVersionTable.PSVersion
```

You need `Major` to be `7` or higher. If it isn't, install [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) first.

**Graph permissions.** A full 13-file export requires
**`ThreatHunting.Read.All`**, **`User.Read.All`**,
**`LicenseAssignment.Read.All`**, and **`AuditLog.Read.All`**, all
admin-consented. The documented app-only path uses Application permissions, whose
tenant-wide consent must be granted by a Privileged Role Administrator or Global
Administrator. The interactive Purview collector also needs **View-Only Audit
Logs** or **Audit Logs** for `Search-UnifiedAuditLog`. If you don't have these
yet, see [authentication.md](authentication.md).

---

## Step 2 — Get your credentials ready

Pick one path:

- **Access token (fastest):** grab a bearer token and keep it handy. Tokens expire after about an hour. How to get one is in [authentication.md](authentication.md#path-a--bring-your-own-access-token).
- **App registration (repeatable):** register an app, grant all four Graph permissions listed above, and create a client secret. Steps in [authentication.md](authentication.md#path-b--app-registration-client-credentials).

> Never paste a token or secret into a file. You will pass it on the command line at runtime.

Before running the full export, establish the interactive Exchange Online/Purview session used for Copilot audit data:

```powershell
Connect-ExchangeOnline
```

---

## Step 3 — Pick (or edit) a KQL preset

A **preset** is a saved KQL query with a `{TIMEFILTER}` placeholder where the time range goes. This repo ships one ready to use:

```
presets/CloudAppEvents_ai_activity_sessions.kql
```

Load it into a variable:

```powershell
$kql = Get-Content .\presets\CloudAppEvents_ai_activity_sessions.kql -Raw
```

Want to change what it returns (columns, filters)? Edit the `.kql` file — just **keep the `{TIMEFILTER}` token** and don't add your own time predicate. Details in [presets-and-kql.md](presets-and-kql.md).

---

## Step 4 — Run the export

Replace every `<PLACEHOLDER>` with your real value:

<small style='color:#666'>Tip: copy the single-line command below, paste it into PowerShell, then press Enter.</small>

**Using an access token:**
```powershell
.\Invoke-AISolutionsExport.ps1 -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory 'C:\AI_Usage_Data' -AccessToken '<YOUR_ACCESS_TOKEN>' -IncludeSectionA
```

**Using an app registration** — run Command 1 first (it will prompt you to type your secret), then Command 2:
```powershell
$secret = Read-Host -AsSecureString 'Client secret'
.\Invoke-AISolutionsExport.ps1 -StartDate '<START_DATE>' -EndDate '<END_DATE>' -OutputDirectory 'C:\AI_Usage_Data' -TenantId '<TENANT_ID>' -ClientId '<CLIENT_ID>' -ClientSecret $secret -IncludeSectionA
```

If the tenant does not have Defender for Cloud Apps or `CloudAppEvents`, add
`-SkipActivitySessions` to either command. This writes the required
header-only activity file and continues with the other Advanced Hunting
presets.

| Placeholder | What to put there |
|---|---|
| `<START_DATE>` | Start of your date window, e.g. `2026-01-01` |
| `<END_DATE>` | End of your date window (exclusive), e.g. `2026-07-01` |
| `C:\AI_Usage_Data` | Folder where you want the 13 CSV files saved |
| `<YOUR_ACCESS_TOKEN>` | The token you copied from Graph Explorer or Azure CLI |
| `<TENANT_ID>` | Entra admin center → your app → **Directory (tenant) ID** |
| `<CLIENT_ID>` | Entra admin center → your app → **Application (client) ID** |

`-EndDate` is **exclusive** — `2026-06-08` means "up to but not including midnight on the 8th."

---

## Step 5 — Read the progress output

As it runs you'll see colored status lines:

| Line | Meaning |
| --- | --- |
| `[ACCEPT] ... : N rows` | This window returned under the configured local threshold and its rows were kept. |
| `[SUBDIVIDE] ... split into K` | This window reached the local threshold and was split into smaller windows. |
| `[RETRY] HTTP 429 ...` | The API throttled; the tool is waiting and will retry automatically. |
| `[SMART SUBDIVISION] ...` | The tool measured data density and chose a split factor. |

This is normal. The default 10,000-row value is a conservative local partition
threshold, below the currently documented service result quota. Current Advanced
Hunting limits also include a 64-MB result-size ceiling, so review any
completeness warning.

---

## Step 6 — Verify the row count

When it finishes, count the rows in your CSV (the `-1` drops the header):

```powershell
(Import-Csv '<OUTPUT.csv>').Count
```

Sanity check: if any single window warned that it "still returned >= RowCap" at
the 1-minute floor, review that period for completeness and consider a more
selective query - see [troubleshooting.md](troubleshooting.md).

---

## Step 7 — Open the CSV

The file is UTF-8 with a header row. Open it in Excel, import it into your dashboard pipeline, or inspect it in PowerShell:

```powershell
Import-Csv '<OUTPUT.csv>' | Select-Object -First 5 | Format-Table
```

> **Handle with care.** This file contains sensitive audit data (user identifiers, IPs, and more). Review the [Sensitive Data Warning](../README.md#sensitive-data-warning) before sharing or storing it.

---

## What next?

- Learn *why* it slices time the way it does: [how-it-works.md](how-it-works.md)
- See every parameter: [parameters.md](parameters.md)
- Write your own query: [presets-and-kql.md](presets-and-kql.md)
