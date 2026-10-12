# Azure Data Factory – Hands-on Lab (3 Hours)

**Lab objectives**

1. Create and execute sample pipelines
2. Configure datasets and linked services
3. Understand pipeline execution flow

**Platform:** Azure Portal + Azure Data Factory Studio (ADF V2)
**Level:** Beginner → Intermediate (fits DP-900 / DP-203 foundations)

---

## 1. What is Azure Data Factory (in one paragraph)

Azure Data Factory (ADF) is Azure's **cloud ETL/ELT and data-integration service**. It does not store data itself – it **moves and transforms data between stores** (Blob, ADLS, SQL, Cosmos DB, on-prem SQL Server, SaaS apps, 90+ connectors) and **orchestrates** the order in which those steps run. Think of it as the "conductor" of a data orchestra: it tells each instrument (storage, database, compute) when to play.

## 2. The 6 building blocks you will touch today

| Building block | Plain-English meaning | Analogy |
|---|---|---|
| **Linked Service** | A *connection string* – how ADF logs in to a data store/compute | The **address + key** of a warehouse |
| **Dataset** | A *pointer to specific data* inside that store (a file, folder, table) | A **specific shelf** in the warehouse |
| **Activity** | A single step of work (Copy, Get Metadata, ForEach, If, Wait…) | A **worker's task** |
| **Pipeline** | A logical group of activities with an order | The **work plan / recipe** |
| **Integration Runtime (IR)** | The compute that actually executes the movement | The **truck** that carries goods |
| **Trigger** | What starts a pipeline (manual, schedule, event, tumbling window) | The **alarm clock** |

```
Trigger ──starts──► Pipeline ──contains──► Activities
                                              │ uses
                                              ▼
                                          Datasets ──refer to──► Linked Services ──connect via──► Integration Runtime ──► Data store
```

## 3. Files in this kit

| File | What it covers | Time |
|---|---|---|
| `01-Environment-Setup.md` | Resource group, Storage account, containers, sample data upload, Data Factory creation, (optional) Azure SQL DB | 30 min |
| `02-Linked-Services.md` | Create Blob + Azure SQL linked services, every option explained | 20 min |
| `03-Datasets.md` | Create CSV, JSON, SQL and **parameterized** datasets | 20 min |
| `04-Pipeline-1-Simple-Copy.md` | First pipeline: Copy CSV → CSV; Debug, Publish, Trigger | 25 min |
| `05-Pipeline-2-Dynamic-ForEach.md` | Get Metadata + ForEach + parameterized Copy (copy many files) | 30 min |
| `06-Pipeline-3-Blob-to-SQL.md` | Load CSV into Azure SQL table (optional but recommended) | 20 min |
| `07-Execution-Flow-and-Monitoring.md` | Dependency conditions, If/Fail/Wait, variables, triggers, Monitor hub, reruns | 30 min |
| `08-Troubleshooting.md` | Common errors and fixes | reference |
| `09-Cleanup-and-Viva.md` | Delete resources, viva/quiz questions with answers | 5 min |
| `sample-data/` | CSV/JSON files to upload | – |
| `pipeline-json/` | JSON definitions of every linked service, dataset and pipeline (paste into ADF code view `{}` if you get stuck) | – |
| `sql/` | SQL script to create the target table | – |

## 4. Suggested 3-hour timeline

| Clock | Activity |
|---|---|
| 0:00 – 0:30 | Environment setup (File 01) |
| 0:30 – 0:50 | Linked services (File 02) |
| 0:50 – 1:10 | Datasets (File 03) |
| 1:10 – 1:35 | Pipeline 1 – simple copy (File 04) |
| 1:35 – 2:05 | Pipeline 2 – dynamic ForEach (File 05) |
| 2:05 – 2:25 | Pipeline 3 – Blob to SQL (File 06) |
| 2:25 – 2:55 | Execution flow, triggers, monitoring (File 07) |
| 2:55 – 3:00 | Cleanup (File 09) |

> **Short on time?** Skip File 06 (Azure SQL). Everything else works with only a Storage account.

## 5. Prerequisites

- An Azure subscription (Azure for Students / Free Trial / Pay-As-You-Go). Role: **Owner** or **Contributor** on the subscription or resource group.
- A modern browser (Edge/Chrome). ADF Studio does not work well in Safari private mode or with 3rd-party cookies fully blocked.
- Sample files from the `sample-data/` folder downloaded to your PC.

## 6. Naming convention used in this lab

Replace `<initials>` with your initials + 2–3 digits (names must be globally unique for storage/ADF/SQL server).

| Resource | Name used in this guide |
|---|---|
| Resource group | `rg-adf-lab` |
| Storage account | `stadflab<initials>` (lowercase, 3–24 chars, letters+digits only) |
| Containers | `input`, `output`, `archive` |
| Data Factory | `adf-lab-<initials>` |
| SQL server (optional) | `sql-adf-lab-<initials>` |
| SQL database (optional) | `sqldb-adflab` |
| Region | Central India (or any region you are allowed – use **the same region for all**) |

## 7. Cost note

- ADF charges per activity run / data-movement minute – this whole lab costs a few rupees.
- Storage: negligible for KB-size files.
- Azure SQL: use the **free Azure SQL Database offer** or the **Basic** tier.
- **Delete the resource group at the end** (File 09) to stop all charges.
