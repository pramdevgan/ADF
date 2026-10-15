# Instructor Guide & Answer Key  (🔒 not for learners before the labs)

## Before the session (T-1 day)
- [ ] Each learner has a subscription with **Owner** (role assignments needed) and Central India quota for SQL.
- [ ] Do a full dry-run yourself (setup + baseline + S2 + E2E stage 1) — ~90 min.
- [ ] Decide: everybody builds pipelines by hand (best learning) or pastes JSON (time-saver). Recommended: **build `PL_Ingest_Sales` by hand, paste the other three**.
- [ ] Optional: pre-provision with `scripts/01_provision_cli_OPTIONAL.sh` if the session is < 4 h.

## Timing options
| Format | Theory | Setup | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|---|---|
| Full day (~5 h) | 40 | 40 | 45 | 35 | 70 | 30 | 45 |
| Half day (~3 h, pre-provisioned + JSON pasted) | 40 | 10 | 15 | 20 | 45 (S1,S3,S5,S6,S7) | 15 | 35 |

## Common learner problems
| Symptom | Fix |
|---|---|
| Test connection to ADLS 403 right after RBAC | Wait 2–5 min; check role was given to the **Data factory** MI, not a user |
| Can't create KV secret ("not allowed by RBAC") | Give the learner **Key Vault Secrets Officer** on the vault |
| Query editor can't log in | Add client IP on SQL server Networking |
| Copy mapping empty after Import schemas | Dataset parameters need debug values; or paste JSON |
| No rerun buttons | They used **Debug** — use **Trigger now** after Publish |
| Runs not in Log Analytics | Ingestion delay 5–15 min; diag setting must be **Resource specific** |
| `SP_LogStart` fails with "Could not find stored procedure" | sql/02 not run, or wrong DB selected in linked service |
| TRUNCATE permission error in Copy | `GRANT ALTER ON SCHEMA::stg TO adfloader` missing (sql/00) |

## Lab 3 answer key
| ID | Expected failing activity | Error key words | Auto ticket? | Correct rerun | Root cause | Good CAPA |
|---|---|---|---|---|---|---|
| S1 | Copy_Sales_To_Stg | path does not exist / PathNotFound, `sales_20261016.csv` | Yes P3 ERR_COPY_SALES | Rerun (full) | Upstream file late | Event trigger / Validation activity / arrival SLA |
| S2 | Copy_Sales_To_Stg | conversion of `two` / `N/A` / invalid date | Yes P3 | Rerun from failed activity (Copy) | Corrupt source values | DQ at source; fault-tolerance policy agreed with business |
| S3 | SP_Load_FactSales | DQ_EMPTY_FILE (50001) | Yes P3 ERR_LOAD_SALES | Rerun from **Copy** (not from failed SP!) | Header-only export | File-size / row-count check before load |
| S4 | Copy_Sales_To_Stg | 403 AuthorizationPermissionMismatch | Yes → raise to P2 | Rerun from failed activity | Role assignment deleted | Resource lock / Policy / alert on role deletes |
| S5 | SP_LogStart (after 2 retries) | Login failed for user 'adfloader' | **No** (DB unreachable) → manual | Rerun (full) | Wrong secret version | MI auth to SQL; rotation SOP |
| S6 | none (green) | HC02 + HC03 + HC05 FAIL | Only via health check, P2 | Fix code then rerun **master** | Unreviewed non-idempotent hotfix | UNIQUE(OrderId), Git + review, hourly HC |
| S6b | SP_Load_FactSales | DQ_DUPLICATE_KEYS (50002) | Yes P3 | Rerun from Copy | Duplicates in source | Data contract |
| S7 | none (no run) | HC01/HC03/HC05 FAIL for 20261017 | Only via HC/freshness | Start trigger + backfill 20261017 | Trigger left stopped after deployment | Freshness alert; release checklist |

## Lab 5 (E2E) answer key
**Stage 1**
- Q2: master `Exec_Ingest_Customers` **Failed**; `Exec_Ingest_Sales`, `SP_Build_Report`, `SP_LogSuccess` **Skipped**; `SP_LogFailure_Master` Succeeded; `Fail_Master` Failed.
- Q3/Q4: child `PL_Ingest_Customers` → `Copy_Customers_To_Stg` fails; message says source column `customer_id` cannot be found/mapped (wording varies).
- Q5: No — sales was skipped because customers runs first (dependency). Sales file was fine.
- Q6: no ADF write operations in Activity log.
- Q7: header `cust_id,…` instead of `customer_id,…`.
- Q8: **Upstream** (schema drift / data contract breach).
- Tickets: P2 `PL_Master_Daily … ERR_MASTER` + P3 `PL_Ingest_Customers … ERR_COPY_CUSTOMERS`.
- Decision: B (vendor resend). Accept A only if framed as emergency change with approval + revert plan.

**Stage 2** (resend1: header fixed, 20 customers)
- Rerun: *Rerun from failed activity* on the master is fine (children are idempotent; it re-invokes `Exec_Ingest_Customers` → new child runs). Full Rerun also correct.
- All green. Health check FAILs **HC04**: 5 orphan rows, amount **11320.90**, missing **C1021, C1022**. (HC01/02/03/05 PASS.)
- Report shows a segment/city **'Unknown'** with revenue 11320.90 → CFO sees an "Unknown" line and segment totals understated.
- Ticket must stay **InProgress** (service up but incorrect). New HC04 ticket (P2, Data Quality) linked.
- Right question to vendor: "Does the file contain the customers onboarded on 15-Oct at the new store?"

**Stage 3** (22 customers)
- Rerun **PL_Master_Daily 20261015** (Trigger now). Customer MERGE inserts 2 rows; FactSales reloaded idempotently (still 60); report rebuilt.
- Health check 0 FAIL; FactSales 60 / 186667.30; DimCustomer 22; no Unknown.

**Model 5 Whys**
1. Why was the report late/wrong? Customer load failed, then loaded incomplete data.
2. Why did the customer load fail? Vendor file header changed.
3. Why did the header change? Vendor upgraded their export tool.
4. Why weren't we told? No data contract / change notification with vendor.
5. Why did incomplete data look "green"? Pipeline validates format but not completeness; only the health check caught it.

**Model CAPA**: Detect — schema validation step (Get Metadata `structure` + If → Fail with clear message) and HC04 in master path; Prevent — data contract + vendor change notification, quarantine folder for non-conforming files; Process — vendor contact in runbook, comms template; Recover — document backfill procedure for dimension late-arrivals.

## Reset between groups
`sql/99_reset_lab.sql`, re-upload good files (`scripts/02_upload_baseline_data.sh`), restore S4/S5/S6/S7 if still injected (`10_fault_injection.sh Sx fix`, `sql/91`), delete E2E files for 20261015 from landing.
