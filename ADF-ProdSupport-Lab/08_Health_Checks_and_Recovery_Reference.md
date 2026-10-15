# Reference — Health Checks & Recovery Procedures for ADF (consolidated)

## 1. Health-check catalogue

| Layer | Check | How (lab) | Frequency | Alert |
|---|---|---|---|---|
| Platform | Azure service issue in region | Service Health alert | continuous | email |
| Platform | Resource health of ADF/SQL/Storage/KV | resource → Resource health | on incident | – |
| Connectivity | Linked services reachable | ADF Manage → Test connection (or a tiny "ping" pipeline: Lookup `SELECT 1` + Get Metadata on landing) | hourly in prod | pipeline failure alert |
| Execution | Failed pipeline/activity/trigger runs | metric alert `PipelineFailedRuns`; KQL K1, K3, K8 | 1 min / daily review | yes |
| Timeliness | Last successful master ≤ 26 h | KQL K7, HC01 | hourly | yes (`alert-adf-master-stale`) |
| Performance | Duration > mean + 2σ | KQL K6 | daily | optional log alert |
| Data | duplicates, reconciliation, orphans, report = fact | `ops.usp_RunHealthChecks` HC02–HC05 | after load + hourly | via `PL_HealthCheck` failure |
| Ops hygiene | failed runs in 24 h, tickets breaching SLA | HC06, HC07 | hourly | WARN |
| Capacity/cost | DIU usage, run counts | ADF Monitor → Consumption; Cost Management | weekly | budget alert |
| Security | role assignment deletes, secret changes | Activity log, KV AuditEvent (K11, K12) | daily | optional |

## 2. Recovery decision matrix

| What broke | Recovery | ADF/Azure feature | Pre-condition |
|---|---|---|---|
| Transient (network, throttling, SQL failover) | auto-retry | Activity **Retry** + interval | idempotent activity |
| Pipeline failed, cause fixed | rerun | Monitor → **Rerun** | idempotent pipeline |
| Long pipeline failed late | rerun from failure | **Rerun from failed activity** | upstream outputs still valid |
| Bad data entered earlier step | rerun from chosen step | **Rerun from activity** | – |
| Business date(s) missed | backfill | **Trigger now** with parameter; tumbling-window trigger for series | parameterised by date |
| Run hung | stop it | **Cancel** / Cancel recursive | understand partial writes |
| Bad pipeline/config deployment | roll back code | Git revert → publish (CI/CD release of previous build) | Git-integrated factory |
| Deleted ADF pipeline (no Git) | recreate | from exported ARM template / JSON backup | backups exist |
| Landing file deleted/overwritten | restore file | Storage **soft delete** / **versioning** → Undelete / promote version | soft delete enabled |
| Table data corrupted, sources gone | restore DB | Azure SQL **point-in-time restore** to new DB → copy back | inside retention |
| Secret wrong | restore secret | KV: new version with good value (or recover deleted secret) | KV soft delete |
| RBAC removed | re-grant | IAM role assignment | change approval |
| Region outage | fail over / wait | Paired region DR plan (ADF re-deploy from Git, geo-redundant storage/SQL) | DR designed upfront |

## 3. Idempotency patterns (what makes reruns safe)
| Pattern | Example in lab |
|---|---|
| Truncate staging before copy | Copy pre-copy script `TRUNCATE TABLE stg.Sales` |
| Delete-then-insert by partition/date in one transaction | `dbo.usp_Load_Sales` |
| MERGE/upsert on business key | `dbo.usp_Load_Customers` |
| Rebuild report partition | `rpt.usp_Build_DailySalesSummary` |
| Validate before destroy | DQ gates run before DELETE |
| Unique constraints as safety net | (recommended: UNIQUE on OrderId) |
| Lineage column | `PipelineRunId` on every row |

## 4. Recovery validation checklist
- [ ] New run(s) Succeeded — RunIds recorded
- [ ] Row counts match source file
- [ ] `EXEC ops.usp_RunHealthChecks` → 0 FAIL
- [ ] Report spot check (no `Unknown`, totals sane vs previous days)
- [ ] Downstream consumers informed
- [ ] Triggers in expected state
- [ ] Ticket updated with evidence
