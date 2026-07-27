# How it works — adaptive time-slicing

## The wall: 10,000 rows, no paging

Microsoft Defender Advanced Hunting (`security/runHuntingQuery`) returns a **hard maximum of 10,000 rows per query**. There is **no continuation token** — you can't ask for "the next page." If your query matches 10,001 rows, you get 10,000 and the rest vanish, with no error to warn you.

So the only lever you have is the **time range**: a smaller time window matches fewer rows. That's the whole idea behind this tool.

---

## The idea in one sentence

> Keep cutting the time range into smaller pieces until every piece returns **under** 10,000 rows, then glue all the pieces back together.

---

## The algorithm, step by step

1. **Build a queue.** The full range `[StartDate, EndDate)` is chopped into an initial set of windows (default **12 hours** each, capped at `MaxPartitions` windows total).
2. **Query a window.** Pop a window off the queue and run the KQL for just that window.
3. **Decide:**
   - **Under the cap** (`< RowCap`, default 10,000)? → **ACCEPT.** Keep the rows.
   - **At or above the cap** (`>= RowCap`)? → **SATURATED.** The rows were probably truncated, so this window must be split.
4. **Subdivide smartly.** Rather than blindly halving, the tool:
   - looks at the timestamps in the (full) batch and measures the **span they actually cover**,
   - estimates **rows per hour** from that span,
   - picks a split factor aimed at **~`TargetRowsPerWindow`** rows (default 8,000) per sub-window — a deliberate buffer under the cap.
   - The new sub-windows go **back onto the queue** and get queried in turn.
5. **Respect the floor.** No window is split below **`MinWindowMinutes`** (default 1 minute). If a 1-minute window *still* returns at the cap, the data is genuinely denser than the API can return for that minute; the tool keeps what it got and prints a warning.
6. **Merge.** When the queue is empty, all accepted rows are written to one CSV.

---

## Why no duplicates?

Every window is a **half-open interval** `[start, end)` — the start instant is included, the end instant is not. Because windows are contiguous (`...end` of one equals `...start` of the next) and never overlap, a row that lands exactly on a boundary is counted in **exactly one** window. No row is double-counted, so **no deduplication is required** by default. (An optional `-DedupeKey` exists for edge cases — see [parameters.md](parameters.md).)

---

## A worked example

Suppose you export a **12-hour** window and it comes back with **10,000 rows** — saturated.

1. The tool inspects the timestamps and sees those 10,000 rows only span the **first 4 hours** of the window. The last 8 hours weren't even reached.
2. Estimated density: `10,000 rows ÷ 4 h ≈ 2,500 rows/hour`.
3. To target ~8,000 rows per window: `8,000 ÷ 2,500 ≈ 3.2 hours` per sub-window.
4. Split factor for a 12-hour window: `ceil(12 ÷ 3.2) = 4`. → four ~3-hour windows are queued.
5. Each ~3-hour window is queried. Most now return well under 10,000 and are **accepted**. Any that still saturate get subdivided again — down toward the 1-minute floor if needed.
6. All accepted rows merge into the final CSV.

The smart step matters: blind halving would have created two 6-hour windows, and the first (holding all the dense data) would saturate *again*, wasting a round trip. Measuring density gets to safe window sizes faster.

---

## Flow diagram

```mermaid
flowchart TD
    A["Range [StartDate, EndDate)"] --> B["Split into initial windows (~12h each)"]
    B --> C{"Queue empty?"}
    C -- "Yes" --> H["Merge accepted rows to CSV"]
    C -- "No" --> D["Pop a window & run KQL"]
    D --> E{"Rows >= RowCap (10,000)?"}
    E -- "No" --> F["ACCEPT: keep rows"] --> C
    E -- "Yes" --> G{"Window <= 1 min floor?"}
    G -- "No" --> I["Smart subdivide (~8,000/window) → re-queue"] --> C
    G -- "Yes" --> J["Warn: dense minute, keep rows"] --> C
```

---

## The knobs that shape this

| Parameter | Default | Effect on slicing |
| --- | --- | --- |
| `-RowCap` | 10,000 | The saturation threshold. Lower it to force smaller windows. |
| `-TargetRowsPerWindow` | 8,000 | The buffer the smart split aims for under the cap. |
| `-InitialPartitionHours` | 12 | Size of the first windows before any subdivision. |
| `-MinWindowMinutes` | 1 | The floor — the smallest a window can get. |
| `-MaxPartitions` | 400 | Caps how many *initial* windows are created. |

Full reference: [parameters.md](parameters.md).
