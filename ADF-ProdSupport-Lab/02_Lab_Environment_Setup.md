# Module 2 — Lab Environment Setup (Azure Portal, step by step)
⏱ ~40 min  |  👤 each learner (or pair) builds their own "RetailMart production"

> Every step tells you **WHAT** to click, **WHY** we choose that option, and **WHAT IT DOES**.
> A CLI shortcut exists in `scripts/01_provision_cli_OPTIONAL.sh`, but do it in the Portal at least once — in a real incident you must know which blade to open.

---

## 2.0 Architecture you are building

```
                ┌──────────────────────── Azure Monitor ────────────────────────┐
                │  Metric alert (PipelineFailedRuns)   Log alert (KQL)          │
                │        │                                   ▲                  │
                │        ▼                                   │ diagnostic logs  │
                │  Action group (email on-call)     Log Analytics  law-adf-ps   │
                └────────────────────────────────────────────▲─────────────────┘
                                                             │
 Vendor/POS files      ┌───────────── Azure Data Factory  adf-ps-<initials> ───────────────┐
 ─────────────────►    │  TR_Daily_0200_IST ─► PL_Master_Daily                              │
 ADLS Gen2             │                        ├─ Exec PL_Ingest_Customers (Copy + SP)    │
 stadfps…/landing      │                        ├─ Exec PL_Ingest_Sales     (Copy + SP)    │
   customers/*.csv ───►│                        └─ SP rpt.usp_Build_DailySalesSummary      │
   sales/*.csv         │  TR_Hourly_HealthCheck ─► PL_HealthCheck (Lookup SP + Fail)        │
                       └───────┬────────────────────────────┬──────────────────────────────┘
                     Managed identity                 secret via MI
                               │                            │
                               ▼                            ▼
                   Azure SQL DB sqldb-retail      Key Vault kv-adf-ps-<initials>
                   stg / dbo / rpt  (business)    secret: sql-adfloader-password
                   ops (logs, incidents, health)
```

## 2.1 Resources required

| # | Resource | Name (replace `<initials>`) | SKU for lab | Why we need it |
|---|---|---|---|---|
| 1 | Resource group | `rg-adf-prodsupport-lab` | – | One container → easy cleanup, one IAM/cost scope |
| 2 | Storage account (ADLS Gen2) | `stadfps<initials><4digits>` | Standard LRS, HNS on | Landing zone for vendor/POS files |
| 3 | Azure SQL server + DB | `sql-adf-ps-<initials>` / `sqldb-retail` | Basic (5 DTU) or Serverless/free offer | Target warehouse + **ops tables = our ticketing system** |
| 4 | Key Vault | `kv-adf-ps-<initials>` | Standard, RBAC model | Store SQL password; practise credential incidents |
| 5 | Log Analytics workspace | `law-adf-ps` | Pay-as-you-go | Keep ADF run history > 45 days, KQL investigation, log alerts |
| 6 | Data Factory V2 | `adf-ps-<initials>` | Pay-per-use | The system we support |
| 7 | Action group | `ag-adf-ps-oncall` | – | Who gets paged (email) |
| 8 | Alert rules | `alert-adf-pipeline-failed`, `alert-adf-healthcheck-log` | – | Detection |

**Prerequisites:** Azure subscription where you are **Owner** (or Contributor + User Access Administrator — needed to create role assignments); a browser; the unzipped lab package.

**Cost (indicative only — verify on the Azure Pricing Calculator for your region/currency):** SQL Basic is a few USD per month (prorated hourly), ADF pay-per-activity-run is cents for this lab, storage and Log Analytics ingestion are negligible at this volume. **Delete the resource group at the end** (`09_Cleanup.md`).

**Region:** use **Central India** for everything (keeps latency low and avoids cross-region data transfer).

---

## 2.2 Create the Resource Group

1. Portal home → search bar → **Resource groups** → **+ Create**.
2. **Subscription:** your lab subscription. **Resource group:** `rg-adf-prodsupport-lab`. **Region:** Central India.
3. **Tags** tab → add `env = lab`, `owner = <your name>`, `purpose = prod-support-training`.
   - *Why tags:* in real prod support, tags tell you **who owns** a resource at 3 AM and drive cost reports.
4. **Review + create** → **Create**.

---

## 2.3 Create the ADLS Gen2 Storage Account

1. Search **Storage accounts** → **+ Create**.
2. **Basics** tab

   | Field | Value | Why |
   |---|---|---|
   | Resource group | `rg-adf-prodsupport-lab` | |
   | Storage account name | `stadfps<initials><4digits>` | Must be globally unique, 3–24 lowercase letters/digits |
   | Region | Central India | Same region as ADF → no egress, lower latency |
   | Primary service | Azure Blob Storage or Azure Data Lake Storage Gen2 (if shown) | |
   | Performance | **Standard** | Premium is for low-latency workloads; not needed |
   | Redundancy | **LRS** | Cheapest. *Prod would use ZRS/GRS* — mention in DR discussions |

3. **Advanced** tab
   - ✅ **Enable hierarchical namespace** → this is what makes it **ADLS Gen2** (real folders, POSIX ACLs, atomic renames). ADF connects through the `dfs` endpoint (`AzureBlobFS` connector).
   - ❌ *Allow enabling anonymous access on individual containers* → **off** (security baseline).
   - Minimum TLS: **1.2**.
4. **Networking** → *Enable public access from all networks* (lab simplicity). *Prod: private endpoints + ADF managed VNet.*
5. **Data protection** → keep **soft delete for blobs/containers** ON (7 days).
   - *Why:* it's a **recovery procedure** — if someone deletes a landing file, you can undelete it.
6. **Review + create** → **Create** → **Go to resource**.

### Create containers
Storage account → **Data storage → Containers** → **+ Container** (Private access) ×3:

| Container | Purpose |
|---|---|
| `landing` | Files arrive here (`customers/`, `sales/` folders) |
| `archive` | (optional) processed files |
| `rejected` | Bad rows if you enable Copy fault tolerance (discussed in S2) |

### Upload baseline data
1. Open container **landing** → **Upload** → *Advanced* → **Upload to folder:** `customers` → select `data/good/customers_20261013.csv` and `customers_20261014.csv` → **Upload**.
2. Again **Upload** → folder `sales` → `data/good/sales_20261013.csv`, `sales_20261014.csv`.
3. Verify you see `landing/customers/…` and `landing/sales/…`.

> If the upload says "you don't have permissions", the container is using *Microsoft Entra* auth: on the container page click **Switch to Access key**, or give yourself **Storage Blob Data Contributor** (IAM).

---

## 2.4 Create Azure SQL Server + Database

1. Search **SQL databases** → **+ Create**.
   - If a banner offers **"Want to try Azure SQL Database for free?" → Apply offer**, you may use it (serverless free amount); otherwise continue with Basic.
2. **Basics**

   | Field | Value | Why |
   |---|---|---|
   | Database name | `sqldb-retail` | |
   | Server | **Create new** → name `sql-adf-ps-<initials>`, location Central India | Logical server = endpoint + logins + firewall |
   | Authentication method | **Use both SQL and Microsoft Entra authentication** (set yourself as Entra admin) — or SQL only | SQL auth needed for the lab's `adfloader` user; Entra admin lets you try managed-identity auth later |
   | Server admin login | `sqladminuser` + strong password | **Do not** use this account in ADF (least privilege) |
   | Want to use SQL elastic pool? | No | |
   | Workload environment | Development | |
   | Compute + storage | **Configure database** → **Basic** (DTU, 2 GB) → Apply | Cheapest always-on tier. *Serverless auto-pause* would add "database not available" cold-start errors — a good discussion topic but noisy for a lab |
   | Backup storage redundancy | **Locally-redundant** | Cheapest; backups still enable **point-in-time restore** (a recovery procedure) |

3. **Networking**
   - Connectivity method: **Public endpoint**.
   - ✅ **Allow Azure services and resources to access this server = Yes** → required because ADF's *AutoResolve* (Azure) Integration Runtime connects from Azure IP ranges.
   - ✅ **Add current client IP address = Yes** → so the Portal Query editor / SSMS from your laptop can connect.
4. **Security** → skip Defender for lab. **Additional settings** → Use existing data: None.
5. **Review + create** → **Create** (3–5 min).

### Run the database scripts
1. Open **sqldb-retail** → **Query editor (preview)** → log in with **SQL server authentication** (`sqladminuser`).
   - If you get *"Client with IP … is not allowed"*, click the link in the error / **Set server firewall** to add your IP.
2. Open each file from the `sql/` folder, paste, **Run**, in this order:

   | Order | File | Creates | Check |
   |---|---|---|---|
   | 1 | `01_schemas_and_tables.sql` | stg/dbo/rpt/ops tables, escalation matrix, status transitions | `SELECT * FROM ops.EscalationMatrix` → 4 rows |
   | 2 | `02_ops_logging_and_incident_procs.sql` | logging + ticket procedures | Message "procedures created" |
   | 3 | `03_business_load_procs.sql` | idempotent loads + report build | |
   | 4 | `04_health_checks.sql` | `ops.usp_RunHealthChecks` | |
   | 5 | `00_create_adf_login_user.sql` | contained user `adfloader` (**edit the password first**) | final SELECT shows `db_datareader`, `db_datawriter` |

   > *Why 00 runs last:* the GRANTs reference schemas created in 01.
   > *Why a contained user (`CREATE USER … WITH PASSWORD`):* the login lives inside the database — no `master` access needed, and it moves with the DB.

---

## 2.5 Create the Key Vault and the secret

1. Search **Key vaults** → **+ Create**.
2. **Basics:** name `kv-adf-ps-<initials>`, region Central India, **Pricing tier: Standard**, soft-delete retention 90 days (default), **Purge protection: Disable** (lab — lets you purge and reuse the name; *enable in prod*).
3. **Access configuration** → Permission model: **Azure role-based access control (recommended)**.
   - *Why RBAC instead of access policies:* same IAM model as every other resource, auditable in Activity Log, and it's the current recommended model.
4. **Networking:** allow public access from all networks (lab).
5. **Review + create** → **Create** → **Go to resource**.
6. **Give yourself rights to write secrets:** Key vault → **Access control (IAM)** → **+ Add → Add role assignment** → role **Key Vault Secrets Officer** → Members: *User, group, or service principal* → **+ Select members** → you → **Review + assign**.
   - Without this you get *"The operation is not allowed by RBAC"* when creating a secret — even as subscription Owner, because Owner is control-plane, secrets are data-plane.
7. Wait ~1 min → **Objects → Secrets → + Generate/Import**
   - Name: `sql-adfloader-password`
   - Secret value: **the same password** you put in `00_create_adf_login_user.sql`
   - **Create**.

---

## 2.6 Create the Log Analytics workspace

1. Search **Log Analytics workspaces** → **+ Create** → RG, name `law-adf-ps`, region Central India → **Review + create**.
2. *Why:* ADF Monitor keeps run history only **45 days**, and you can't query across factories or join with other logs there. Log Analytics gives long retention, **KQL**, dashboards, and **log-search alerts**.

---

## 2.7 Create the Data Factory

1. Search **Data factories** → **+ Create**.
2. **Basics:** RG, **Name** `adf-ps-<initials>`, Region Central India, **Version V2**.
3. **Git configuration:** ✅ **Configure Git later**.
   - *Why for lab:* we publish directly ("live mode") so failures can be injected quickly.
   - *In prod:* always Git (Azure DevOps/GitHub) + CI/CD — that's your **rollback** mechanism and change audit trail.
4. **Networking:** Public endpoint (default). *Managed VNet + private endpoints in prod.*
5. **Advanced:** encryption with Microsoft-managed key (default).
6. **Review + create** → **Create** → **Go to resource**.
7. Note the **Managed Identity**: Data factory → **Properties** (or **Identity**) → copy *Managed Identity Object ID*. ADF gets a **system-assigned managed identity** automatically — an Entra identity with the same name as the factory; no passwords to rotate.

---

## 2.8 Grant ADF's managed identity access (RBAC)

### a) Storage → Storage Blob Data Contributor
1. Storage account → **Access control (IAM)** → **+ Add → Add role assignment**.
2. Role tab: search **Storage Blob Data Contributor** → Next.
   - *Why this role:* data-plane read/write on blobs. **Reader/Contributor are not enough** — they are control-plane roles; ADF would get *403 AuthorizationPermissionMismatch* (this is exactly Scenario S4).
3. Members: **Assign access to → Managed identity** → **+ Select members** → Managed identity: **Data factory (V2)** → select `adf-ps-<initials>` → **Select** → **Review + assign**.

### b) Key Vault → Key Vault Secrets User
Same steps on the Key Vault, role **Key Vault Secrets User** (read secret values only — least privilege; ADF never needs to write secrets).

> ⏳ RBAC changes can take a few minutes to propagate. If Test connection fails right after assigning, wait 2–5 min and retry.

---

## 2.9 Setup verification checklist

| ✔ | Check | How |
|---|---|---|
| ☐ | 6 resources in RG | Resource group → Overview |
| ☐ | 4 files in `landing` | Storage → Containers → landing |
| ☐ | `ops.EscalationMatrix` has 4 rows | Query editor |
| ☐ | `adfloader` exists with roles | result of `00_create_adf_login_user.sql` |
| ☐ | Secret `sql-adfloader-password` exists | Key Vault → Secrets |
| ☐ | ADF MI has **Storage Blob Data Contributor** on storage | Storage → IAM → **Role assignments** tab |
| ☐ | ADF MI has **Key Vault Secrets User** on KV | KV → IAM → Role assignments |

➡️ Next: `03_Lab1_Build_Monitored_Pipelines.md`
