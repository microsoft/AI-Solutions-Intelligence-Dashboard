# Defender Advanced Hunting Exporter

Export **every** row from a Microsoft Defender **Advanced Hunting** (KQL) query — even when the result set is far larger than the API will hand back in one call.

> **TL;DR:** exports ALL Defender Advanced Hunting rows past the 10,000-row cap.

---

## The 10,000-row problem (and how this fixes it)

> Microsoft Defender Advanced Hunting returns a **hard maximum of 10,000 rows per query** and gives you **no paging token** to fetch the rest. If your query matches more than 10,000 rows, the extra rows are silently dropped.
>
> This tool defeats that wall with **adaptive time-slicing**: it splits your time range into smaller windows, and any window that comes back "full" (at the cap) is automatically subdivided into even smaller windows until every piece returns under 10,000 rows. All the pieces are then merged into one complete CSV.

You write your KQL once. The tool handles the slicing, retrying, and merging for you.

---

## Contents

| Page | What it covers |
| --- | --- |
| [Quickstart (5 minutes)](#quickstart-5-minutes) | Your first export, start to finish |
| [Which path is for me?](#which-path-is-for-me) | Pick how you authenticate |
| [How it works](#how-it-works) | The time-slicing idea in plain language |
| [Parameters at a glance](#parameters-at-a-glance) | The knobs you'll actually use |
| [docs/quickstart.md](docs/quickstart.md) | The long, step-by-step first run |
| [docs/authentication.md](docs/authentication.md) | Access token vs. app registration |
| [docs/how-it-works.md](docs/how-it-works.md) | The subdivision algorithm + a worked example |
| [docs/parameters.md](docs/parameters.md) | Full parameter reference |
| [docs/presets-and-kql.md](docs/presets-and-kql.md) | Using and writing KQL presets |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Fixes for common errors |

---

## Which path is for me?

You need a way to prove to Microsoft Graph who you are. Pick the row that matches what you already have:

| Your situation | Use these parameters | Notes |
| --- | --- | --- |
| **I already have an access token** | `-AccessToken <YOUR_ACCESS_TOKEN>` | Fastest. Tokens expire after ~1 hour. |
| **I have an app registration** | `-TenantId <TENANT_ID>` `-ClientId <CLIENT_ID>` `-ClientSecret <SECURE_SECRET>` | Best for repeatable/automated runs. |
| **I'm not sure** | — | Read [docs/authentication.md](docs/authentication.md) — it walks you through both. |

Either way, credentials are passed **at runtime only** and are never written to disk or logged.

---

## Quickstart (5 minutes)

**Prerequisites**

1. **PowerShell 7+** — check with `$PSVersionTable.PSVersion` (must be 7.0 or higher).
2. **Graph permission** `ThreatHunting.Read.All` on the identity you authenticate with.

**Run it**

From inside the `AI_Solutions_AH_Exporter` folder, paste this and replace the `<PLACEHOLDERS>`:

```powershell
# 1. Load the ready-made preset query
$kql = Get-Content .\presets\CloudAppEvents_ai_activity_sessions.kql -Raw

# 2. Export everything in your date range to a CSV
.\Export-DefenderAdvancedHunting.ps1 `
    -Query      $kql `
    -StartDate  '<START_DATE>' `   # e.g. 2026-06-01
    -EndDate    '<END_DATE>'   `   # e.g. 2026-06-08  (exclusive)
    -OutputPath '<OUTPUT.csv>' `   # e.g. .\ai_activity_sessions.csv
    -AccessToken '<YOUR_ACCESS_TOKEN>'
```

**What you'll see:** progress lines as each time window is queried — `[ACCEPT]` when a window is safely under the cap, `[SUBDIVIDE]` when a full window is split into smaller ones. When it finishes, your `<OUTPUT.csv>` contains the complete, merged result set (UTF-8, with a header row).

> New here? The [long-form quickstart](docs/quickstart.md) explains each step, how to get a token, and how to verify your row count.

---

## How it works

- The date range is split into an initial queue of **half-open time windows** `[start, end)`.
- Each window is queried. If it returns **at or above the row cap (10,000)** it's assumed to be truncated, so it's **subdivided** into smaller windows and re-queued.
- Subdivision is **smart**: instead of blindly halving, the tool measures how much time the full batch actually covered, estimates rows-per-hour, and picks a split factor aimed at **~8,000 rows per window**. A **1-minute floor** stops it from subdividing forever.
- Because every window is half-open and contiguous, **no row is counted twice** — no deduplication needed.

Full explanation with a worked example: [docs/how-it-works.md](docs/how-it-works.md).

---

## Parameters at a glance

The six you'll reach for most often. Full list in [docs/parameters.md](docs/parameters.md).

| Parameter | Required | Default | Purpose |
| --- | --- | --- | --- |
| `-Query` | Yes | — | Your KQL. Must contain the `{TIMEFILTER}` token. |
| `-StartDate` | Yes | — | Inclusive start of the export range. |
| `-EndDate` | Yes | — | Exclusive end of the export range. |
| `-OutputPath` | Yes | — | Path for the merged CSV output. |
| `-AccessToken` | No | — | Pre-acquired Graph bearer token (auth path A). |
| `-TimeColumn` | No | `Timestamp` | KQL column used for time filtering/subdivision. |

---

## ⚠️ Sensitive Data Warning

**The CSVs produced by this tool contain raw audit data.** Depending on your query, that includes **user identifiers** (object IDs, display names), **IP addresses**, **geolocation**, **user agents**, and **resource/object names**.

- Treat all exported output as **Highly Confidential**.
- **You (the customer) are responsible** for storing, transmitting, and disposing of this data securely and in line with your organization's policies and applicable law.
- **Never commit exported CSVs** or credentials to source control (see [.gitignore](.gitignore)).
- **Never paste tokens or secrets into files** — pass them at runtime only.

See [SECURITY.md](SECURITY.md) for responsible-use guidance.

---

## Repository layout

```
AI_Solutions_AH_Exporter/
├── README.md                          ← you are here
├── Export-DefenderAdvancedHunting.ps1 ← the exporter script
├── LICENSE                            ← MIT
├── SECURITY.md                        ← reporting + data-handling
├── .gitignore                         ← keeps exported data/secrets out of git
├── docs/
│   ├── quickstart.md                  ← step-by-step first run
│   ├── authentication.md              ← the two auth paths
│   ├── how-it-works.md                ← time-slicing explained
│   ├── parameters.md                  ← full parameter reference
│   ├── presets-and-kql.md             ← using & writing KQL presets
│   └── troubleshooting.md             ← common errors & fixes
├── presets/
│   └── CloudAppEvents_ai_activity_sessions.kql
└── Tests/
    └── Export-DefenderAdvancedHunting.Tests.ps1
```

---

## License & attribution

Licensed under the [MIT License](LICENSE) — Copyright (c) Microsoft Corporation.

Built on the time-slicing approach from the Microsoft PAX project (MIT).
