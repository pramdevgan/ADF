# 02 – Configure Linked Services (≈ 20 min)

## What is a Linked Service?

A **linked service** is ADF's equivalent of a **connection string**. It stores:

- **Which** store/compute (type: Azure Blob, Azure SQL, Snowflake, REST…)
- **Where** it is (account name, server, URL)
- **How** to authenticate (account key, SAS, managed identity, SQL login, service principal)
- **Which Integration Runtime** executes the connection

A linked service by itself does nothing – datasets and activities reference it. One linked service can serve many datasets (one storage account → many files).

### Integration Runtime (IR) – quick primer

| IR type | Runs where | Use when |
|---|---|---|
| **Azure IR** (`AutoResolveIntegrationRuntime`) | Microsoft-managed, serverless in Azure | Cloud ↔ cloud with public endpoints – **this lab** |
| **Self-hosted IR** | Software you install on a VM/on-prem machine | On-premises or private-network sources |
| **Azure-SSIS IR** | Managed cluster running SSIS packages | Lift-and-shift SSIS |

"AutoResolve" means ADF picks the region closest to the sink automatically.

---

## Linked Service 1 – Azure Blob Storage (`LS_BlobStorage`)

1. ADF Studio → **Manage** (🧰) → **Linked services** → **+ New**.
2. **Data store** tab → search **Azure Blob Storage** → **Continue**.
3. Fill the form:

| Field | Value | What / Why |
|---|---|---|
| Name | `LS_BlobStorage` | Prefix `LS_` is a common convention, makes objects easy to find |
| Description | Lab storage account | Documentation |
| Connect via integration runtime | `AutoResolveIntegrationRuntime` | Azure-hosted IR; storage is public, so no self-hosted IR needed |
| Authentication type | **Account key** | Simplest. Other options: SAS URI (time-limited, scoped), Service principal, **System-assigned managed identity** (best practice – no secrets), User-assigned MI |
| Account selection method | **From Azure subscription** | Lets you pick from a dropdown instead of typing the connection string |
| Azure subscription | yours | |
| Storage account name | `stadflab<initials>` | ADF reads the key automatically and stores it encrypted |
| Test connection | **To linked service** | Checks you can reach the account |

4. Click **Test connection** (bottom) → expect ✅ **Connection successful**.
5. Click **Create**.

> **Why the key is safe:** ADF encrypts the credential. In production you'd store it in **Azure Key Vault** and reference it, or use Managed Identity and grant the factory the **Storage Blob Data Contributor** RBAC role.

### (Bonus) Managed Identity variant – best practice
1. Storage account → **Access control (IAM)** → **+ Add role assignment** → **Storage Blob Data Contributor** → Assign access to **Managed identity** → select **Data factory → adf-lab-<initials>** → Review + assign.
2. In the linked service choose Authentication type **System-assigned managed identity**.
3. RBAC can take 2–5 minutes to propagate; if Test connection fails with 403, wait and retry.

---

## Linked Service 2 – Azure SQL Database (`LS_AzureSqlDb`) *(optional – for Pipeline 3)*

1. **Manage → Linked services → + New → Azure SQL Database → Continue**.

| Field | Value | What / Why |
|---|---|---|
| Name | `LS_AzureSqlDb` | |
| Connect via IR | AutoResolveIntegrationRuntime | |
| Version *(if shown)* | Recommended | The newer connector version |
| Account selection method | From Azure subscription | |
| Server name | `sql-adf-lab-<initials>` | |
| Database name | `sqldb-adflab` | |
| Authentication type | **SQL authentication** | Uses the admin login you created. Alternatives: Managed identity (create a contained user for the factory), Service principal |
| User name / Password | `sqladmin` / your password | Or choose **Azure Key Vault** to reference a secret |
| Encrypt *(if shown)* | Mandatory | TLS encryption in transit |
| Trust server certificate | unchecked | Validate the certificate |

2. **Test connection** → ✅ → **Create**.

**If the test fails with "Cannot open server … Client with IP address … is not allowed":**
SQL server → **Networking** → enable **Allow Azure services and resources to access this server** → Save.

---

## Publish

Linked services created in live mode appear in the **Publish all** counter at the top. Click **Publish all → Publish** to save them to the service.

> In live mode (no Git) anything not published is lost if you close the browser.

✅ **Checkpoint:** Manage → Linked services shows `LS_BlobStorage` (and `LS_AzureSqlDb`).

Reference JSON: `pipeline-json/linkedService_LS_BlobStorage.json`, `pipeline-json/linkedService_LS_AzureSqlDb.json`
