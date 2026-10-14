# Root Cause Analysis (RCA) Report – WORKED EXAMPLE

| Field | Value |
|---|---|
| **Incident ID** | INC-001 |
| **Title** | 3 Oct orders not loaded – source file arrived with a different name |
| **Date of incident** | 03-Oct-2026 |
| **Severity** | Sev 2 (one day of sales missing from dashboard; no data loss) |
| **Status** | Resolved |
| **Author** | On-call Data Engineer |
| **Reviewed by** | Data Platform Lead |
| **Systems affected** | ADF `PL_20_Daily_Orders_Load`; `dbo.FactOrders`; CEO Sales Dashboard |

---

## 1. Summary
On 3 Oct the daily orders load failed because the vendor's file arrived as `Orders_20261003.csv` instead of the agreed `orders_20261003.csv`. Azure Blob file names are case-sensitive, so the pipeline treated the file as missing. The CEO dashboard showed no sales for 3 Oct from 07:05 until 07:40, when the vendor re-sent the file with the correct name and the load was rerun successfully.

## 2. Impact
| Dimension | Detail |
|---|---|
| Data affected | LoadDate 2026-10-03 – 18 orders, ₹5,12,150 |
| Business impact | CEO/Sales dashboard showed ₹0 for 3 Oct for 35 minutes (before the 9 AM review – no decision impact) |
| Duration | 07:05 – 07:40 IST (35 min) |
| Users affected | Sales leadership (dashboard), Finance (daily flash report delayed) |
| Data loss? | No |

## 3. Timeline (IST)
| Time | Event | Evidence |
|---|---|---|
| 02-Oct 07:01 | Last known good run (LoadDate 2026-10-02) | Monitor Run ID `a1b2…` |
| 02-Oct (evening) | Vendor upgraded export tool (new default file name) | Vendor email, 03-Oct 07:30 |
| 03-Oct 06:02 | File `Orders_20261003.csv` uploaded to `input/orders/` | Blob *Last modified* |
| 03-Oct 07:01 | Pipeline started; `Fail_FileNotFound` raised `FILE_NOT_FOUND` (404) | Monitor Run ID `c3d4…` |
| 03-Oct 07:05 | **Detected** – Azure Monitor alert "Failed pipeline runs > 0" | Alert email |
| 03-Oct 07:08 | Investigation: `CheckFileExists.output.exists = false`; file found with capital "O" | Monitor output; container listing |
| 03-Oct 07:15 | Root cause identified; vendor contacted | Ticket comment |
| 03-Oct 07:35 | Vendor re-sent `orders_20261003.csv`; wrong file deleted | Blob listing |
| 03-Oct 07:37 | Pipeline rerun – Succeeded | Monitor Run ID `e5f6…` |
| 03-Oct 07:40 | **Resolved** – 18 rows / ₹5,12,150 match control | SQL validation (below) |

**MTTD:** 4 min  **MTTR:** 35 min

## 4. Detection
Detected by the Azure Monitor metric alert on failed pipeline runs, 4 minutes after failure. The explicit `FILE_NOT_FOUND` message from the Fail activity made the cause obvious within 3 minutes. **Could be earlier:** a file-arrival check at 06:30 would have caught it before the scheduled run.

## 5. Investigation & Evidence
| Step | What I checked | Finding | Evidence |
|---|---|---|---|
| 1 | Monitor → failed run → activity runs | `Fail_FileNotFound` failed; Copy never ran | Run ID `c3d4…` |
| 2 | Error details | Code 404, `FILE_NOT_FOUND: input/orders/orders_20261003.csv` | Error pane |
| 3 | `SetFileName` output | Name built correctly from parameter `2026-10-03` | Activity output |
| 4 | `CheckFileExists` output | `exists: false` | Activity output |
| 5 | Container listing | File present as `Orders_20261003.csv` | Portal screenshot |
| 6 | Dataset preview with both names | Capital-O name works, lowercase fails → case-sensitivity confirmed | Preview |

## 6. Root Cause
**Category:** Missing file

**Immediate cause:** the source file name used a capital "O"; the pipeline (correctly) looks for the agreed lowercase name, and Blob storage is case-sensitive.

**5 Whys:**
1. Why was 3 Oct missing on the dashboard? → The pipeline failed.
2. Why did it fail? → It could not find `orders_20261003.csv`.
3. Why couldn't it find it? → The file was named `Orders_20261003.csv`; Blob names are case-sensitive.
4. Why did the name change? → The vendor upgraded their export tool, which uses a different default name.
5. Why did nobody catch the change? → The naming convention was agreed verbally; there is **no written file-interface contract** and no change notification process with the vendor.

**Root cause:** no formal file-interface contract and change process with the vendor.
**Contributing factor:** no early file-arrival check before the scheduled load.

## 7. Resolution
Vendor re-sent the file with the agreed name; the wrongly named file was deleted; the failed run was rerun.
Verification:
```sql
SELECT Status, RowsRead, FactRows FROM audit.LoadLog WHERE LoadDate='2026-10-03';  -- Succeeded, 18, 18
SELECT SUM(Amount) FROM dbo.FactOrders WHERE LoadDate='2026-10-03';               -- 512150.00 = control
```

## 8. Corrective & Preventive Actions (CAPA)
| # | Action | Type | Owner | Due | Status |
|---|---|---|---|---|---|
| 1 | Reload 3 Oct with corrected file | Corrective | On-call DE | 03-Oct | Done |
| 2 | Sign a file-interface contract (name pattern, columns, formats, delivery time) and a 5-day change-notice clause | Preventive | Data Product Owner | 17-Oct | Open |
| 3 | Add a 06:30 file-arrival check (Get Metadata on folder, alert if today's file absent) | Detective | DE team | 10-Oct | Open |
| 4 | Switch to Storage-event trigger on `input/orders/` + case-insensitive name matching via Filter activity (`toLower(item().name)`) | Preventive | DE team | 24-Oct | Open |

## 9. Lessons Learned
- **Went well:** the explicit Fail message and Get Metadata `exists` check cut diagnosis to 3 minutes.
- **Went badly:** we depended on an unwritten agreement with an external party.
- **Got lucky:** it happened before the 9 AM review; on a month-end day the impact would have been much higher.

---
*Blameless review: this document describes system and process failures, not individual fault.*
