# Azure Data Factory — Production Support Readiness Lab Package

**Focus areas:** Incident Management Process · Ticket Documentation & Escalation · Support Runbooks & SOPs · Health Checks & Recovery Procedures
**Hands-on:** Simulated production support scenarios · Incident logging & resolution tracking · End-to-end failure investigation
**Format:** 40 min theory (Hinglish, one running example: *RetailMart 9 AM CFO report*) + detailed hands-on in Azure Portal & ADF Studio.

---

## Agenda

| # | Module | File | Time |
|---|---|---|---|
| 1 | Theory (Hinglish) | `01_Theory_Hinglish.md` | 40 min |
| 2 | Environment setup in Azure Portal | `02_Lab_Environment_Setup.md` | 40 min |
| 3 | Lab 1 – Build support-ready pipelines | `03_Lab1_Build_Monitored_Pipelines.md` | 45 min |
| 4 | Lab 2 – Monitoring, alerting, health checks | `04_Lab2_Monitoring_Alerting_HealthChecks.md` | 35 min |
| 5 | Lab 3 – 8 simulated incidents (S1–S7, S6b) | `05_Lab3_Simulated_Incidents.md` | 70 min |
| 6 | Lab 4 – Incident logging, escalation & resolution tracking | `06_Lab4_Incident_Logging_Resolution_Tracking.md` | 30 min |
| 7 | Lab 5 – End-to-end failure investigation | `07_Lab5_E2E_Failure_Investigation.md` | 45 min |
| 8 | Reference – health checks & recovery | `08_Health_Checks_and_Recovery_Reference.md` | – |
| 9 | Cleanup & cost | `09_Cleanup_and_Cost.md` | 5 min |
| 10 | Instructor guide & answer key | `10_Instructor_Guide_and_Answer_Key.md` | – |

A half-day variant is in the instructor guide.

## Package contents

```
ADF-ProdSupport-Lab/
├── README.md, 01…10 *.md            ← theory + step-by-step labs
├── data/
│   ├── good/                         baseline files 20261013, 20261014
│   ├── fault_injection/              S1 late files, S2 bad types, S3 empty, S6b duplicates, S7 files
│   ├── e2e/                          E2E stage 1 & 2 vendor files (20261015)
│   ├── corrected/                    clean files for recovery
│   └── EXPECTED_VALUES.md            answer key: row counts & revenue
├── sql/
│   ├── 00_create_adf_login_user.sql  least-privilege SQL user for ADF
│   ├── 01_schemas_and_tables.sql     stg/dbo/rpt + ops (log, incidents, health, escalation matrix)
│   ├── 02_ops_logging_and_incident_procs.sql   logging + auto-ticketing + ticket lifecycle
│   ├── 03_business_load_procs.sql    idempotent loads with DQ gates, report build
│   ├── 04_health_checks.sql          HC01–HC08
│   ├── 50_support_triage_queries.sql first-10-minutes query pack
│   ├── 60_incident_kpi_reports.sql   MTTA / MTTR / SLA / repeat incidents
│   ├── 90_FAULT_S6_…sql / 91_FIX_S6_…sql   fault + fix for S6
│   └── 99_reset_lab.sql
├── adf/                              JSON: linkedService, dataset, pipeline, trigger
├── kql/adf_support_queries.kql       K1–K12 Log Analytics queries
├── scripts/
│   ├── 00_variables.sh, 01_provision_cli_OPTIONAL.sh, 02_upload_baseline_data.sh
│   ├── 10_fault_injection.sh         inject / fix every scenario
│   ├── 99_cleanup.sh
│   ├── generate_lab_data.py          regenerates all CSVs (deterministic)
│   └── generate_adf_json.py          regenerates ADF JSON
└── templates/
    ├── Runbook_PL_Master_Daily.md    filled runbook (decision tree)
    ├── SOPs.md                       SOP-01…06
    ├── Incident_Ticket_Template.md, RCA_PIR_Template.md
    ├── Escalation_Matrix_and_Communication.md, Shift_Handover_Template.md
    └── ADF_Error_Triage_Cheatsheet.md
```

## Azure resources needed
Resource group, ADLS Gen2 storage account, Azure SQL Database (Basic), Key Vault, Log Analytics workspace, Data Factory V2, Action group, Alert rules. Learner needs **Owner** on the subscription/RG (for role assignments). Region used: **Central India**. Delete the resource group after the session.

## Quick start
1. Read `01_Theory_Hinglish.md` (instructor delivers).
2. Follow `02_…` → `07_…` in order.
3. Faults are injected via Portal uploads/changes or `scripts/10_fault_injection.sh <S#> inject|fix`.
4. Compare your numbers with `data/EXPECTED_VALUES.md`.
5. Clean up with `09_Cleanup_and_Cost.md`.

## Placeholders to replace
`<initials>`, `<digits>` in names and in `adf/linkedService/*.json`; the `adfloader` password in `sql/00_create_adf_login_user.sql` (and the identical Key Vault secret); your email in `scripts/00_variables.sh`.

> Portal blade names and ADF error wording evolve over time; if a label differs slightly, look for the closest equivalent — the concepts and flow stay the same.
