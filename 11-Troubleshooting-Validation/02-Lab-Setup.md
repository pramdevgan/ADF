# 02 – Hands-on Part A: Lab Setup – build the "ShopKart" daily load (25 min)

**Goal:** build the production-style pipeline `PL_20_Daily_Orders_Load` that you will break and investigate in Part B.

**You reuse from Module 1:** resource group `rg-adf-lab`, storage account `stadflab<initials>` (container `input`), Data Factory `adf-lab-<initials>`, Azure SQL `sqldb-adflab`, linked services `LS_BlobStorage` and `LS_AzureSqlDb`.

> ⚠️ This module **needs the Azure SQL database** (File 01 Step 6 of Module 1). If you skipped it, create it now (5 min).

```
PL_20_Daily_Orders_Load   (parameter p_LoadDate = 'yyyy-MM-dd')

[SetFileName] → [CheckFileExists] → [IfFileMissing] → [CopyToStaging] → [LoadFact] → [ValidateLoad] → [LogSuccess]
 Set variable    Get Metadata       If Condition        Copy data         Stored proc   Stored proc     Stored proc
 v_FileName      exists?            True → Fail          CSV → stg.Orders  stg → fact    quality gate    audit.LoadLog
```

| Step | What | Time |
|---|---|---|
| A1 | Upload data files | 3 min |
| A2 | Run SQL scripts | 4 min |
| A3 | Create 2 datasets | 4 min |
| A4 | Build the pipeline (7 activities) | 11 min |
| A5 | Baseline run for 2026-10-01 + verify | 3 min |

---

## A1. Upload the data files (3 min)

Portal → storage account `stadflab<initials>` → **Containers** → `input` → **Upload** → expand **Advanced** → **Upload to folder** = `orders` → select **all 5 files** from `data/upload/`:

| File | Used for | What is special |
|---|---|---|
| `orders_20261001.csv` | Baseline + incidents 2, 3, 4 | Clean, 20 rows |
| `orders_20261002.csv` | Part C validation | 22 rows, **hidden quality problems** (pipeline will still succeed) |
| `Orders_20261003.csv` | Incident 1 – missing file | Capital **O** in the name |
| `orders_20261004.csv` | Incident 5a – schema drift | Column `Unit_Price` + extra `Discount` |
| `orders_20261005.csv` | Incident 5b – bad formats | dd/MM/yyyy dates, `N/A` quantity, `12,000.00` price |

> **Do not** upload anything from `data/fixes/` yet. Those are the "corrected files from the vendor" you'll use during the incidents.

Result:
```
input/orders/
  orders_20261001.csv
  orders_20261002.csv
  Orders_20261003.csv
  orders_20261004.csv
  orders_20261005.csv
```

---

## A2. Create database objects (4 min)

Portal → SQL database `sqldb-adflab` → **Query editor (preview)** → log in (SQL authentication).

Run the scripts **one file at a time**: open the file, copy everything, paste, click **Run**, then clear the editor before the next file.

| Order | Script | Creates | Expected result |
|---|---|---|---|
| 1 | `sql/01-setup-tables.sql` | Schemas `stg`, `dim`, `audit`; 8 tables; master + control data | Last result: 15, 6, 5 |
| 2 | `sql/02-usp_Load_Orders.sql` | `dbo.usp_Load_Orders` | "Query succeeded" |
| 3 | `sql/03-usp_Validate_Load.sql` | `audit.usp_Validate_Load` | "Query succeeded" |
| 4 | `sql/04-usp_Log_Run.sql` | `audit.usp_Log_Run` | "Query succeeded" |

**Why one at a time?** `CREATE PROCEDURE` must be the only statement in its batch, and the portal Query editor doesn't understand `GO`. (In SSMS / Azure Data Studio you could join the files with `GO`.)

### What each object does (the design)

| Object | Layer | Purpose |
|---|---|---|
| `stg.Orders` | **Staging** | Raw copy of the file. **All columns NVARCHAR**, so the file always lands, even with bad values |
| `dbo.FactOrders` | **Target** | Typed, clean table used by reports. `Amount` is a computed column |
| `dim.Customer`, `dim.Product` | **Master/reference** | For referential-integrity checks |
| `audit.SourceControl` | **Control/manifest** | Row count + total amount the vendor says they sent. The "source of truth" for reconciliation |
| `audit.RejectedOrders` | **Quarantine** | Rows that failed type conversion, with a reason |
| `audit.ValidationResults` | **Evidence** | Result of every check for every run |
| `audit.LoadLog` | **Audit** | One row per successful load |
| `usp_Load_Orders` | Transform | `TRY_CONVERT` each value; bad rows go to reject, good rows to fact; deletes the same date first (**idempotent** = safe to rerun) |
| `usp_Validate_Load` | **Quality gate** | 11 checks; **THROW** on any CRITICAL failure so the ADF activity goes red |

Quick test (optional):
```sql
SELECT name, SCHEMA_NAME(schema_id) AS sch FROM sys.procedures;   -- 3 procedures
```

---

## A3. Create the datasets (4 min)

ADF Studio → **Author** → **+** → **Dataset**.

### Dataset 1: `DS_Orders_Csv` (parameterized source file)
1. **Azure Blob Storage** → Continue → **DelimitedText** → Continue.
2. Name `DS_Orders_Csv` · Linked service `LS_BlobStorage` · leave File path empty · ✅ First row as header · Import schema **None** → OK.
   *Why None:* the file name changes every day, and Day 4's file has different columns. A fixed schema here would hide schema drift.
3. **Parameters** tab → **+ New**: `p_file`, String, default `orders_20261001.csv`.
4. **Connection** tab → File path: container `input` · directory `orders` · file → **Add dynamic content** → `@dataset().p_file`.
5. Click **Preview data**, accept the default value → you see 20 rows.

### Dataset 2: `DS_Sql_Stg_Orders` (staging table)
1. **+ → Dataset → Azure SQL Database** → Continue.
2. Name `DS_Sql_Stg_Orders` · Linked service `LS_AzureSqlDb` · Table `stg.Orders` · Import schema **From connection/store** → OK.

**Publish all.**

---

## A4. Build the pipeline (11 min)

**Author → + → Pipeline** → name `PL_20_Daily_Orders_Load`.

Click the empty canvas:
- **Parameters** tab → **+ New** → `p_LoadDate`, String, default `2026-10-01`.
  *Why a parameter:* the same pipeline loads any day. The trigger passes today's date, and an engineer can rerun a past day by hand. This is essential for troubleshooting.
- **Variables** tab → **+ New** → `v_FileName`, String.
- **Properties** (📄 icon, top right) → Annotations: `module3`.

### Activity 1: `SetFileName` (General → Set variable)
| Setting | Value |
|---|---|
| Variable type | Pipeline variable |
| Name | `v_FileName` |
| Value | `@concat('orders_', replace(pipeline().parameters.p_LoadDate,'-',''), '.csv')` |

*What it does:* `2026-10-01` → `orders_20261001.csv`. The file-naming rule lives in **one** place, and its output is visible in Monitor, which helps a lot during the trigger incident.

### Activity 2: `CheckFileExists` (General → Get Metadata) – connect from SetFileName (Success)
| Setting | Value |
|---|---|
| Dataset | `DS_Orders_Csv` → p_file = `@variables('v_FileName')` |
| Field list → + New | **Exists**, **Size**, **Last modified** |

*Why:* without **Exists**, Get Metadata (and Copy) throw a generic "path does not exist" error. With **Exists**, a missing file returns `{"exists": false}` and **we** decide the error message. Size and Last modified are evidence for the RCA (empty file? old file?).

### Activity 3: `IfFileMissing` (Iteration & conditionals → If Condition) – from CheckFileExists (Success)
- Expression: `@not(activity('CheckFileExists').output.exists)`
- **True** → ✏️ → add **General → Fail** activity named `Fail_FileNotFound`:

| Setting | Value |
|---|---|
| Fail message | `@concat('FILE_NOT_FOUND: input/orders/', variables('v_FileName'), ' not found for LoadDate ', pipeline().parameters.p_LoadDate)` |
| Error code | `404` |

- **False** → leave empty. Go back to the main canvas with the breadcrumb.

*Why a Fail activity:* it turns a vague platform error into a **clear, searchable business error**. On-call staff instantly know what is missing.

### Activity 4: `CopyToStaging` (Move and transform → Copy data) – from IfFileMissing (Success)

**General:** Timeout `0.01:00:00` (1 h), Retry `0` (kept at 0 so the incidents fail quickly; use 2–3 in production).

**Source:**
| Setting | Value | Why |
|---|---|---|
| Source dataset | `DS_Orders_Csv`, p_file = `@variables('v_FileName')` | |
| File path type | File path in dataset | |
| Additional columns → + New | `SourceFile` = `$$FILEPATH` | Lineage: which file each row came from |
| Additional columns → + New | `RunId` = (dynamic content) `@pipeline().RunId` | Lets you trace a row in SQL back to the ADF run |

**Sink:**
| Setting | Value | Why |
|---|---|---|
| Sink dataset | `DS_Sql_Stg_Orders` | |
| Write behavior | Insert | |
| Pre-copy script | `TRUNCATE TABLE stg.Orders` | Staging holds **only today's** file |
| Table option | None (use existing) | |

**Mapping:** click **Import schemas**. When asked for the debug value of `p_file`, keep `orders_20261001.csv`. You should get **9 mapped rows**:

| Source | → | Destination |
|---|---|---|
| OrderID, OrderDate, CustomerID, ProductID, Quantity, UnitPrice, Status | → | same names |
| SourceFile, RunId (additional columns) | → | SourceFile, RunId |

If SourceFile/RunId don't map automatically, pick them in the destination dropdown.

> 💡 **Why explicit mapping matters (Incident 5a):** once mapping is imported, ADF expects these exact source column names. If the vendor renames a column, the copy **fails loudly**. Without explicit mapping, the renamed column would silently become NULL.

### Activity 5: `LoadFact` (General → Stored procedure) – from CopyToStaging (Success)
1. **Settings** → Linked service `LS_AzureSqlDb` → Stored procedure name `[dbo].[usp_Load_Orders]`.
2. **Stored procedure parameters → Import**, then set:

| Name | Type | Value (dynamic content) |
|---|---|---|
| LoadDate | String | `@pipeline().parameters.p_LoadDate` |
| RunId | String | `@pipeline().RunId` |

### Activity 6: `ValidateLoad` (Stored procedure) – from LoadFact (Success)
`[audit].[usp_Validate_Load]` → Import:

| Name | Type | Value |
|---|---|---|
| LoadDate | String | `@pipeline().parameters.p_LoadDate` |
| RunId | String | `@pipeline().RunId` |
| SourceRows | Int32 | `@activity('CopyToStaging').output.rowsRead` |

*Why rowsRead:* this is what ADF actually read from the file, which is the **source side** of the row-count reconciliation.

### Activity 7: `LogSuccess` (Stored procedure) – from ValidateLoad (Success)
`[audit].[usp_Log_Run]` → Import:

| Name | Type | Value |
|---|---|---|
| PipelineName | String | `@pipeline().Pipeline` |
| RunId | String | `@pipeline().RunId` |
| LoadDate | String | `@pipeline().parameters.p_LoadDate` |
| Status | String | `Succeeded` |
| RowsRead | Int32 | `@activity('CopyToStaging').output.rowsRead` |
| RowsCopied | Int32 | `@activity('CopyToStaging').output.rowsCopied` |
| Message | String | `Load and validation passed` |

**Validate** → **Publish all**.

> Stuck? Paste `pipeline-json/pipeline_PL_20_Daily_Orders_Load.json` into the pipeline's `{ }` code view.

---

## A5. Baseline run – prove it works (3 min)

1. **Add trigger → Trigger now** → p_LoadDate = `2026-10-01` → OK.
2. Monitor → Pipeline runs → **Succeeded**, with all 7 activities green and the If's False branch empty.
3. SQL Query editor:
```sql
SELECT * FROM audit.LoadLog;
-- ✅ 1 row: 2026-10-01 | Succeeded | RowsRead 20 | RowsCopied 20 | FactRows 20 | RejectedRows 0

SELECT CheckName, Severity, Expected, Actual, Result
FROM audit.ValidationResults WHERE LoadDate = '2026-10-01';
-- ✅ 11 checks, all PASS

SELECT COUNT(*) AS Rows, SUM(Amount) AS Total FROM dbo.FactOrders WHERE LoadDate = '2026-10-01';
-- ✅ 20 | 444100.00  (matches audit.SourceControl)
```

✅ **Baseline is green. Note the time and Run ID; this is your "known good" reference for the incidents.**

➡️ Next: `03-Incidents-Hands-on.md`
