# Parameter reference

Complete list of parameters for `Export-DefenderAdvancedHunting.ps1`, taken directly from the script's comment-based help and `param()` block. Parameters marked **Required** must always be supplied.

| Name | Type | Default | Required | Description |
| --- | --- | --- | --- | --- |
| `Query` | `string` | — | **Yes** | The KQL query to execute. **Must contain the literal token `{TIMEFILTER}`** where a time predicate belongs. For each window the token is replaced with `<TimeColumn> >= datetime(<startISO>) and <TimeColumn> < datetime(<endISO>)`. If `{TIMEFILTER}` is missing, the tool throws a terminating error. |
| `StartDate` | `datetime` | — | **Yes** | Inclusive start of the export range (half-open interval start). |
| `EndDate` | `datetime` | — | **Yes** | Exclusive end of the export range (half-open interval end). Must be greater than `StartDate`. |
| `TimeColumn` | `string` | `Timestamp` | No | The KQL column used for time filtering and subdivision analysis. Defaults to `Timestamp` (the CloudAppEvents time column). |
| `OutputPath` | `string` | — | **Yes** | Path to the CSV file that receives the merged result set. |
| `InitialPartitionHours` | `double` | `12` | No | Initial window size, in hours, used to build the first work queue. |
| `MaxPartitions` | `int` | `400` | No | Maximum number of **initial** partitions. If the range ÷ `InitialPartitionHours` would exceed this, the partition size is recomputed as `totalHours / MaxPartitions`. Subdivision can still create more windows beyond this count. |
| `MinWindowMinutes` | `double` | `1` | No | Subdivision floor. A window at or below this size that still saturates cannot be split further; a warning is emitted and the returned (possibly truncated) rows are kept. |
| `RowCap` | `int` | `10000` | No | Saturation threshold. A window returning `>= RowCap` rows triggers subdivision. `10000` is the real API cap. |
| `TargetRowsPerWindow` | `int` | `8000` | No | Smart-subdivision target row count per sub-window (a buffer below `RowCap`). |
| `AccessToken` | `string` | — | No | A pre-acquired Microsoft Graph bearer token. If supplied it is used directly. Never logged. |
| `TenantId` | `string` | — | No | Microsoft Entra tenant id for client-credentials token acquisition. Used only when `-AccessToken` is not supplied. |
| `ClientId` | `string` | — | No | App registration (client) id for client-credentials token acquisition. |
| `ClientSecret` | `securestring` | — | No | App registration client secret as a `SecureString`. Never logged. |
| `QueryExecutor` | `scriptblock` | — | No | **Testing injection seam.** A scriptblock receiving one argument — a `PSCustomObject` with `Kql`, `Start` (datetime), `End` (datetime) — that must return an array of row objects. When supplied, it is used **instead of** calling Microsoft Graph, enabling credential-free testing of the subdivision logic. |
| `DedupeKey` | `string[]` | — | No | Optional column name(s). When supplied, the merged result set is de-duplicated by these columns after merge. Off by default because half-open contiguous intervals already prevent boundary double-counting. |

## Credential requirement

For real (non-mock) execution you must supply **one** of:

- `-AccessToken`, **or**
- `-TenantId` **+** `-ClientId` **+** `-ClientSecret`, **or**
- `-QueryExecutor` (testing only — bypasses Graph).

If none are supplied, the tool stops with an error. See [authentication.md](authentication.md).

## Notes

- Requires **PowerShell 7+**.
- Requires the Microsoft Graph permission **`ThreatHunting.Read.All`** for real execution.
- No tenant id, client id, secret, or token is ever hardcoded or logged.
