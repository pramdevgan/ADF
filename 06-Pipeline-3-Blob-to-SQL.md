# 06 – Pipeline 3: Load CSV into Azure SQL + Log the Run (≈ 20 min, optional)

**Goal:** load `employees.csv` into table `dbo.Employees` (with typed columns), then insert an audit row into `dbo.PipelineRunLog` using the copy statistics.

```
[Copy data: CopyToSql] ──success──► [Script: LogSuccess]
        └──────────failure──────► [Script: LogFailure]
```

Prerequisites: Step 6 of File 01 (SQL DB + `sql/01-create-tables.sql`), `LS_AzureSqlDb`, `DS_Sql_Employees`.

---

## Step 1 – Pipeline

**Author → + → Pipeline** → `PL_03_Load_Employees_To_Sql`.

## Step 2 – Copy activity `CopyToSql`

**Source:** `DS_Employees_CSV`.

**Sink:**

| Field | Value | What it does |
|---|---|---|
| Sink dataset | `DS_Sql_Employees` | |
| Write behavior | **Insert** | Other options: *Upsert* (needs key columns – update if exists else insert), *Stored procedure* (custom logic) |
| Bulk insert table lock | No | Table lock speeds up large loads |
| Table option | **Use existing** | *Auto create table* creates the table from source schema if missing |
| Pre-copy script | `TRUNCATE TABLE dbo.Employees` | Runs **before** the load → makes the pipeline **re-runnable (idempotent)** – no duplicates on rerun |
| Write batch size / timeout | blank | Rows per batch – tune for large data |
| Max concurrent connections | blank | |

**Mapping tab → Import schemas.** ADF maps CSV columns (strings) to SQL types:

| Source (String) | Sink column | Sink type |
|---|---|---|
| EmpID | EmpID | int |
| Name | Name | nvarchar |
| Department | Department | nvarchar |
| City | City | nvarchar |
| Salary | Salary | decimal |
| JoinDate | JoinDate | date |

ADF performs **implicit type conversion**. If a value can't convert (e.g. `abc` into int) the copy fails – unless **Settings → Fault tolerance → Skip incompatible rows** is enabled.

## Step 3 – Script activity `LogSuccess`

1. Activities → **General** → **Script**. Name `LogSuccess`. Connect from `CopyToSql` with **Success** (green).
2. **Settings**:

| Field | Value |
|---|---|
| Linked service | `LS_AzureSqlDb` |
| Script type | **NonQuery** (no result set returned; *Query* returns rows) |
| Script | see below |

```sql
INSERT INTO dbo.PipelineRunLog (PipelineName, RunId, Status, RowsCopied, LogTime)
VALUES ('@{pipeline().Pipeline}', '@{pipeline().RunId}', 'Succeeded',
        @{activity('CopyToSql').output.rowsCopied}, SYSUTCDATETIME());
```

`@{ ... }` = **string interpolation**: ADF evaluates the expression and pastes the result into the SQL text before sending it.

## Step 4 – Script activity `LogFailure`

Same as above but:
- Connect from `CopyToSql` using the **Failure** (red ✖) handle: hover the Copy activity → click **+** (or the ✖ handle) → **Failure** → drag to `LogFailure`.
- Script:
```sql
INSERT INTO dbo.PipelineRunLog (PipelineName, RunId, Status, RowsCopied, ErrorMessage, LogTime)
VALUES ('@{pipeline().Pipeline}', '@{pipeline().RunId}', 'Failed', 0,
        '@{replace(activity('CopyToSql').error.message, '''', '')}', SYSUTCDATETIME());
```
(`replace(...,'''','')` removes single quotes from the error so the SQL doesn't break.)

## Step 5 – Run & verify

1. **Debug** → expect `CopyToSql` ✅ → `LogSuccess` ✅, `LogFailure` shown as **Skipped**.
2. SQL Query editor:
```sql
SELECT * FROM dbo.Employees;
SELECT * FROM dbo.PipelineRunLog ORDER BY LogTime DESC;
```
3. **Debug again** – row count in `Employees` stays 10 (thanks to TRUNCATE pre-copy script).

## Step 6 – Force a failure (to see the Failure path)

1. Upload `sample-data/employees_bad.csv` to `input/` **renamed as** `employees.csv` (overwrite) – it contains `EmpID = ABC`.
2. **Debug** → `CopyToSql` ❌ → `LogFailure` ✅ → `LogSuccess` Skipped.
3. Note: the **pipeline status** – see File 07, section "How ADF decides pipeline status".
4. Re-upload the good `employees.csv`.

✅ **Checkpoint:** `dbo.Employees` has 10 rows, `dbo.PipelineRunLog` has Succeeded and Failed entries.

Reference JSON: `pipeline-json/pipeline_PL_03_Load_Employees_To_Sql.json`
