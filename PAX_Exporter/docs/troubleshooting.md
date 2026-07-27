# Troubleshooting

Common problems and how to fix them. Find your symptom in the table, then read the matching section below.

| Symptom | Likely cause | Jump to |
| --- | --- | --- |
| `401 Unauthorized` | Expired or invalid token | [401 / 403 errors](#401--403--authorization-errors) |
| `403 Forbidden` | Missing `ThreatHunting.Read.All` | [401 / 403 errors](#401--403--authorization-errors) |
| `429` / "waiting … retry" | API throttling | [429 throttling](#429--throttling) |
| Warning about the 1-minute window | Extremely dense data | [1-minute floor](#still-hitting-the-wall-at-the-1-minute-floor) |
| Empty CSV / 0 rows | KQL issue or missing `{TIMEFILTER}` | [Empty results](#empty-results) |
| Garbled characters in the CSV | Encoding mismatch on open | [CSV encoding](#csv-encoding) |
| "must contain the literal token `{TIMEFILTER}`" | Token missing from query | [Missing TIMEFILTER](#error-query-must-contain-timefilter) |
| "No credentials supplied" | No auth parameters given | [No credentials](#error-no-credentials-supplied) |

---

## 401 / 403 — authorization errors

**`401 Unauthorized`** almost always means your **access token expired** (tokens last ~1 hour). Get a fresh token and re-run. If you're using an app registration, the tool re-acquires a token automatically, so a 401 there points to a bad secret or the wrong tenant/client id.

**`403 Forbidden`** means you authenticated fine but you **lack the permission**. The identity must have Microsoft Graph **`ThreatHunting.Read.All`**, and for an app registration that permission must have **admin consent granted** (green check). See [authentication.md](authentication.md).

---

## 429 — throttling

A `429 Too Many Requests` (or a `5xx`) is handled for you. You'll see:

```
[RETRY] HTTP 429 on attempt 2/5 - waiting 4 s
```

The tool automatically retries up to 5 times with exponential backoff, honoring the server's `Retry-After` header when present. **You don't need to do anything** — let it run. Only if it exhausts all attempts will it stop with an error; in that case, re-run later or narrow your date range.

---

## Still hitting the wall at the 1-minute floor

If you see:

> Minimal window … still returned >= RowCap … Records within this window may be truncated by the API; keeping N returned rows.

…it means a **single 1-minute window** matched 10,000+ rows. The tool can't subdivide below `MinWindowMinutes`, so those rows may be truncated. Fixes:

- **Make the KQL more selective** — add tighter `where` filters so fewer rows match (see [presets-and-kql.md](presets-and-kql.md)).
- **Project fewer columns** — smaller rows won't reduce the count, but a tighter filter will.
- As a last resort, lower `-TargetRowsPerWindow` (e.g. `4000`) so windows are sized more conservatively before the floor.

This warning reflects a genuine API limitation, not a bug — the data is simply denser than 10,000 rows per minute.

---

## Empty results

A CSV with only a header (or an empty file) usually means the query matched nothing. Check:

- **Is `{TIMEFILTER}` present?** Without it the tool errors out — see below. With a wrong/extra time filter, your rows may be excluded.
- **Is the date range right?** `-EndDate` is **exclusive**. `-StartDate '2026-06-01' -EndDate '2026-06-01'` covers zero time.
- **Does the KQL return anything at all?** Test a small window directly in the Defender Advanced Hunting portal first.
- **Right table / column names?** A typo in a column name can silently yield nothing.

The tool always writes a file (even when empty) so downstream steps get a predictable artifact.

---

## CSV encoding

Output is written as **UTF-8** with a header row. If names or non-ASCII characters look garbled:

- Open with UTF-8 explicitly. In Excel, use *Data → From Text/CSV* and choose **65001: Unicode (UTF-8)** as the file origin.
- In PowerShell, read it back with `Import-Csv` (which handles UTF-8 correctly):

  ```powershell
  Import-Csv '<OUTPUT.csv>' | Select-Object -First 5
  ```

---

## Error: "Query must contain {TIMEFILTER}"

Full message: *"The -Query must contain the literal token '{TIMEFILTER}' …"*. Your KQL is missing the placeholder the exporter needs to inject each time window. Add `{TIMEFILTER}` to your first `where` clause and remove any hand-written time predicate. See [presets-and-kql.md](presets-and-kql.md#the-timefilter-token-required).

---

## Error: "No credentials supplied"

You didn't tell the tool how to authenticate. Supply **one** of:

- `-AccessToken <YOUR_ACCESS_TOKEN>`, or
- `-TenantId` + `-ClientId` + `-ClientSecret`, or
- `-QueryExecutor` (testing only).

See [authentication.md](authentication.md).

---

## Checking your environment

```powershell
# PowerShell version (must be 7+)
$PSVersionTable.PSVersion

# Row count of an export (excludes header)
(Import-Csv '<OUTPUT.csv>').Count
```
