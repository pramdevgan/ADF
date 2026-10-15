# RUNBOOK — RetailMart Daily Sales Load (`PL_Master_Daily`)

| Field | Value |
|---|---|
| Runbook ID | RB-ADF-001 · v1.0 · Owner: Data Engineering (L2) · Reviewed: 2026-10-15 |
| Service | RetailMart CFO Daily Sales Report |
| Business SLA | `rpt.DailySalesSummary` for D-1 ready by **08:30 IST** (CFO reads 09:00) |
| Schedule | `TR_Daily_0200_IST` 02:00 IST, pRunDate = D-1 (yyyyMMdd) |
| Typical duration | master 3–6 min (record your baseline from Lab 1 §1.9) |
| Data volume | sales 40–60 rows/day (lab), customers 20–22 |
| Alerts | `alert-adf-pipeline-failed` (metric), `alert-adf-failed-run-log` (log), `alert-adf-master-stale` (freshness) |
| Upstream contacts | POS team (sales file) · CRM vendor (customers file) |
| Downstream | Finance BI team (Power BI) |
| Escalation | see `Escalation_Matrix_and_Communication.md` |

## Components
| Object | Purpose | Idempotent? | Safe rerun point |
|---|---|---|---|
| `PL_Master_Daily` | orchestrates children + report | yes | any |
| `PL_Ingest_Customers` | landing/customers → stg → DimCustomer (MERGE) | yes | Copy activity |
| `PL_Ingest_Sales` | landing/sales → stg → FactSales (DELETE+INSERT per date) | yes | Copy activity (not the SP if staging is empty/wrong) |
| `rpt.usp_Build_DailySalesSummary` | report rebuild per date | yes | any |
| `PL_HealthCheck` | data validation | read/insert only | any |

---

## Step 0 — First 5 minutes (always)
1. Acknowledge the ticket (`ops.usp_UpdateIncident … 'Acknowledged'`).
2. Check **Azure Service Health** for an active incident in Central India (Data Factory, SQL, Storage, Key Vault). If yes → link it in the ticket, monitor, skip to Step 6 when Azure recovers.
3. ADF Studio → Monitor → Pipeline runs → filter `PL_Master_Daily`, last 24 h → open the failed run → note **master RunId**, failure time.
4. Identify the failed **child** (Execute Pipeline activity → Output → `pipelineRunId`) → open it → failed **activity** → copy **error code + message** into the ticket.

## Step 1 — Decision tree on the error

| Error text contains… | Likely cause | Action | Who |
|---|---|---|---|
| `PathNotFound` / `does not exist` / file name | Source file missing/late | SOP-03 (late file). Contact upstream. Ticket OnHold. | L1 |
| type conversion / `'two'` / cannot convert / invalid date | Corrupt source values | SOP-03 (bad file). Request resend. **Do not** hand-edit | L1 → data owner |
| column … not found / mapping / header | **Schema change upstream** | Compare header with previous file. Request resend in agreed format. Mapping change = Change request | L1 → L2 |
| `DQ_EMPTY_FILE` (50001/50011) | Header-only file | Request resend; rerun **from Copy** | L1 |
| `DQ_DUPLICATE_KEYS` (50002/50012) | Duplicate keys in file | Capture keys from stg; request resend | L1 |
| `DQ_NEGATIVE_VALUES`, `DQ_WRONG_BUSINESS_DATE` | Bad/wrong file | Check file date & content; request resend | L1 |
| `403` / `AuthorizationPermissionMismatch` | ADF MI lost storage RBAC | Check storage Activity log for role deletion → **escalate L3 Platform** (P2) | L1 → L3 |
| `Login failed for user 'adfloader'` | KV secret / DB password mismatch | SOP-04. Check KV versions + AuditEvent. Escalate L2 | L1 → L2 |
| `Key Vault` / `Forbidden` on secret | ADF MI lost KV RBAC or KV firewall | SOP-04 → L3 | L3 |
| `database … not currently available` (40613) / timeout | Transient SQL / scaling / failover | Retries should cover; if not → rerun once; if repeats → L2 | L1 |
| Integration runtime errors | IR issue (self-hosted in real prod) | Monitor → Integration runtimes; L3 | L3 |
| Nothing failed, but report stale | **Trigger stopped / didn't fire** | Monitor → Trigger runs; Manage → Triggers; SOP-01 backfill | L1 |
| Pipeline green but numbers wrong | Data quality / code change | Run `PL_HealthCheck`; `sql/50` Q6 lineage, Q9 changed objects → L2 | L1 → L2 |
| anything else | – | Escalate to L2 with RunIds + error text | L1 |

## Step 2 — What changed? (check all, write findings)
- [ ] Data factory → **Activity log** (pipelines/linked services/triggers modified?)
- [ ] Storage → **Activity log** (role assignments, network rules)
- [ ] Key Vault → Secrets → versions; KQL K12
- [ ] Source files: header/rows vs previous day
- [ ] DB code: `sql/50` Q9
- [ ] Recent releases / change calendar

## Step 3 — Fix (smallest safe fix, within your authority)
Anything that changes production code/config/IAM = **change request** (emergency change at night) — log the CHG in the ticket (`@ChangeRef`).

## Step 4 — Recover (SOP-01)
| Situation | Use |
|---|---|
| Failure before any data written / pipeline short | **Rerun** |
| Failure late in a long pipeline, earlier steps valid | **Rerun from failed activity** |
| Bad data entered earlier than the failing step (e.g. empty staging) | **Rerun from activity** → the Copy activity |
| Missed business date (no run happened) | **Trigger now** with that pRunDate (backfill), oldest date first |
| Data corrupted by non-idempotent code | fix code first, then rerun; if irrecoverable → SOP-05 PITR |

## Step 5 — Validate (never skip)
```sql
EXEC ops.usp_RunHealthChecks @RunDate = '<yyyyMMdd>';
SELECT CheckId, Status, Detail FROM ops.vw_LatestHealth ORDER BY CheckId;   -- 0 FAIL
```
Compare rows/revenue to source file row count. Confirm report has no `Unknown` segment.

## Step 6 — Communicate & close
- Communication entry to Finance BI: restored at hh:mm, validated.
- Resolve with **Resolution**; Close with **RootCause**; raise Problem if repeat (sql/60 R2) or if CAPA needed.

## Do NOT
- ❌ Hand-edit source files or delete fact rows manually (use reruns; they're auditable)
- ❌ Put the SQL admin password in ADF
- ❌ Disable a DQ gate to "make it green"
- ❌ Close a ticket when the pipeline is green but health checks fail
- ❌ Leave a trigger stopped after maintenance
