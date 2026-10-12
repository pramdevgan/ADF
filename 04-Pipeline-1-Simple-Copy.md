# 04 – Pipeline 1: Simple Copy (CSV → CSV) (≈ 25 min)

**Goal:** copy `input/employees.csv` to `output/employees_copy.csv`, run it in **Debug**, **Publish**, then run with **Trigger now** and observe it in **Monitor**.

```
[ Copy data: CopyEmployees ]
   source: DS_Employees_CSV  ──►  sink: DS_Output_CSV
```

---

## Step 1 – Create the pipeline

1. **Author → + → Pipeline → Pipeline**.
2. **Properties** pane (right, toggle with the 📄 icon top-right):

| Field | Value | Why |
|---|---|---|
| Name | `PL_01_Copy_Employees` | `PL_` prefix + number keeps pipelines sorted |
| Description | Copy employees CSV from input to output | |
| Annotations | `lab` | Tags you can filter on in Monitor |

---

## Step 2 – Add the Copy activity

1. **Activities** pane → expand **Move and transform** → drag **Copy data** onto the canvas.
   *Why Copy data:* the core data-movement activity – reads from a source dataset, optionally converts format/maps columns, writes to a sink. Runs on the Integration Runtime.

### General tab

| Field | Value | What it does |
|---|---|---|
| Name | `CopyEmployees` | Referenced in expressions: `@activity('CopyEmployees')` – avoid spaces |
| Timeout | `0.12:00:00` (default 12 h) | Run is failed if longer. Format `d.hh:mm:ss` |
| Retry | `0` (try `2` in production) | Auto-retry on transient failures |
| Retry interval (sec) | 30 | Wait between retries |
| Secure output / Secure input | unchecked | When checked, input/output is hidden from Monitor logs (for secrets) |

### Source tab

| Field | Value | What it does |
|---|---|---|
| Source dataset | `DS_Employees_CSV` | Where to read |
| File path type | **File path in dataset** | Other choices: *Wildcard file path* (`*.csv`), *Prefix*, *List of files* (a text file listing paths) |
| Recursively | ✅ | Include sub-folders when pointing at a folder |
| Filter by last modified | blank | Incremental copy: only files changed in a time window |
| Enable partition discovery | unchecked | Parses `year=2026/month=01` style folders into columns |
| Max concurrent connections | blank | Limit parallel connections to the source |
| Additional columns | (optional) **+ New** → name `SourceFile`, value `$$FILEPATH` | Adds a column with the source file path – useful for lineage |
| Delete files after completion | unchecked | Moves (instead of copies) when checked |

Click **Preview data** to verify.

### Sink tab

| Field | Value | What it does |
|---|---|---|
| Sink dataset | `DS_Output_CSV` | Where to write |
| Copy behavior | *(none)* | For folder copies: *PreserveHierarchy*, *FlattenHierarchy*, *MergeFiles* |
| Max concurrent connections | blank | |
| File extension | `.csv` | |

### Mapping tab

1. Click **Import schemas**.
   *Why:* shows source column → sink column mapping. By default ADF maps **by name**. You can delete columns, rename the sink column, or set types (for typed sinks like SQL).
2. Exercise: uncheck nothing for now. (Try later: remove `Salary` to see column filtering.)

### Settings tab

| Field | Value | What it does |
|---|---|---|
| Data integration unit (DIU) | Auto | Compute power (CPU+memory+network) per copy on Azure IR. Min 2, max 256. Billing = DIU × duration |
| Degree of copy parallelism | Auto | Parallel threads reading/writing |
| Fault tolerance | none | *Skip incompatible rows* → bad rows are skipped (and optionally logged) instead of failing the copy |
| Enable logging | off | Logs copied/skipped files to storage |
| Enable staging | off | Uses interim Blob storage (needed e.g. for Synapse PolyBase, Snowflake) |
| Data consistency verification | off | Verifies file size/checksum after copy |

---

## Step 3 – Validate

Click **Validate** (toolbar). It checks required fields, broken references, expression syntax.
✅ "Your pipeline has been validated. No errors were found."

---

## Step 4 – Debug run

Click **Debug** (toolbar).

**What Debug does:**
- Runs the pipeline **as it is on your canvas**, even unpublished.
- Results show in the **Output** tab at the bottom of the canvas (not in Monitor's "Triggered" list; they appear under Monitor → Pipeline runs → **Debug** tab).
- Use it to test before publishing.

In the **Output** tab watch status: *Queued → In progress → Succeeded*.

Hover over the activity row and click:
- **→ Input** icon: the JSON ADF sent to the activity (source/sink config).
- **← Output** icon: run statistics, e.g.
  ```json
  {
    "dataRead": 512,
    "dataWritten": 520,
    "filesRead": 1,
    "filesWritten": 1,
    "rowsRead": 10,
    "rowsCopied": 10,
    "copyDuration": 4,
    "throughput": 0.1,
    "usedDataIntegrationUnits": 4,
    "usedParallelCopies": 1,
    "executionDetails": [ ... ]
  }
  ```
- **👓 Details** (glasses) icon: graphical copy monitoring – source, sink, rows, duration split into *Queue*, *Pre-copy script*, *Transfer (Reading from source / Writing to sink)*.

**Verify:** Azure portal → storage account → container **output** → `employees_copy.csv` exists → click it → **Edit** to view contents.

---

## Step 5 – Publish

**Publish all → Publish.**

| Debug | Publish + Trigger |
|---|---|
| Runs your draft canvas | Runs the **published** version |
| No trigger needed | Started by a trigger (manual or automatic) |
| Shown in Output tab / Monitor → Debug | Shown in Monitor → Pipeline runs → Triggered |
| For development | For production |

---

## Step 6 – Trigger now (manual trigger)

1. Toolbar **Add trigger → Trigger now** → **OK**.
   *What it does:* creates a one-off manual run of the **published** pipeline.
2. Go to **Monitor (📈) → Pipeline runs → Triggered** tab.

| Column | Meaning |
|---|---|
| Pipeline name | `PL_01_Copy_Employees` |
| Run start / end, Duration | Timing |
| Triggered by | `Manual trigger` |
| Status | Queued / In progress / Succeeded / Failed / Cancelled |
| Run ID | GUID – unique per run; useful for support & logging |
| Parameters | Values passed into this run |

3. Click the pipeline name → **Activity runs** view: Gantt-style list of each activity with input/output/details icons.

✅ **Checkpoint:** one successful Debug run and one successful Triggered run; `output/employees_copy.csv` exists.

### Try it (5 min exercise)
- Change the sink dataset format to **JSON** (create `DS_Output_JSON`) → run → observe CSV→JSON conversion. Copy activity converts formats automatically.
- Use a **Wildcard file path** in Source: folder `sales`, file `*.csv`, and sink copy behavior **MergeFiles** → three monthly files become one.

Reference JSON: `pipeline-json/pipeline_PL_01_Copy_Employees.json`
