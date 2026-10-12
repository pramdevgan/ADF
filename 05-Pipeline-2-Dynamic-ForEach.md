# 05 – Pipeline 2: Dynamic Multi-file Copy (Get Metadata → Filter → ForEach → Copy) (≈ 30 min)

**Goal:** list every file in `input/sales/`, keep only `.csv` files, and copy each one to `archive/<today's date>/` – using **one** parameterized dataset. This is the classic **metadata-driven pattern**.

```
[Get Metadata: GetSalesFiles] ──success──► [Filter: OnlyCsv] ──success──► [ForEach: ForEachFile]
                                                                               └─ [Copy data: CopyOneFile]
```

---

## Step 1 – Create pipeline & parameters

1. **Author → + → Pipeline** → Name `PL_02_Copy_All_Sales_Files`.
2. Click empty canvas → bottom pane **Parameters** tab → **+ New**:

| Name | Type | Default | Why |
|---|---|---|---|
| `p_SourceFolder` | String | `sales` | Change the folder at run time without editing the pipeline |
| `p_TargetContainer` | String | `archive` | |

**Parameters vs Variables**
- *Parameter* = input value supplied when the run **starts**; read-only during the run. `@pipeline().parameters.p_SourceFolder`
- *Variable* = value you can **change during** the run with *Set variable / Append variable*. `@variables('v_name')`

---

## Step 2 – Get Metadata activity

1. Activities → **General** → drag **Get Metadata**. Name: `GetSalesFiles`.
2. **Settings** tab:

| Field | Value | What it does |
|---|---|---|
| Dataset | `DS_Blob_Folder_Binary` (points to `input/sales`) | The folder to inspect |
| Field list → **+ New** | **Child items** | Returns array of `{ "name": "...", "type": "File"/"Folder" }` |
| (optional) + New | Item name, Last modified, Exists | Other metadata fields; *Exists* is handy for "does file exist?" checks |

> Why Get Metadata? It retrieves **information about data** (not the data) so the pipeline can decide dynamically what to process.

3. **Debug** now (only this activity) → open **Output**:
   ```json
   {
     "childItems": [
       {"name": "sales_2026_01.csv", "type": "File"},
       {"name": "sales_2026_02.csv", "type": "File"},
       {"name": "sales_2026_03.csv", "type": "File"}
     ],
     "effectiveIntegrationRuntime": "AutoResolveIntegrationRuntime (Central India)"
   }
   ```

---

## Step 3 – Filter activity

1. Activities → **Iteration & conditionals** → **Filter**. Name: `OnlyCsv`.
2. Connect: drag the **green (Success)** handle of `GetSalesFiles` onto `OnlyCsv`.
3. **Settings**:

| Field | Expression | Meaning |
|---|---|---|
| Items | `@activity('GetSalesFiles').output.childItems` | Input array |
| Condition | `@and(equals(item().type,'File'), endswith(item().name,'.csv'))` | Keep only CSV files (skip sub-folders) |

Output: `{ "ItemsCount": 3, "FilteredItemsCount": 3, "Value": [ ... ] }`

---

## Step 4 – ForEach activity

1. Activities → **Iteration & conditionals** → **ForEach**. Name: `ForEachFile`. Connect from `OnlyCsv` (Success).
2. **Settings**:

| Field | Value | What it does |
|---|---|---|
| Sequential | unchecked | Unchecked = parallel iterations (faster). Check it when order matters |
| Batch count | `3` | Max parallel iterations (default 20, max 50) |
| Items | `@activity('OnlyCsv').output.Value` | Array to loop over; each element = `@item()` |

3. **Activities** tab inside ForEach → click the ✏️ pencil to open the inner canvas.

---

## Step 5 – Copy activity inside ForEach

Inner canvas → drag **Copy data**, name `CopyOneFile`.

**Source tab**
- Source dataset: `DS_Generic_CSV` → the dataset parameters appear:

| Parameter | Value (Add dynamic content) |
|---|---|
| p_container | `input` |
| p_folder | `@pipeline().parameters.p_SourceFolder` |
| p_file | `@item().name` |

**Sink tab**
- Sink dataset: `DS_Generic_CSV` (same dataset reused!):

| Parameter | Value |
|---|---|
| p_container | `@pipeline().parameters.p_TargetContainer` |
| p_folder | `@formatDateTime(utcnow(),'yyyy-MM-dd')` |
| p_file | `@item().name` |

- File extension: `.csv`

Go back to the main canvas via the breadcrumb `PL_02_Copy_All_Sales_Files`.

---

## Step 6 – Validate, Debug, Publish, Trigger

1. **Validate**.
2. **Debug** → a dialog asks for parameter values (defaults pre-filled) → **OK**.
3. In Output you'll see: 1 × GetSalesFiles, 1 × OnlyCsv, 1 × ForEachFile, **3 × CopyOneFile** (one per iteration, running in parallel).
4. Verify: `archive/2026-10-12/sales_2026_01.csv` … `_03.csv` exist.
5. **Publish all** → **Add trigger → Trigger now** → change `p_SourceFolder` if you want → OK.
6. **Monitor** → open the run → note iterations are listed as separate activity runs.

### Why this pattern matters
- Add a 4th file to `input/sales` → rerun → it is copied automatically – **no pipeline changes**.
- One dataset + parameters scales to hundreds of files/tables.

### Exercise
Add a **Delete** activity (General → Delete) after `CopyOneFile` inside the loop, dataset `DS_Generic_CSV` with `input` / `p_SourceFolder` / `@item().name` → the pipeline now **moves** files. (Re-upload sales files afterwards!)

✅ **Checkpoint:** 3 files in `archive/<date>/`; Monitor shows 6 activity runs.

Reference JSON: `pipeline-json/pipeline_PL_02_Copy_All_Sales_Files.json`
