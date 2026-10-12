# 03 – Configure Datasets (≈ 20 min)

## What is a Dataset?

A **dataset** is a **named view of data** inside a linked service: *which* file/folder/table and *what format* (CSV, JSON, Parquet, Excel, table…). Activities use datasets as **inputs (source)** and **outputs (sink)**.

```
LS_BlobStorage  (the account)
   ├── DS_Employees_CSV       → input/employees.csv
   ├── DS_Output_CSV          → output/employees_copy.csv
   ├── DS_Products_JSON       → input/products.json
   ├── DS_Blob_Folder_Binary  → input/sales/   (for Get Metadata)
   └── DS_Generic_CSV         → @{container}/@{folder}/@{file}  (parameterized)
LS_AzureSqlDb
   └── DS_Sql_Employees       → dbo.Employees
```

We create 6 datasets. All are created under **Author (✏️) → + (Factory Resources) → Dataset**.

---

## Dataset 1 – `DS_Employees_CSV` (source CSV)

1. **Author → + → Dataset**.
2. Select data store **Azure Blob Storage** → **Continue**.
3. Select format **DelimitedText** → **Continue**.
   *Why DelimitedText:* CSV/TSV/pipe-delimited files. Other formats: Parquet (columnar, compressed – best for analytics), JSON, Avro, ORC, Excel, XML, Binary (copy as-is, no parsing).
4. **Set properties** blade:

| Field | Value | What / Why |
|---|---|---|
| Name | `DS_Employees_CSV` | |
| Linked service | `LS_BlobStorage` | Which account |
| File path | Container `input` / Directory *(blank)* / File `employees.csv` | Use the 📁 browse button to avoid typos |
| First row as header | ✅ | Row 1 contains column names → used as schema |
| Import schema | **From connection/store** | ADF reads the file and detects columns. "None" = schema-less (more flexible, used for dynamic pipelines) |

5. **OK**. The dataset opens in a tab. Review the **Connection** tab:

| Setting | Default | Meaning |
|---|---|---|
| Compression type | None | gzip, bzip2, deflate, ZipDeflate, snappy, lz4, tar… |
| Column delimiter | Comma (,) | `;`, `|`, tab, etc. |
| Row delimiter | Default (\r, \n, or \r\n) | Line endings |
| Encoding | Default (UTF-8) | |
| Escape character | Backslash (\) | |
| Quote character | Double quote (") | Allows commas inside quoted values |
| First row as header | ✅ | |
| Null value | (empty) | String that should be treated as NULL |

6. Click **Preview data** → you should see 10 employee rows.
7. **Schema** tab → shows `EmpID, Name, Department, City, Salary, JoinDate` (all String – CSV has no types; types are applied at the sink or via mapping).

---

## Dataset 2 – `DS_Output_CSV` (sink CSV)

Repeat the steps with:

| Field | Value | Note |
|---|---|---|
| Name | `DS_Output_CSV` | |
| File path | `output` / *(blank)* / `employees_copy.csv` | The file doesn't exist yet – ADF creates it |
| First row as header | ✅ | Writes header row |
| Import schema | **None** | Nothing to import from a non-existent file |

---

## Dataset 3 – `DS_Products_JSON`

| Field | Value |
|---|---|
| Format | **JSON** |
| Name | `DS_Products_JSON` |
| File path | `input` / *(blank)* / `products.json` |
| Import schema | From connection/store |

In the **Connection** tab, **File pattern**: *Array of objects* (the file is `[ {...}, {...} ]`). The other option *Set of objects* = JSON Lines (one object per line). Preview data to confirm.

---

## Dataset 4 – `DS_Blob_Folder_Binary` (folder for Get Metadata)

| Field | Value | Why |
|---|---|---|
| Format | **Binary** | We only need the *list of files*, not their content |
| Name | `DS_Blob_Folder_Binary` | |
| File path | `input` / `sales` / *(file blank)* | Pointing to a **folder**; Get Metadata will list its children |

---

## Dataset 5 – `DS_Generic_CSV` (**parameterized** – reusable)

Instead of one dataset per file, create **one dataset** whose container/folder/file are supplied at runtime.

1. Create a DelimitedText dataset on `LS_BlobStorage`, Name `DS_Generic_CSV`, **leave file path empty**, First row as header ✅, Import schema **None** → OK.
2. Open the **Parameters** tab → **+ New** three times:

| Name | Type | Default value |
|---|---|---|
| `p_container` | String | `input` |
| `p_folder` | String | *(blank)* |
| `p_file` | String | `employees.csv` |

3. Go to **Connection** tab → click into the **container** box → **Add dynamic content** (or Alt+Shift+D) → pick parameter `p_container` → expression becomes:
   ```
   @dataset().p_container
   ```
   Repeat: directory → `@dataset().p_folder`, file → `@dataset().p_file`.

**Why parameterize?** One dataset serves hundreds of files/tables → fewer objects, metadata-driven pipelines. `@dataset()` refers to the dataset's own parameters; the *pipeline/activity* supplies the values.

---

## Dataset 6 – `DS_Sql_Employees` (optional)

1. **+ → Dataset → Azure SQL Database → Continue**.

| Field | Value |
|---|---|
| Name | `DS_Sql_Employees` |
| Linked service | `LS_AzureSqlDb` |
| Table name | `dbo.Employees` (from dropdown – table must exist; run the SQL script first) |
| Import schema | From connection/store |

---

## Publish

Click **Publish all** → review the list (6 datasets) → **Publish**.

### Expression cheat-sheet (used in later labs)

| Expression | Meaning |
|---|---|
| `@dataset().p_file` | Dataset's own parameter |
| `@pipeline().parameters.x` | Pipeline parameter |
| `@variables('x')` | Pipeline variable |
| `@item()` | Current element inside ForEach |
| `@activity('Name').output` | Output JSON of a previous activity |
| `@pipeline().RunId` | Unique ID of this run |
| `@pipeline().TriggerTime` / `@utcnow()` | Timestamps |
| `@concat('a','b')`, `@{expr}` | String building / interpolation |

✅ **Checkpoint:** Author → Datasets lists 6 datasets; Preview works on DS_Employees_CSV and DS_Products_JSON.
