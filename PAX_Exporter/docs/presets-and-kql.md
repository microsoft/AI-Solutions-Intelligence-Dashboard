# Presets & writing your own KQL

## What a preset is

A **preset** is a saved Advanced Hunting KQL query stored as a `.kql` file under [`presets/`](../presets/). Presets exist so you don't have to rewrite the same query every time — load one, run the exporter, get a CSV.

The one thing that makes a query "exporter-ready" is a single token: **`{TIMEFILTER}`**.

---

## The `{TIMEFILTER}` token (required)

Your query must contain the literal text `{TIMEFILTER}` exactly where a time predicate belongs. For every time window it slices, the exporter replaces that token with:

```kusto
Timestamp >= datetime(<startISO>) and Timestamp < datetime(<endISO>)
```

(The column name comes from `-TimeColumn`, which defaults to `Timestamp`.)

**Rules:**

- Include `{TIMEFILTER}` exactly once, in a `where` clause.
- **Do not** add your own time predicate — let `{TIMEFILTER}` own the time range. A second time filter fights the slicing logic and can drop rows.
- If `{TIMEFILTER}` is missing, the tool refuses to run and tells you so.

---

## A bundled preset

### `CloudAppEvents_ai_activity_sessions.kql`

Feeds the dashboard artifact **`ai_activity_sessions.csv`**. It pulls Copilot/AI-related activity from the `CloudAppEvents` table:

```kusto
CloudAppEvents
| where {TIMEFILTER}
| where Application has_any ("Copilot", "Microsoft 365 Copilot", "AI")
| project
    Timestamp, ReportId, ActionType, Application,
    AccountObjectId, AccountDisplayName, UserAgent,
    IPAddress, CountryCode, ActivityType, ObjectName
| sort by Timestamp asc
```

Notice `{TIMEFILTER}` sits in the **first** `where`, and there is no other time filter.

Load and run it:

```powershell
$kql = Get-Content .\presets\CloudAppEvents_ai_activity_sessions.kql -Raw
.\Export-DefenderAdvancedHunting.ps1 -Query $kql `
    -StartDate '<START_DATE>' -EndDate '<END_DATE>' `
    -OutputPath '.\ai_activity_sessions.csv' `
    -AccessToken '<YOUR_ACCESS_TOKEN>'
```

---

## Which CSV does each preset feed?

The exporter supplies the Defender-sourced CSVs behind the **AI Solutions Intelligence Dashboard**:

| Dashboard CSV | Source table | Preset |
| --- | --- | --- |
| `ai_activity_sessions.csv` | `CloudAppEvents` (Defender for Cloud Apps) | `CloudAppEvents_ai_activity_sessions.kql` |
| `ai_file_proximity.csv` | `DeviceFileEvents` + `DeviceNetworkEvents` (MDE Plan 2) | `DeviceNetworkEvents_ai_file_proximity.kql` |
| `ai_offhours_geo.csv` | `EntraIdSignInEvents` | `EntraIdSignInEvents_ai_offhours_geo.kql` |
| `ai_client_channel.csv` | `DeviceNetworkEvents` (MDE Plan 2) | `DeviceNetworkEvents_ai_client_channel.kql` |

All four presets are bundled. Availability still depends on the listed product and table being present in your tenant.

---

## Customize which AI tools are collected

You decide exactly which AI tools the exporter pulls. There are two short lists,
and both sit at the very top of the preset files under a banner that says
`EDIT HERE`.

**By app name — `AIAppNames`** (sign-in / cloud-app presets):
- `presets/CloudAppEvents_ai_activity_sessions.kql`
- `presets/EntraIdSignInEvents_ai_offhours_geo.kql`

**By website — `AIDomains`** (network presets):
- `presets/DeviceNetworkEvents_ai_client_channel.kql`
- `presets/DeviceNetworkEvents_ai_file_proximity.kql`

### Add a tool
1. Add its **app name** (e.g. `"Contoso AI"`) to the `AIAppNames` list in the two
   Cloud/SignIn presets.
2. Add its **website domain** (e.g. `"contoso.ai"`) to the `AIDomains` list in the
   two network presets.

Adding it to both lists means the tool is caught however employees reach it — by
app sign-in and by browsing its site. A tool you add is kept automatically under
its own name; you do not need to edit anything else.

### Remove a tool
Delete its line from the lists above. Anything not on the lists is ignored.

### Collect only a few specific tools
Trim the lists to just the ones you care about. For example, to collect only
Microsoft 365 Copilot, reduce `AIAppNames` to `"Microsoft 365 Copilot"` and
`"Copilot"`, and `AIDomains` to `"copilot.microsoft.com"` and
`"copilot.cloud.microsoft"`.

### Notes
- Matching is case-insensitive and matches whole words/phrases.
- The default lists ship with 60+ of the most common AI tools as a starting
  point. Trim them to match your organization's approved and monitored tools.
- (Optional) `ai_activity_sessions` also has `AISolution`, `Category`, and
  `RiskTier` `case()` blocks lower in the file. New tools appear under their raw
  app name with Category "Other" / RiskTier "Unsanctioned". To give a custom
  display name or category, add a matching line to those `case()` blocks — this
  is optional.

---

## Writing your own preset

1. **Start from the table** you want (e.g. `CloudAppEvents`, or another Advanced Hunting table).
2. **Add `{TIMEFILTER}`** in the first `where` clause — nothing else time-related.
3. **Filter and project** the columns you need. Fewer columns and tighter filters = fewer rows = fewer subdivisions.
4. **Save** it as a `.kql` file under `presets/`, named for the CSV it feeds.

Template:

```kusto
<YourTable>
| where {TIMEFILTER}
| where <your business filters>
| project <the columns you need>
| sort by Timestamp asc
```

> **Tip:** if a query is so dense that even 1-minute windows saturate, make the KQL more selective (tighter `where`, fewer matches). See [troubleshooting.md](troubleshooting.md#still-hitting-the-wall-at-the-1-minute-floor).

---

## Using a different time column

If your table's time column isn't `Timestamp`, pass `-TimeColumn`:

```powershell
.\Export-DefenderAdvancedHunting.ps1 -Query $kql -TimeColumn 'TimeGenerated' `
    -StartDate '<START_DATE>' -EndDate '<END_DATE>' `
    -OutputPath '<OUTPUT.csv>' -AccessToken '<YOUR_ACCESS_TOKEN>'
```

The exporter uses that column both for the `{TIMEFILTER}` predicate and for measuring data density during smart subdivision.
