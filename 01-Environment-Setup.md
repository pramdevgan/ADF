# 01 – Environment Setup (≈ 30 min)

Goal: create everything ADF needs to read from and write to.

```
rg-adf-lab
 ├── stadflab<initials>   (Storage account)
 │     ├── input/      ← source files
 │     ├── output/     ← copied files land here
 │     └── archive/    ← used in Pipeline 2
 ├── adf-lab-<initials>   (Data Factory V2)
 └── sql-adf-lab-<initials> / sqldb-adflab   (optional, Pipeline 3)
```

---

## Step 1 – Create a Resource Group

1. Open **https://portal.azure.com** → sign in.
2. Search bar (top) → type **Resource groups** → **+ Create**.
3. Fill:

| Field | Value | Why |
|---|---|---|
| Subscription | your subscription | Billing boundary – all charges go here |
| Resource group | `rg-adf-lab` | A **logical folder** for all lab resources. Deleting it later deletes everything in one click |
| Region | Central India | Where the RG *metadata* is stored. Keep all resources in the same region to avoid cross-region data-transfer cost and latency |

4. **Review + create** → **Create**.

---

## Step 2 – Create a Storage Account

1. Search **Storage accounts** → **+ Create**.
2. **Basics tab**

| Field | Value | Why / What it does |
|---|---|---|
| Subscription / RG | `rg-adf-lab` | Keep it inside the lab RG |
| Storage account name | `stadflab<initials>` | Globally unique, it becomes `https://stadflab<initials>.blob.core.windows.net` |
| Region | Central India | Same as ADF |
| Primary service *(if shown)* | Azure Blob Storage or Azure Data Lake Storage Gen2 | We store files (blobs) |
| Performance | **Standard** | HDD-backed, cheap; Premium is for low-latency workloads – not needed |
| Redundancy | **LRS** (Locally-redundant) | 3 copies in one datacenter – cheapest. GRS/ZRS add geo/zone copies (production use) |

3. **Advanced tab**

| Field | Value | Why |
|---|---|---|
| Require secure transfer | ✅ Enabled | Only HTTPS allowed |
| Allow enabling anonymous access on containers | ❌ Disabled | Containers stay private; ADF authenticates with a key |
| **Enable storage account key access** | ✅ **Enabled** | ADF linked service will use **Account key** authentication. If disabled, account-key auth fails |
| Minimum TLS version | 1.2 | Security best practice |
| Enable hierarchical namespace | ❌ (leave off) | Turning it on makes it ADLS Gen2 (real folders, ACLs). Not required for this lab; both work with ADF |
| Access tier | **Hot** | Frequently accessed data, lowest access cost |

4. **Networking tab** → Network access: **Enable public access from all networks** (simplest for a lab).
   *Why:* ADF's Azure Integration Runtime connects over the public endpoint. In production you'd use private endpoints / managed VNet.
5. **Data protection / Encryption / Tags** → leave defaults (soft delete on, Microsoft-managed keys).
6. **Review + create** → **Create** → wait ~30 s → **Go to resource**.

---

## Step 3 – Create containers

Storage account → left menu **Data storage → Containers** → **+ Container**

| Name | Anonymous access level | Purpose |
|---|---|---|
| `input` | Private | Source files ADF will read |
| `output` | Private | Sink – ADF writes copies here |
| `archive` | Private | Destination for the multi-file pipeline |

*Why private:* ADF does not need public access; it uses the account key.

---

## Step 4 – Upload sample data

1. Open container **input** → **Upload**.
2. Inside the upload blade expand **Advanced** → **Upload to folder** → type the folder name, then select files:

| Upload to folder | Files (from `sample-data/`) |
|---|---|
| *(root – leave blank)* | `employees.csv`, `products.json` |
| `sales` | `sales_2026_01.csv`, `sales_2026_02.csv`, `sales_2026_03.csv` |

3. Click **Upload**. You should now see:

```
input/
 ├── employees.csv
 ├── products.json
 └── sales/
       ├── sales_2026_01.csv
       ├── sales_2026_02.csv
       └── sales_2026_03.csv
```

> Blob storage is flat; "folders" are just prefixes in the blob name (`sales/sales_2026_01.csv`). ADF treats them like folders.

---

## Step 5 – Create the Azure Data Factory

1. Search **Data factories** → **+ Create**.
2. **Basics tab**

| Field | Value | Why |
|---|---|---|
| Resource group | `rg-adf-lab` | |
| Name | `adf-lab-<initials>` | Globally unique (3–63 chars, letters/digits/hyphens) |
| Region | Central India | Where ADF **metadata** (pipelines, run history) is stored. The Azure IR auto-resolves compute near the data |
| Version | **V2** | V1 is retired; V2 has the visual Studio, control flow, triggers, data flows |

3. **Git configuration tab** → ✅ **Configure Git later**
   *Why:* Git (Azure DevOps/GitHub) gives version control and CI/CD. Without Git you work in **"live mode"** – changes go live when you click **Publish all**. Simpler for a lab.
4. **Networking tab**
   - Enable managed virtual network on default AutoResolveIntegrationRuntime: **unchecked** (managed VNet = isolated network for IR; slower start-up, used with private endpoints).
   - Connectivity method: **Public endpoint**.
5. **Advanced tab** → Encryption: leave unchecked (Microsoft-managed keys).
6. **Tags** (optional) → `course = DP-900`, `owner = <your name>` – helps cost tracking.
7. **Review + create** → **Create** → wait 1–2 min → **Go to resource**.
8. On the overview page click **Launch Studio** (opens `https://adf.azure.com`).

### Tour of ADF Studio (left vertical bar)

| Icon | Hub | Used for |
|---|---|---|
| 🏠 | **Home** | Shortcuts: Ingest (Copy Data tool), Orchestrate, Transform |
| ✏️ | **Author** | Build pipelines, datasets, data flows, Power Query |
| 📈 | **Monitor** | Pipeline runs, trigger runs, IR status, alerts |
| 🧰 | **Manage** | Linked services, Integration runtimes, Triggers, Git, Global parameters, Credentials |
| 🎓 | Learning center | Tutorials/templates |

---

## Step 6 (Optional) – Azure SQL Database for Pipeline 3

Skip if short on time.

1. Search **SQL databases** → **+ Create**.
   - If the banner **"Want to try Azure SQL Database for free?" → Apply offer** appears, apply it (free 100,000 vCore-seconds/month).
2. **Basics**

| Field | Value | Why |
|---|---|---|
| Database name | `sqldb-adflab` | |
| Server | **Create new** → name `sql-adf-lab-<initials>`, location Central India | Logical server = endpoint + logins + firewall |
| Authentication method | **Use SQL authentication** (admin `sqladmin` + strong password) | ADF linked service will use this login. (Entra-only auth is better for production) |
| Want to use SQL elastic pool? | No | |
| Workload environment | Development | |
| Compute + storage | Free offer **or** Basic (5 DTU, 2 GB) | Cheapest |
| Backup storage redundancy | Locally-redundant | Cheapest |

3. **Networking**
   - Connectivity method: **Public endpoint**
   - **Allow Azure services and resources to access this server: Yes** ← *required so ADF's Azure IR can reach the server*
   - **Add current client IP address: Yes** ← *so you can run the SQL script from Query editor*
4. **Review + create** → **Create** (2–4 min).
5. Open the database → **Query editor (preview)** → login with SQL auth → paste and run `sql/01-create-tables.sql`.

✅ **Checkpoint:** RG contains a Storage account (3 containers, 5 files), a Data Factory, and optionally a SQL database with tables `dbo.Employees` and `dbo.PipelineRunLog`.
