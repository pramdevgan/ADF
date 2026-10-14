# 06 – Instructor Notes & Answer Key

## Before class (15 min, do once)
1. Run the whole lab yourself once on a test environment, especially INC-003 (key rotation) and INC-004 (trigger), which depend on your tenant settings.
2. If students share **one** SQL database or storage account, incidents will collide. Each student/pair needs their own resource group (Module 1).
3. Put `data/fixes/` aside, or hand it out only when students reach the fix steps, so they can't "peek" at the answers.
4. If the Module 2 alert rule exists, students receive real alert emails for each incident, which adds a lot of realism.

## Timing tips
- **Part A is the risk.** If a student is stuck > 5 min, have them paste `pipeline-json/pipeline_PL_20_Daily_Orders_Load.json` into the code view (create the 2 datasets first).
- **INC-004** has ~6 + 5 min of waiting. Use the first wait to explain `trigger().scheduledTime` (UTC) and the second to start filling the register.
- If short on time, drop **INC-003** (it's the most similar to INC-002) and the optional experiments.

## Data facts (answer key)

| LoadDate | File (upload) | Rows | Control amount | Outcome on first run | After fix |
|---|---|---|---|---|---|
| 2026-10-01 | orders_20261001.csv | 20 | 444,100.00 | ✅ Succeeded | – |
| 2026-10-02 | orders_20261002.csv | 22 | 347,800.00 | ✅ Succeeded with 5 WARNING checks failing | (optional dedupe → 337,300.00) |
| 2026-10-03 | Orders_20261003.csv | 18 | 512,150.00 | ❌ FILE_NOT_FOUND | 18 rows / 512,150.00 |
| 2026-10-04 | orders_20261004.csv | 15 | 400,450.00 | ❌ Copy – column UnitPrice not found | 15 rows / 400,450.00 |
| 2026-10-05 | orders_20261005.csv | 16 | 784,400.00 | ❌ ValidateLoad – 6 rejected, fact 10 rows / 565,400.00 | 16 rows / 784,400.00 |

### 2026-10-02 hidden defects
| OrderID | Defect | Check that catches it |
|---|---|---|
| 50025 | Duplicate (2 copies, Qty 5 × 1500) | V6 / DUPLICATE_ORDERID |
| 50031 | Duplicate (2 copies, Qty 2 × 1500) | V6 / DUPLICATE_ORDERID |
| 50028 | CustomerID C999 (not in dim) | V8 / ORPHAN_CUSTOMERID |
| 50033 | Quantity −2 | V9 / INVALID_QUANTITY |
| 50036 | CustomerID blank | V7 / NULL_CUSTOMERID |
| 50039 | Status 'Shiped' | V9 / INVALID_STATUS |

Revenue overstated by duplicates: **₹10,500** (347,800 → 337,300).

### 2026-10-05 rejected rows
50076 `28/09/2026` · 50079 `30/09/2026` · 50082 `27/09/2026` · 50085 `29/09/2026` (dates) · 50087 Quantity `N/A` · 50088 UnitPrice `12,000.00`

## Expected error messages (wording may vary slightly by ADF version)

| Incident | Activity | Message contains |
|---|---|---|
| INC-001 | Fail_FileNotFound | `FILE_NOT_FOUND: input/orders/orders_20261003.csv` (code 404) |
| INC-002 | CopyToStaging | `Client with IP address '…' is not allowed to access the server` |
| INC-003 | CheckFileExists | `Server failed to authenticate the request` / 403 (or `AuthorizationPermissionMismatch` for MI) |
| INC-004 | (no run) then Fail_FileNotFound | `orders_<ddMMyyyy>.csv not found for LoadDate dd-MM-yyyy` |
| INC-005a | CopyToStaging | `Column 'UnitPrice' … cannot be found in source data` |
| INC-005b | ValidateLoad | `DATA VALIDATION FAILED for LoadDate 2026-10-05: REJECTED_ROWS (expected 0, actual 6); CONTROL_TOTAL_AMOUNT (expected 784400.00, actual 565400.00)` |

## Common student problems
| Symptom | Fix |
|---|---|
| Baseline fails at CopyToStaging: "Invalid object name 'stg.Orders'" | SQL script 01 not run, or run against a different database |
| LoadFact: "Could not find stored procedure" | Scripts 02–04 must each be run separately |
| Mapping shows only 7 rows (no SourceFile/RunId) | Additional columns were added after Import schemas → click Import schemas again |
| INC-003 run still succeeds | LS uses key2 → rotate key2 too; or LS uses MI → remove the RBAC role instead |
| INC-004 trigger never fires even after Start | Not published after Start; start time in the past with a long recurrence; check Trigger runs |
| ValidateLoad: CONTROL checks SKIPPED | Expected for dates without a control record (e.g. today's date in INC-004) |
| Part C counts don't match | Another load ran after 10-02 and replaced staging → rerun 2026-10-02 |

## Reset to repeat the lab
1. Run `sql/07-reset-lab.sql`.
2. Re-upload original files from `data/upload/` (overwrite) and re-upload `Orders_20261003.csv` (delete the lowercase one).
3. Trigger `TR_Daily_Orders`: Stop / delete.
