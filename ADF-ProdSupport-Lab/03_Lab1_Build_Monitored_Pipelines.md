# Lab 1 — Build "support-ready" pipelines in ADF Studio
⏱ ~45 min  |  Goal: a production-like daily load that **logs every run, raises tickets automatically, fails loudly and can be rerun safely**.

> A pipeline that only moves data is a *dev* pipeline. A *support-ready* pipeline also answers, without anyone opening code:
> **Did it run? With which parameters? How many rows? If it failed — where, why, and is there a ticket? Can I rerun it safely?**

---

## 1.1 Open ADF Studio
Portal → Data factory `adf-ps-<initials>` → **Overview → Launch studio** (or https://adf.azure.com and pick the factory).

ADF Studio hubs (left rail) you will use:

| Icon | Hub | Used for |
|---|---|---|
| 🏠 | Home | |
| ✏️ | **Author** | Pipelines, datasets, data flows |
| 📈 | **Monitor** | Pipeline runs, trigger runs, IR status, **alerts & metrics**, **rerun** |
| 🧰 | **Manage** | Linked services, integration runtimes, triggers, Git, global parameters |

---

## 1.2 Linked services (Manage → Linked services → + New)

A **linked service** = connection string (where + how to authenticate). Datasets and activities reuse it.

### a) `LS_KeyVault`
1. + New → search **Azure Key Vault** → Continue.
2. Name `LS_KeyVault`; Azure key vault selection: **From Azure subscription** → pick `kv-adf-ps-<initials>`; Authentication: **System-assigned managed identity**.
3. **Test connection** → ✅ → **Create**.
   - *What it does:* lets other linked services fetch secrets **at runtime**. The password is never stored in ADF → rotation needs **no ADF redeploy** (and a bad rotation breaks ADF instantly — Scenario S5).

### b) `LS_ADLS`
1. + New → **Azure Data Lake Storage Gen2** → Continue.
2. Name `LS_ADLS`; Connect via integration runtime: **AutoResolveIntegrationRuntime**.
   - *Why AutoResolve:* Azure-hosted, serverless compute managed by Microsoft; enough for public endpoints. A **Self-hosted IR** is used for on-prem/private sources — and is a very common source of prod incidents (VM down, certificate expiry).
3. Authentication type: **System-assigned managed identity**; Account selection: From Azure subscription → your storage account.
4. **Test connection** (choose *To linked service*) → ✅ → **Create**.
   - If ❌ *403*: the RBAC from setup 2.8a hasn't propagated or wasn't assigned to the **Data factory** identity.

### c) `LS_AzureSql`
1. + New → **Azure SQL Database** → Continue.
2. Name `LS_AzureSql`; IR: AutoResolve; Version: **Recommended** (if asked).
3. Server name: `sql-adf-ps-<initials>.database.windows.net` (or pick from subscription); Database: `sqldb-retail`.
4. Authentication type: **SQL authentication**; User name: `adfloader`.
5. Password → switch to **Azure Key Vault** → AKV linked service `LS_KeyVault` → Secret name `sql-adfloader-password` → Secret version: *(leave blank = latest)*.
   - *Why blank version:* ADF always picks the **latest** secret version → rotation is automatic. Trade-off: a wrong new version breaks prod immediately.
6. Encrypt: **mandatory** (default). **Test connection** → ✅ → **Create**.

> 💡 JSON for all three is in `adf/linkedService/`. Replace `<initials>`/`<digits>` placeholders if you paste JSON (Manage → linked service → `{}` code view).

---

## 1.3 Datasets (Author → + → Dataset)

We use **two generic, parameterised datasets** instead of one dataset per file/table.
*Why:* fewer objects to maintain; when a path changes you fix it in the pipeline parameter, not in 20 datasets.

### a) `DS_ADLS_Csv`
1. + → Dataset → **Azure Data Lake Storage Gen2** → **DelimitedText** → Continue.
2. Name `DS_ADLS_Csv`; Linked service `LS_ADLS`; File path: leave empty; ✅ **First row as header**; Import schema: **None** → OK.
3. **Parameters** tab → + New ×3: `pContainer`, `pFolder`, `pFileName` (String).
4. **Connection** tab → File path → click each box → **Add dynamic content**:
   - File system: `@dataset().pContainer`
   - Directory: `@dataset().pFolder`
   - File: `@dataset().pFileName`
5. Column delimiter: Comma; Quote `"`; Escape `\`; Encoding default.

### b) `DS_AzureSql_Table`
1. + → Dataset → **Azure SQL Database** → Name `DS_AzureSql_Table`, linked service `LS_AzureSql`, Table name: none, Import schema: None → OK.
2. **Parameters**: `pSchema`, `pTable`.
3. **Connection** → Table: ✅ **Enter manually** → schema `@dataset().pSchema`, table `@dataset().pTable`.

---

## 1.4 Pipeline `PL_Ingest_Sales` (the most important one — build it by hand)

Author → + → **Pipeline** → Name `PL_Ingest_Sales` → Properties: Folder `Ingest`.
Click empty canvas → **Parameters** → + New: `pRunDate` (String, default `20261014`).
*Why a run-date parameter:* every run is tied to a **business date** → you can **backfill / rerun any date** without code change.

### Final design
```
SP_LogStart ──✔──► Copy_Sales_To_Stg ──✔──► SP_Load_FactSales ──✔──► SP_LogSuccess
                         │✘                         │✘
                         ▼                          ▼
               SP_LogFailure_Copy           SP_LogFailure_Load
                         │✔✘                        │✔✘
                         ▼                          ▼
                    Fail_Copy                   Fail_Load
```
✔ = Upon success, ✘ = Upon failure, ✔✘ = both (so `Fail_*` runs even if logging itself failed).

### Step A — `SP_LogStart` (Stored procedure activity)
1. Activities pane → *General* → drag **Stored procedure**. Name `SP_LogStart`.
2. **General** tab: Timeout `0.00:10:00`, **Retry 2**, Retry interval **60** s.
   - *Why retry here:* SQL connection blips (failover, throttling) are **transient** — auto-retry fixes them before a human is paged.
3. **Settings** tab: Linked service `LS_AzureSql`; Stored procedure name `[ops].[usp_LogRunStart]`; click **Import** (parameters appear).
4. Set values (each via *Add dynamic content*):

   | Parameter | Value | Meaning |
   |---|---|---|
   | RunId | `@pipeline().RunId` | Unique GUID of this run — **the key you put in every ticket** |
   | PipelineName | `@pipeline().Pipeline` | |
   | TriggerName | `@pipeline().TriggerName` | Who started it (schedule vs manual) |
   | RunDate | `@pipeline().parameters.pRunDate` | business date |

### Step B — `Copy_Sales_To_Stg` (Copy data activity)
1. Drag **Copy data** (Move & transform). Name `Copy_Sales_To_Stg`. Connect **green (success)** handle from `SP_LogStart` to it.
2. **General**: Timeout `0.01:00:00`; **Retry 0** (lab: fail fast so you see errors immediately; prod often 1–2).
3. **Source**: Dataset `DS_ADLS_Csv`, parameters:
   - pContainer `landing` · pFolder `sales` · pFileName → dynamic: `@concat('sales_', pipeline().parameters.pRunDate, '.csv')`
   - File path type: **File path in dataset**; Recursively: off.
   - *Why exact filename (not wildcard):* if the file is missing the copy **fails** (good — we want to know). A wildcard with no matches can succeed with 0 rows = silent data loss.
4. **Sink**: Dataset `DS_AzureSql_Table` → pSchema `stg`, pTable `Sales`; Write behavior **Insert**; **Pre-copy script**: `TRUNCATE TABLE stg.Sales`.
   - *Why truncate staging:* staging holds **only this run's file** → rerun-safe.
5. **Mapping** → **Import schemas** (enter test values when prompted: pRunDate `20261014`) → make sure the mapping is:

   | Source | Destination |
   |---|---|
   | order_id | OrderId |
   | order_date | OrderDate |
   | customer_id | CustomerId |
   | product_id | ProductId |
   | quantity | Quantity |
   | unit_price | UnitPrice |
   | amount | Amount |
   | store_code | StoreCode |

   *Why explicit mapping:* if the vendor renames a column, the copy fails with a clear error instead of silently loading NULLs (this is the E2E exercise).
6. **Settings**: Fault tolerance **unchecked** (default). Enable logging off. *(In S2 we discuss "Skip incompatible rows".)*

### Step C — `SP_Load_FactSales`
Stored procedure, connect ✔ from Copy. Retry 2/60. `[dbo].[usp_Load_Sales]` → Import → RunDate `@pipeline().parameters.pRunDate`, RunId `@pipeline().RunId`.
*What it does:* DQ gates (empty, duplicates, negatives, wrong date) → `DELETE` that LoadDate → `INSERT` → idempotent.

### Step D — `SP_LogSuccess`
Stored procedure, ✔ from `SP_Load_FactSales`. `[ops].[usp_LogRunEnd]` → Import:

| Param | Value |
|---|---|
| RunId | `@pipeline().RunId` |
| Status | `Succeeded` (plain text) |
| RowsRead | `@activity('Copy_Sales_To_Stg').output.rowsRead` |
| RowsWritten | `@activity('Copy_Sales_To_Stg').output.rowsCopied` |
| PipelineName | `@pipeline().Pipeline` |
| RunDate | `@pipeline().parameters.pRunDate` |
| others | leave **Treat as null** ✅ |

*Why pass PipelineName/RunDate again at the end?* **Rerun from failed activity** creates a *new* RunId but does **not** re-execute `SP_LogStart` (it already succeeded). The procedure then creates the missing log row itself. Logging that breaks on rerun is a classic support blind spot.

*Why log row counts:* health check **HC03** reconciles them against the table → catches duplicates/lost rows.

### Step E — failure path for the Copy
1. Add Stored procedure `SP_LogFailure_Copy`. On `Copy_Sales_To_Stg` click the **(+)** / ✘ red handle → **Upon failure** → connect to `SP_LogFailure_Copy`.
2. `[ops].[usp_LogRunEnd]` → Status `Failed`, FailedActivity `Copy_Sales_To_Stg`, ErrorCode `ERR_COPY_SALES`, ErrorMessage `@activity('Copy_Sales_To_Stg').error.message`, RunId `@pipeline().RunId`, PipelineName `@pipeline().Pipeline`, RunDate `@pipeline().parameters.pRunDate`.
   - *What happens inside:* log row updated **and** `ops.usp_RaiseIncident` creates (or de-duplicates) a ticket → **auto incident logging**.
3. Add **Fail** activity (General) `Fail_Copy`; connect from `SP_LogFailure_Copy` with **Upon completion** (= success or failure).
   - Message: `@concat('Copy_Sales_To_Stg failed: ', activity('Copy_Sales_To_Stg').error.message)` · Error code `ERR_COPY_SALES`.
   - ⚠️ **Why the Fail activity is mandatory:** ADF evaluates pipeline status from the activities that ran. If a failure is "handled" by an *Upon failure* path that succeeds, the **pipeline can end as Succeeded** → no alert fires → incident is invisible. `Fail` forces **Failed** status with your own error code.

### Step F — failure path for the load
Same pattern: `SP_LogFailure_Load` (✘ from `SP_Load_FactSales`; FailedActivity `SP_Load_FactSales`, ErrorCode `ERR_LOAD_SALES`, message `@activity('SP_Load_FactSales').error.message`) → `Fail_Load`.

### Step G — validate & publish
1. Toolbar **Validate** → fix any errors.
2. **Debug** → pRunDate `20261014` → watch Output tab. All green? 
3. **Publish all**.
   - *Debug vs triggered:* Debug runs use your unpublished canvas and show in Monitor under the **Debug** filter; **rerun options in Monitor are for triggered runs** — so in all scenarios use **Add trigger → Trigger now**.

### Shortcut (paste JSON)
For each pipeline you may instead create an empty pipeline with the exact name → click **`{}`** (Code) at the top-right → replace the JSON with the file from `adf/pipeline/` → OK. Linked services and datasets must already exist with the same names.

---

## 1.5 Pipeline `PL_Ingest_Customers`
Identical pattern to sales (copy by JSON `adf/pipeline/PL_Ingest_Customers.json` or rebuild):
- Copy source folder `customers`, file `@concat('customers_', pipeline().parameters.pRunDate, '.csv')` → sink `stg.Customers`, pre-copy `TRUNCATE TABLE stg.Customers`, mapping `customer_id→CustomerId, customer_name→CustomerName, city→City, segment→Segment, signup_date→SignupDate`.
- `SP_Load_DimCustomer` → `[dbo].[usp_Load_Customers]` (MERGE, SCD-1).
- Error codes `ERR_COPY_CUSTOMERS`, `ERR_LOAD_CUSTOMERS`.

---

## 1.6 Pipeline `PL_Master_Daily` (orchestrator)

```
SP_LogStart ─✔─► Exec_Ingest_Customers ─✔─► Exec_Ingest_Sales ─✔─► SP_Build_Report ─✔─► SP_LogSuccess
                                                                          │ ✘ (Failed)  │ ⤼ (Skipped)
                                                                          └──────┬──────┘
                                                                        SP_LogFailure_Master ─✔✘─► Fail_Master
```

1. Parameter `pRunDate` (default `20261014`).
2. **Execute Pipeline** activities `Exec_Ingest_Customers` → invoked pipeline `PL_Ingest_Customers`, ✅ **Wait on completion**, parameter pRunDate = `@pipeline().parameters.pRunDate`. Same for `Exec_Ingest_Sales`.
   - *Why wait on completion:* without it the parent continues immediately and **can't see the child's failure**.
3. `SP_Build_Report` → `[rpt].[usp_Build_DailySalesSummary]` (RunDate, RunId).
4. **Generic error handler:** connect `SP_Build_Report` to `SP_LogFailure_Master` with **both Upon failure and Upon skip**.
   - *Why this works:* if *any* earlier step fails, the following steps are **Skipped**; the last step is therefore either Failed or Skipped → one handler covers the whole chain. Multiple conditions from the **same** activity are OR-ed.
5. `SP_LogFailure_Master`: ErrorCode `ERR_MASTER`, ErrorMessage `@concat('Daily master load failed for business date ', pipeline().parameters.pRunDate, '. Drill into child pipeline runs in ADF Monitor. Master RunId=', pipeline().RunId)` → creates a **P2** ticket (master = business impact) while the child creates a **P3** technical ticket → in Lab 4 you **link** them (parent/child incidents).
6. `Fail_Master` after it (Upon completion).

## 1.7 Pipeline `PL_HealthCheck`
1. **Lookup** `Lookup_RunHealthChecks`: dataset `DS_AzureSql_Table` (pSchema `ops`, pTable `HealthCheckResult` — only needed because Lookup requires a dataset), Use query: **Stored procedure** `[ops].[usp_RunHealthChecks]` → Import → RunDate `@pipeline().parameters.pRunDate`; ✅ First row only. Retry 2.
2. **If Condition** `If_AnyCheckFailed` (✔ from Lookup) → Expression `@greater(int(activity('Lookup_RunHealthChecks').output.firstRow.FailCount), 0)` → **True** branch: **Fail** activity `Fail_HealthCheck` with message from the JSON file.
   - *Why fail the pipeline:* a failed health-check pipeline triggers the **same** Azure Monitor alert → one detection path for "broken" and "wrong".

## 1.8 Triggers (Manage → Triggers → + New)

| Name | Type | Schedule | Pipeline & parameter |
|---|---|---|---|
| `TR_Daily_0200_IST` | Schedule | Every 1 day at 02:00, time zone **(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi**, start **2026-12-01** | `PL_Master_Daily`, pRunDate = `@formatDateTime(addDays(convertFromUtc(trigger().scheduledTime, 'India Standard Time'), -1), 'yyyyMMdd')` |
| `TR_Hourly_HealthCheck` | Schedule | Every 1 hour, start 2026-12-01 03:15 IST | `PL_HealthCheck`, same expression |

Attach via the pipeline: Author → pipeline → **Add trigger → New/Edit** → choose trigger → OK → enter parameter → **Publish**. Then Manage → Triggers → **Start** `TR_Daily_0200_IST` (status *Started*). Leave the hourly one *Stopped* during the lab.
- *Why start date in the future:* it keeps the trigger **Started** (realistic) without firing on its own during class and polluting your scenarios.
- *Why yesterday's date:* at 02:00 we load the **previous business day**.
- *Why time zone:* schedules default to UTC; IST avoids "it ran at 07:30 AM" surprises (UTC+5:30).

---

## 1.9 Baseline run & verification (this is "normal" — remember it)

1. Author → `PL_Master_Daily` → **Add trigger → Trigger now** → pRunDate `20261013` → OK.
2. Monitor → **Pipeline runs** → wait for Succeeded (≈2–4 min). Click the master run name → see the **activity runs** list and the **Gantt** view. Click the Execute Pipeline activity's output icon → note the child `pipelineRunId`.
3. Trigger now again with `20261014`.
4. Run `PL_HealthCheck` with Trigger now → pRunDate `20261014` → must be **Succeeded**.
5. Query editor:
```sql
SELECT PipelineName, RunDate, Status, RowsRead, RowsWritten, DurationSec FROM ops.PipelineRunLog ORDER BY LogId;
SELECT LoadDate, COUNT(*) Rows_, SUM(Amount) Revenue FROM dbo.FactSales GROUP BY LoadDate;
SELECT * FROM ops.vw_LatestHealth ORDER BY CheckId;
SELECT COUNT(*) AS OpenIncidents FROM ops.Incident;   -- expect 0
```
6. Compare with `data/EXPECTED_VALUES.md`: **20261013 → 40 rows / 126957.50**, **20261014 → 50 rows / 144809.95**.

| Baseline fact | Your value |
|---|---|
| Master duration (min) | |
| Child sales duration (min) | |
| Rows 20261014 | 50 |
| Health checks | all PASS (HC08 may be WARN/PASS) |

> 📌 **Support mindset:** knowing what *normal* looks like (duration, row counts) is how you recognise *abnormal* at 3 AM.

➡️ Next: `04_Lab2_Monitoring_Alerting_HealthChecks.md`
