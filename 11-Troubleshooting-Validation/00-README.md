# Module 3 – Troubleshooting & Data Validation (3 hours)

**Total: 180 min = 40 min theory (Hinglish) + 140 min hands-on**

## Focus areas → where they are covered

| Focus area | Theory | Hands-on |
|---|---|---|
| Missing files | 01 §2.1 | INC-001 |
| Connectivity issues | 01 §2.2 | INC-002 |
| Authentication failures | 01 §2.3 | INC-003 |
| Trigger failures | 01 §2.4 | INC-004 |
| Data mapping errors | 01 §2.5 | INC-005a (schema drift), INC-005b (data types) |
| SQL fundamentals for validation | 01 Part 3 | Part C (V1–V13) |
| Root Cause Analysis | 01 Part 4 | Part D (RCA reports) |

## Schedule

| Clock | Part | File | Min |
|---|---|---|---|
| 0:00 – 0:40 | **Theory** (Hinglish, one running example: *ShopKart*) | `01-Theory-Hinglish.md` | 40 |
| 0:40 – 1:05 | **A.** Lab setup: build `PL_20_Daily_Orders_Load` | `02-Lab-Setup.md` | 25 |
| 1:05 – 2:11 | **B.** Investigate 5 simulated incidents | `03-Incidents-Hands-on.md` | 66 |
| 2:11 – 2:41 | **C.** Source-to-target data validation | `04-Data-Validation-Hands-on.md` | 30 |
| 2:41 – 3:00 | **D.** Prepare RCA reports | `05-RCA-Hands-on.md` | 19 |

## Prerequisites (from Module 1)
- Resource group `rg-adf-lab`, storage `stadflab<initials>` with container `input`
- Data Factory `adf-lab-<initials>`
- **Azure SQL DB `sqldb-adflab`** (required for this module)
- Linked services `LS_BlobStorage`, `LS_AzureSqlDb`
- Optional: the alert rule from Module 2 (`10-Monitoring-History-Alerts.md`) sends emails for every incident, which feels very realistic

## Package contents

```
11-Troubleshooting-Validation/
├── 00-README.md                       ← this file
├── 01-Theory-Hinglish.md              ← 40-min theory
├── 02-Lab-Setup.md                    ← Part A
├── 03-Incidents-Hands-on.md           ← Part B (INC-001 … INC-005)
├── 04-Data-Validation-Hands-on.md     ← Part C
├── 05-RCA-Hands-on.md                 ← Part D (+ model answer)
├── 06-Instructor-Notes.md             ← answer key, timing tips, reset
├── data/
│   ├── upload/      ← upload ALL to input/orders/ in Part A
│   │   ├── orders_20261001.csv   20 rows, clean (baseline)
│   │   ├── orders_20261002.csv   22 rows, hidden quality issues (Part C)
│   │   ├── Orders_20261003.csv   18 rows, WRONG-CASE name (INC-001)
│   │   ├── orders_20261004.csv   15 rows, schema drift (INC-005a)
│   │   └── orders_20261005.csv   16 rows, bad formats (INC-005b)
│   ├── fixes/       ← "vendor re-sent" files, used only during the fix steps
│   │   ├── orders_20261003.csv
│   │   ├── orders_20261004.csv
│   │   └── orders_20261005.csv
│   └── reference/   ← master data as CSV (already inserted by SQL script 01)
├── sql/
│   ├── 01-setup-tables.sql            ← schemas, tables, masters, control manifest
│   ├── 02-usp_Load_Orders.sql         ← staging → fact with reject handling
│   ├── 03-usp_Validate_Load.sql       ← 11-check quality gate (THROW on critical)
│   ├── 04-usp_Log_Run.sql             ← success log
│   ├── 05-validation-queries.sql      ← Part C hands-on (with expected answers)
│   ├── 06-incident-investigation-queries.sql
│   └── 07-reset-lab.sql               ← clear data to repeat the lab
├── pipeline-json/                     ← reference JSON (datasets, pipeline, broken + fixed trigger)
└── rca-templates/
    ├── RCA-Template.md
    ├── RCA-Example-INC-001.md         ← worked example
    └── Incident-Register.csv          ← evidence log students fill during Part B
```

## Student deliverables (submit at the end)
1. Screenshot: Monitor list showing the failed + rerun-succeeded runs for INC-001…005
2. Completed `Incident-Register.csv` (7 rows)
3. Completed validation worksheet (Part C)
4. `RCA-INC-005b.md` (full) and `RCA-INC-006.md` (short)

## Cleanup
- **Stop trigger `TR_Daily_Orders`** and Publish (if not already done in INC-004).
- Re-enable SQL "Allow Azure services" if you left it off.
- At the end of the course: delete `rg-adf-lab` (Module 1, File 09).
