# 03 – Hands-on Part B: Investigate Simulated Production Incidents (66 min)

You are the **on-call data engineer at ShopKart**. Five production incidents will come in. For each one you will:

```
🔧 Simulate  →  🚨 Observe  →  🔍 Investigate  →  🎯 Root cause  →  🛠 Fix  →  ✅ Verify  →  📝 Record
```

| # | Incident | Category | Time |
|---|---|---|---|
| INC-001 | 3 Oct orders missing | Missing file | 12 min |
| INC-002 | Load fails after "security hardening" | Connectivity | 12 min |
| INC-003 | Load fails after key rotation | Authentication | 12 min |
| INC-004 | "Today's data never arrived" | Trigger failure | 15 min |
| INC-005 | Vendor file changes | Data mapping (schema + format) | 15 min |

**Before you start:**
- Open `rca-templates/Incident-Register.csv` in Excel. You add **one row per incident** while you work, as your evidence log.
- Keep 3 browser tabs open: **ADF Studio (Monitor)**, **Azure Portal**, **SQL Query editor** with `sql/06-incident-investigation-queries.sql` loaded.
- **Working in pairs?** Partner A does the 🔧 *Simulate* steps without showing B. Partner B investigates "blind" from the ticket. Swap roles for each incident.

### The investigation checklist (use it every time)

| # | Question | Where to look |
|---|---|---|
| 1 | **Which** pipeline / run / activity failed? When? | Monitor → Pipeline runs → Failed → Activity runs |
| 2 | **What** is the exact error code + message? Failure type? | Activity row → 💬 Error icon |
| 3 | **What were the inputs?** (parameters, file name, connection) | Pipeline run → *Parameters*; activity → **Input** (→ icon) |
| 4 | **What changed?** (since the last good run) | Azure Portal → resource → **Activity log**; trigger/LS edit history; vendor email |
| 5 | **Can I reproduce it in isolation?** | Linked service → **Test connection**; dataset → **Preview data** |
| 6 | **What is the data impact?** | SQL: LoadLog, FactOrders, RejectedOrders (script 06) |

---

## INC-001 · Missing file (12 min)

> 🎫 **Ticket (Sev 2, 07:05):** "Alert: PL_20_Daily_Orders_Load **Failed** for 3 Oct. Vendor says they uploaded the file on time. Dashboard shows no sales for 3 Oct."

### 🔧 Simulate
Already done: the vendor uploaded `Orders_20261003.csv` in Part A1. Just run the load:
**Add trigger → Trigger now** → `p_LoadDate = 2026-10-03`.

### 🚨 Observe
Monitor → Pipeline runs → `PL_20_Daily_Orders_Load` → **Failed**.

### 🔍 Investigate
1. Open the run → **Activity runs**:

| Activity | Status |
|---|---|
| SetFileName | ✅ Succeeded |
| CheckFileExists | ✅ Succeeded *(the file check itself worked)* |
| IfFileMissing | ❌ Failed |
| Fail_FileNotFound | ❌ Failed |
| CopyToStaging … LogSuccess | ⏭ Not run (skipped) |

2. Click 💬 on `Fail_FileNotFound` → **Error code `404`** · Message `FILE_NOT_FOUND: input/orders/orders_20261003.csv not found for LoadDate 2026-10-03`.
3. Click **Output** (←) of `CheckFileExists` → `"exists": false`. ADF genuinely could not see the file.
4. Click **Output** of `SetFileName` → value = `orders_20261003.csv`. The pipeline built the name correctly from the parameter.
5. Portal → storage → `input/orders/` → the file **is** there… as **`Orders_20261003.csv`**. 🧐
6. Compare character by character: `O` vs `o`. **Blob names are case-sensitive.**
7. Optional, to prove it: in ADF, open `DS_Orders_Csv` → Preview data → p_file = `Orders_20261003.csv` → works; `orders_20261003.csv` → fails.

### 🎯 Root cause
- **Immediate cause:** the file arrived with a different file name (capital O), so the pipeline's naming rule didn't match.
- **Root cause (5 Whys):** the vendor changed their export tool. There is **no written file-naming contract** and no alert on file arrival.

### 🛠 Fix
The portal can't rename blobs (Azure Storage Explorer can). The vendor re-sends the correct file:
1. Upload `data/fixes/orders_20261003.csv` to `input/orders/`.
2. Delete `Orders_20261003.csv`, so it doesn't confuse anyone later.
3. Monitor → the failed run → **⟳ Rerun**. It reruns with the same parameter, `2026-10-03`.

### ✅ Verify
```sql
SELECT * FROM audit.LoadLog WHERE LoadDate = '2026-10-03';
-- ✅ Succeeded | RowsRead 18 | FactRows 18 | RejectedRows 0
SELECT SUM(Amount) FROM dbo.FactOrders WHERE LoadDate = '2026-10-03';
-- ✅ 512150.00 = audit.SourceControl
```

### 📝 Record (Incident-Register.csv)
`INC-001 | Missing file | PL_20 | <RunId> | Fail_FileNotFound | 404 | FILE_NOT_FOUND… | Vendor naming changed (case) | Re-sent file + rerun | <times>`

> **Discussion (1 min):** without our Get Metadata + Fail design, what would the error look like? (A generic Copy error saying the blob/path doesn't exist, which is much less clear for on-call staff.)

---

## INC-002 · Connectivity failure (12 min)

> 🎫 **Ticket (Sev 1, 07:10):** "Daily load failed. Security team did 'network hardening' on database servers last night."

### 🔧 Simulate
Portal → **SQL server** `sql-adf-lab-<initials>` (the *server*, not the database) → **Security → Networking** → **Exceptions** → **uncheck** ☐ *Allow Azure services and resources to access this server* → **Save**.
*(Leave your client IP rule as is, so your Query editor keeps working. This is realistic: humans can still log in, only the service is blocked.)*

Run: **Trigger now** → `p_LoadDate = 2026-10-01`.

### 🚨 Observe
Run **Failed**. `SetFileName`, `CheckFileExists`, `IfFileMissing` = ✅ → **`CopyToStaging` ❌**.

### 🔍 Investigate
1. **Localize:** the activities that only touch **Blob** succeeded. The first one that touches **SQL** failed. So Blob is fine and the suspect is SQL.
2. 💬 Error on CopyToStaging → error code `2200` / failure type *User configuration issue* · message similar to:
   `Cannot open server 'sql-adf-lab-xx' requested by the login. Client with IP address '20.xx.xx.xx' is not allowed to access the server.`
   Keywords **IP address … not allowed** → **network/firewall**, not password.
3. **Reproduce in isolation:** ADF → Manage → Linked services → `LS_AzureSqlDb` → **Test connection** → same error ❌. The pipeline logic is fine; the connection itself is broken.
4. **Why does my Query editor still work?** Because **your** IP has a firewall rule; the ADF Azure IR's IP does not.
5. **What changed?** Portal → SQL server → **Activity log** → filter last 24 hours → find an operation like *"Update SQL server firewall rule"* / *"Update Azure SQL Server"*, with **who** and **when**. This is your RCA timeline evidence.

### 🎯 Root cause
- **Immediate:** the "Allow Azure services" firewall exception was disabled, so ADF's Azure IR is blocked.
- **Root cause:** the security change was made **without an impact assessment** of dependent services. There is no inventory of what connects to this server, and no post-change smoke test.

### 🛠 Fix
SQL server → Networking → ✅ *Allow Azure services and resources to access this server* → **Save** → wait ~1 min → `LS_AzureSqlDb` → **Test connection** ✅ → **Rerun** the failed run.
*(Long-term, secure option: Private endpoint + Managed VNet IR. Mention it in the RCA preventive actions.)*

### ✅ Verify
Run Succeeded → `SELECT * FROM audit.LoadLog ORDER BY LoggedAt DESC;` shows a new 2026-10-01 row (20/20).
*Note: FactOrders still has exactly 20 rows for 10-01, not 40, because usp_Load_Orders is idempotent.*
```sql
SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = '2026-10-01';   -- ✅ 20
```

### 📝 Record → INC-002 row.

---

## INC-003 · Authentication failure (12 min)

> 🎫 **Ticket (Sev 1, 07:12):** "Load failed. Note: quarterly security key rotation happened yesterday."

### 🔧 Simulate
Portal → storage account `stadflab<initials>` → **Security + networking → Access keys** → **key1 → ⟳ Rotate key** (Regenerate) → Yes.
*(If the next run still succeeds, your linked service uses key2. Rotate key2 too.)*
> **If you switched `LS_BlobStorage` to Managed Identity in Module 1:** simulate instead by removing the factory's **Storage Blob Data Contributor** role (Storage → Access control (IAM) → Role assignments → remove). You'll get `AuthorizationPermissionMismatch`.

Run: **Trigger now** → `2026-10-01`.

### 🚨 Observe
`SetFileName` ✅ → **`CheckFileExists` ❌** (the very first activity that touches Blob).

### 🔍 Investigate
1. 💬 Error → message similar to:
   `Server failed to authenticate the request. Make sure the value of Authorization header is formed correctly including the signature.` → **403 / AuthenticationFailed**
2. Classify it using the theory table: no IP/firewall words; **authenticate / 403** → **authentication**, not connectivity.
3. **Reproduce:** Manage → `LS_BlobStorage` → **Test connection** ❌, same error.
4. **Compare with INC-002:** there, Blob worked and SQL failed on *network*. Here, Blob fails on *identity*.
5. **What changed?** Storage account → **Activity log** → operation *"Regenerate Storage Account Keys"* → who/when.

### 🎯 Root cause
- **Immediate:** the storage key was rotated; ADF's linked service still holds the old key.
- **Root cause:** the key-rotation runbook **doesn't include updating dependent services**. The secret is stored inside ADF instead of Key Vault, or Managed Identity is not used.

### 🛠 Fix
**Quick fix (restore service):** Manage → `LS_BlobStorage` → (edit) → Account selection method **From Azure subscription** → re-select the storage account (ADF fetches the current key) → **Test connection** ✅ → **Save**. Then **Rerun** the failed run.
**Permanent fix (preventive, if time allows):** storage → IAM → add **Storage Blob Data Contributor** to the data factory's managed identity → LS authentication type **System-assigned managed identity** → Test → Save. Key rotation can never break ADF again.

### ✅ Verify
Run Succeeded; LoadLog has a new 10-01 row; FactOrders 10-01 still 20 rows.

### 📝 Record → INC-003 row.

---

## INC-004 · Trigger failure (15 min)

> 🎫 **Ticket (Sev 2, 09:05):** "A new automated daily trigger was deployed yesterday. CEO dashboard has **no data for today**, and **no failure alert** was received."

### 🔧 Simulate (≈ 4 min)
1. **Prepare today's file:** take `data/upload/orders_20261001.csv`, **rename** the copy on your PC to `orders_<today as yyyyMMdd>.csv` (e.g. `orders_20261014.csv`), and upload it to `input/orders/`.
2. Open `PL_20_Daily_Orders_Load` → **Add trigger → New/Edit → + New**:

| Field | Value (deliberately buggy) |
|---|---|
| Name | `TR_Daily_Orders` |
| Type | Schedule |
| Start date | now + 2 min |
| Time zone | (UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi |
| Recurrence | Every **5** Minute(s) *(stands in for "daily", so we don't wait 24 h)* |
| **Activated** | **No** ← bug 1 |

   → OK → **Trigger Run Parameters**: `p_LoadDate` = `@formatDateTime(trigger().scheduledTime,'dd-MM-yyyy')` ← bug 2 → OK.
3. **Publish all.** Wait ~6 minutes; use the time for the first investigation step.

### 🚨 Observe – Phase 1 ("nothing happened")
Monitor → Pipeline runs: **no new run**, nothing red, no alert. *This is why trigger failures are dangerous: silence.*

### 🔍 Investigate – Phase 1
1. Monitor → **Trigger runs** → no entries for `TR_Daily_Orders`. The trigger never fired.
2. Manage → **Triggers** → `TR_Daily_Orders` → **Status: Stopped**.
3. Root cause #1: the trigger was deployed but **never activated**.

### 🛠 Fix – Phase 1
Manage → Triggers → `TR_Daily_Orders` → **▷ Start** (or edit → Activated: Yes) → **Publish all**. Wait ≤ 5 min.

### 🚨 Observe – Phase 2 ("it ran… and failed")
Trigger runs → ✅ `TR_Daily_Orders` Succeeded *(the trigger fired fine)*. Pipeline runs → `PL_20` **Failed**, *Triggered by* `TR_Daily_Orders`.

### 🔍 Investigate – Phase 2
1. Error: `FILE_NOT_FOUND: input/orders/orders_14102026.csv not found for LoadDate 14-10-2026` (your date will differ).
2. But the file **is** there as `orders_20261014.csv`! Compare: `14102026` vs `20261014`.
3. Pipeline runs list → **Parameters** column (or the run's parameter view) → `p_LoadDate = 14-10-2026`. The **trigger** passed the date in the wrong format.
4. `SetFileName` output confirms the wrong name was built from that parameter.
5. **Lesson:** the pipeline is correct (a manual run with `yyyy-MM-dd` works). The defect is in the **trigger's parameter expression**.

### 🛠 Fix – Phase 2
Manage → Triggers → `TR_Daily_Orders` → edit *(if ADF says the trigger must be stopped first: **Stop** → edit → Publish → **Start**)* → parameter `p_LoadDate`:
```
@convertFromUtc(trigger().scheduledTime, 'India Standard Time', 'yyyy-MM-dd')
```
**Why `convertFromUtc` and not just `formatDateTime(...,'yyyy-MM-dd')`?** `trigger().scheduledTime` is always in **UTC**. A daily IST run between 00:00 and 05:29 would otherwise get **yesterday's** date. That's a second, hidden bug.
→ **Publish all** → wait for the next fire.

### ✅ Verify
Pipeline run Succeeded (Triggered by TR_Daily_Orders):
```sql
SELECT * FROM audit.LoadLog ORDER BY LoggedAt DESC;      -- today's date, 20 rows
SELECT CheckName, Result FROM audit.ValidationResults
WHERE LoadDate = CAST(GETDATE() AS DATE);                 -- CONTROL_* = SKIPPED (no manifest for today)
```
**Discuss:** CONTROL checks show **SKIPPED** because the vendor sent no manifest for today. Should a missing control record be CRITICAL in production? (Usually yes: no manifest means you can't prove completeness.)

### ⚠️ Stop the trigger now
Manage → Triggers → `TR_Daily_Orders` → **Stop** → **Publish all**. Otherwise it runs every 5 minutes.

### 📝 Record → INC-004 row (two root causes: not activated + wrong date format; latent UTC bug).

---

## INC-005 · Data mapping errors (15 min)

### Part 5a – Schema drift (7 min)

> 🎫 **Ticket (Sev 2, 07:08):** "Load for 4 Oct failed. Vendor released 'v2' of their export last night."

**🔧 Simulate:** already uploaded. **Trigger now** → `2026-10-04`.

**🚨 Observe:** `CheckFileExists` ✅ (the file exists!) → **`CopyToStaging` ❌**.

**🔍 Investigate:**
1. 💬 Error, similar to: `ErrorCode=UserErrorInvalidColumnMappingColumnNotFound … Column 'UnitPrice' specified in column mapping cannot be found in source data`.
2. Inspect the file: Author → `DS_Orders_Csv` → **Preview data** → p_file = `orders_20261004.csv` → header is
   `OrderID, OrderDate, CustomerID, ProductID, Quantity, `**`Unit_Price`**`, `**`Discount`**`, Status`
3. Compare with the Copy activity → **Mapping** tab, which expects `UnitPrice`. **Schema drift** = the source structure changed without notice.
4. Check `CheckFileExists` output → *Size* is larger than usual (extra column). Evidence for the RCA.

**🎯 Root cause:** the vendor renamed a column and added one; there is no schema contract or schema check before loading.

**🛠 Fix – choose and justify (write your choice in the register):**

| Option | Pros | Cons |
|---|---|---|
| A. Vendor re-sends file in agreed format | Pipeline unchanged; contract enforced | Depends on vendor speed |
| B. Change mapping `Unit_Price → UnitPrice` | Fast | **Breaks every other day's file**; need two versions |
| C. Dynamic mapping / schema-drift handling (Data Flow) | Robust long-term | More build effort |

**Do option A:** upload `data/fixes/orders_20261004.csv` (overwrite) → **Rerun**.

**✅ Verify:** LoadLog 2026-10-04 → 15 rows · `SUM(Amount)` = **400450.00**.

> 🧪 **Optional experiment (2 min):** what if mapping were NOT explicit? Clone the pipeline, clear the Copy **Mapping**, run with the *original* drift file → Copy **succeeds**, UnitPrice lands as NULL → `usp_Load_Orders` rejects all 15 rows → **ValidateLoad** fails with `REJECTED_ROWS`. The validation gate catches what the copy missed.

### Part 5b – Data type / format errors (8 min)

> 🎫 **Ticket (Sev 1, 07:15):** "Load for 5 Oct failed at validation. Finance noticed **partial** numbers on the dashboard."

**🔧 Simulate:** **Trigger now** → `2026-10-05`.

**🚨 Observe:** `CopyToStaging` ✅ · `LoadFact` ✅ · **`ValidateLoad` ❌** · LogSuccess skipped.

**🔍 Investigate:**
1. 💬 Error on ValidateLoad (it's our own `THROW 50001`):
   `DATA VALIDATION FAILED for LoadDate 2026-10-05: REJECTED_ROWS (expected 0, actual 6); CONTROL_TOTAL_AMOUNT (expected 784400.00, actual 565400.00)`
2. **Why did Copy succeed?** Staging is all-NVARCHAR, so bad values land as text. Conversion happens in `usp_Load_Orders`.
3. SQL – which rows and why? (`06-incident-investigation-queries.sql` → **I3**)
```sql
SELECT OrderID, OrderDate, Quantity, UnitPrice, RejectReason
FROM audit.RejectedOrders WHERE LoadDate = '2026-10-05';
```
   ✅ expect 6 rows:

| OrderID | Problem value | RejectReason |
|---|---|---|
| 50076 | 28/09/2026 | Invalid OrderDate (dd/MM/yyyy) |
| 50079 | 30/09/2026 | Invalid OrderDate |
| 50082 | 27/09/2026 | Invalid OrderDate |
| 50085 | 29/09/2026 | Invalid OrderDate |
| 50087 | Quantity `N/A` | Invalid Quantity |
| 50088 | UnitPrice `12,000.00` | Invalid UnitPrice |

4. **Impact (very important):** run **I5** (partial-load detector):
```sql
SELECT LoadDate, COUNT(*) FROM dbo.FactOrders GROUP BY LoadDate;
-- 2026-10-05 → 10 rows present, but NO success row in audit.LoadLog
```
   `LoadFact` committed **10 good rows before** the gate failed, so the dashboard showed **₹5,65,400 instead of ₹7,84,400** (₹2,19,000 understated). That's what Finance saw.
5. Pattern: the 4 bad dates are all **late orders from September**. The vendor's system formats back-dated orders differently. This is a good RCA detail.

**🎯 Root cause:** the vendor exports inconsistent formats (no data contract). **Design weakness:** the quality gate runs **after** data is published to the fact table, so partial data was visible.

**🛠 Fix:**
1. **Immediate:** upload `data/fixes/orders_20261005.csv` (overwrite) → **⟳ Rerun** (the full pipeline). *"Rerun from failed activity" would only re-validate the same bad staging data and fail again; the file must be copied in again.*
2. **Preventive (write in CAPA):**
   - Validate **staging before** loading the fact (move the critical checks ahead of LoadFact), or load fact inside a transaction / swap pattern.
   - Optionally accept `dd/MM/yyyy` with `TRY_CONVERT(DATE, x, 103)` *if the contract allows*.

**✅ Verify:**
```sql
SELECT COUNT(*), SUM(Amount) FROM dbo.FactOrders WHERE LoadDate = '2026-10-05';  -- ✅ 16 | 784400.00
SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate = '2026-10-05';         -- ✅ 0 (old rejects deleted by idempotent SP)
```

### 📝 Record → INC-005a and INC-005b rows.

---

## Part B wrap-up (in your notes)

| Incident | First failing activity | Category | Key evidence |
|---|---|---|---|
| INC-001 | Fail_FileNotFound | Missing file | `exists:false`, file name case |
| INC-002 | CopyToStaging | Connectivity | "IP … not allowed", Test connection ❌, Activity log |
| INC-003 | CheckFileExists | Authentication | 403 AuthenticationFailed, key regenerated |
| INC-004 | *(no run)* → Fail_FileNotFound | Trigger | Trigger Stopped; parameter `dd-MM-yyyy` |
| INC-005a | CopyToStaging | Mapping – schema drift | Column not found; new header |
| INC-005b | ValidateLoad | Mapping – data types | 6 rejected rows, partial load |

**Pattern to remember:** *which activity fails first* tells you **where** to look:
Get Metadata = file / Blob auth · Copy = schema, SQL connectivity · Stored procedure = data quality · *no run at all* = trigger.

➡️ Next: `04-Data-Validation-Hands-on.md`
