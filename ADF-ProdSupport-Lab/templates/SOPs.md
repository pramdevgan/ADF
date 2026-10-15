# Standard Operating Procedures (SOPs) — ADF Production Support

> SOP = reusable, step-by-step **task**. Runbooks reference SOPs.
> Format: Purpose · When · Pre-checks · Steps · Verification · Rollback.

---

## SOP-01 — Rerun, rerun-from-activity and backfill an ADF pipeline

**Purpose:** restore data after a fix. **When:** after root cause of a failed run is fixed, or a business date was missed.
**Pre-checks:** (1) fix is in place (test connection / file present); (2) the pipeline is **idempotent** for that date (see runbook table); (3) no other run of the same pipeline+date is in progress (Monitor filter *In progress*).

| Goal | Steps (ADF Studio) |
|---|---|
| **Rerun** whole pipeline, same parameters | Monitor → Pipeline runs → hover the failed run → **Rerun** icon (↻) → confirm. New RunId is created; original run stays Failed (history kept). |
| **Rerun from failed activity** | Monitor → open the failed run → toolbar **Rerun from failed activity**. Succeeded activities upstream are not re-executed. |
| **Rerun from a specific activity** | Monitor → open the run → select the activity in the list/diagram → **Rerun from activity**. |
| **Backfill / different parameters** | Author → open pipeline → **Add trigger → Trigger now** → enter pRunDate → OK. Run oldest missing date first. |
| **Bulk backfill** (many dates) | Prefer a *tumbling window trigger* or loop pipeline in prod; in lab, Trigger now per date. |
| **Cancel** a hung run | Monitor → run → **Cancel** (or *Cancel recursive* for parent + children). Record why in the ticket. |

**Verification:** new run Succeeded; `ops.PipelineRunLog` shows Succeeded with row counts; SOP-02 health check 0 FAIL.
**Rollback:** reruns don't need rollback if idempotent. If not idempotent → STOP, escalate L2.
**Record:** old + new RunIds and rerun type in the ticket.

---

## SOP-02 — Daily health check (L1, 08:00 IST)
1. Monitor → Alerts (last 24h) — every fired alert has a ticket?
2. ADF Monitor → Pipeline runs → Status Failed, last 24h — each has a ticket?
3. Monitor → Trigger runs — `TR_Daily_0200_IST` fired today?
4. Log Analytics → KQL K1, K6, K7.
5. Query editor: `EXEC ops.usp_RunHealthChecks '<yesterday yyyyMMdd>'` → 0 FAIL.
6. `sql/50` Q3 — open tickets, ACK/SLA flags.
7. Service Health — active Azure issues?
8. Write shift handover.
**Verification:** checklist signed in handover. **Escalate** any FAIL as a ticket (Source=HealthCheck, P2 for HC01–HC05).

---

## SOP-03 — Late, missing or bad source file
1. Confirm in Storage → `landing/<feed>/` (name, size, last modified). Preview first 5 lines (Edit/preview).
2. Compare with previous day's file: header, delimiter, row count, business date in rows.
3. Record findings in ticket (file name, size, timestamps, header diff).
4. Contact upstream owner (contact list in runbook) with: file expected, issue, example rows, deadline. Log as **Communication**.
5. Ticket → **OnHold** while waiting (note ETA).
6. When the corrected file arrives → overwrite in landing → SOP-01 (rerun from **Copy**).
7. **Never** hand-edit data files unless the data owner approves in writing (attach approval to ticket).
**Verification:** SOP-02 checks for that date.

---

## SOP-04 — Access and credential failures (403 / Login failed / Key Vault)
1. Test the linked service: ADF → Manage → Linked services → *LS_x* → **Test connection** → copy error.
2. **Storage 403:** Storage → IAM → *Role assignments* → is ADF MI listed with *Storage Blob Data Contributor*? Storage → Activity log for deletes. Also check Networking (firewall) changes.
3. **Key Vault:** KV → IAM → ADF MI has *Key Vault Secrets User*? KV → Secrets → *sql-adfloader-password* → versions (newest created when/by whom? KQL K12).
4. **SQL login failed:** password in KV ≠ DB user password, or user disabled/dropped (`SELECT name FROM sys.database_principals WHERE name='adfloader'`).
5. L1 has no IAM/secret rights → **escalate** (L3 Platform for IAM; L2 for credentials) with SBAR.
6. After fix: wait for propagation (RBAC can take minutes) → Test connection ✅ → SOP-01.
**Rollback:** secret — create a new version with the previous good value; RBAC — re-add role.
**Prevention:** managed identity everywhere possible; locks/Policy on IAM; rotation runbook that updates DB + KV together.

---

## SOP-05 — Data recovery with Azure SQL point-in-time restore (PITR)
**When:** data corrupted/deleted and **cannot** be rebuilt by rerunning pipelines (e.g., source files gone).
1. Determine the last good time T (from `ops.PipelineRunLog`, ticket timeline). Convert to UTC.
2. Portal → SQL database `sqldb-retail` → **Overview → Restore** → *Point-in-time* → restore point T → new database name `sqldb-retail-pitr-<date>` → Review + create. (Restores to a **new** DB; the original is untouched.)
3. Verify data in the restored DB.
4. Copy back only the affected rows/tables (e.g., `FactSales` for affected LoadDates) — via an ADF Copy activity or cross-DB scripts — under a **change** ticket.
5. Rebuild reports (rerun report step), run SOP-02 checks.
6. Delete the restored DB when done (cost).
**Note:** Basic tier retains PITR backups 7 days by default — verify your retention.

---

## SOP-06 — Safe trigger maintenance
1. Before deployments: record trigger states (Manage → Triggers).
2. Stop only the triggers needed; log the CHG number.
3. After deployment: **Start** them again; publish; verify next run time shown.
4. If a scheduled time was missed while stopped → SOP-01 backfill.
5. Add a final checklist item in every release: "triggers restored to recorded state".
