# Lab 3 — Simulated Production Support Scenarios
⏱ ~70 min (≈8–10 min per scenario)  |  Work in pairs: **Instructor/partner = "Chaos"**, **Learner = "On-call L1/L2"**

> Rule of the game: the on-call engineer **must not look at the injection step**. They start from the **symptom** (alert email / ticket / user complaint) exactly as in production.

## How to inject faults
- **Portal way:** upload/replace the named file in `landing/…` (Storage → Containers → landing → folder → Upload → ✅ *Overwrite if files already exist*), or do the IAM/Key Vault change described.
- **CLI way (Cloud Shell):** `bash scripts/10_fault_injection.sh S2 inject` … `bash scripts/10_fault_injection.sh S2 fix`

## The investigation method (use it for EVERY scenario)

```
1. ACKNOWLEDGE   ticket → Acknowledged (MTTA clock stops)            usp_UpdateIncident
2. SCOPE         which pipeline, which business date, since when?   ADF Monitor / ops.PipelineRunLog
3. LOCATE        which activity failed?                              run → activity list → ✘
4. READ ERROR    errorCode + message (copy TEXT into ticket)         activity → Error icon / Output JSON
5. WHAT CHANGED? data? code? access? secret? platform?               landing files, Activity log, sys.objects, KV versions, Service Health
6. CLASSIFY      Data | Code | Access | Credential | Platform | Upstream
7. DECIDE        fix myself (runbook) or escalate (matrix)?          templates/Escalation_Matrix
8. FIX           smallest safe fix
9. RECOVER       pick the RIGHT rerun type                           Monitor → Rerun options
10. VALIDATE     health check + numbers vs EXPECTED_VALUES.md        usp_RunHealthChecks
11. DOCUMENT     work notes, resolution, root cause → Resolved       usp_UpdateIncident
```

## Ticket quick-card (Query editor, logged in as `sqladminuser`)
```sql
-- see open tickets
SELECT IncidentNumber, Severity, Status, Title, OccurrenceCount FROM ops.Incident WHERE Status NOT IN ('Resolved','Closed');
-- acknowledge
EXEC ops.usp_UpdateIncident @IncidentNumber='INC000001', @Author='<you>', @NewStatus='Acknowledged', @Note='Ack. Investigating.', @AssignTo='<you>';
-- start work
EXEC ops.usp_UpdateIncident @IncidentNumber='INC000001', @Author='<you>', @NewStatus='InProgress', @Note='Failed activity Copy_Sales_To_Stg, error: ...';
-- add a note
EXEC ops.usp_UpdateIncident @IncidentNumber='INC000001', @Author='<you>', @Note='Rerun from failed activity started, new RunId ...';
-- resolve
EXEC ops.usp_UpdateIncident @IncidentNumber='INC000001', @Author='<you>', @NewStatus='Resolved',
     @Resolution='...', @RootCause='...';
```
Full lifecycle, escalation & closure rules → Lab 4.

---

## Scenario overview

| ID | Title | Category | Pipeline status | Detected by | Sev |
|---|---|---|---|---|---|
| S1 | Source file not delivered | Upstream / Data | ❌ Failed | Metric alert + auto-ticket | P3 |
| S2 | Corrupt values in file | Data | ❌ Failed | alert + auto-ticket | P3 |
| S3 | Empty file | Data quality | ❌ Failed (business rule) | alert + auto-ticket | P3 |
| S4 | ADF lost storage permission | Access | ❌ Failed | alert + auto-ticket | P2 |
| S5 | Bad secret rotation | Credential | ❌ Failed | **alert only** (logging DB unreachable) | P2 |
| S6 | Non-idempotent hotfix → duplicates on rerun | Code / Change | ✅ **Succeeded** | **Health check only** | P2 |
| S6b | Duplicate keys inside the file | Data quality | ❌ Failed | alert + auto-ticket | P3 |
| S7 | Trigger stopped → nothing ran | Config / Change | — (no run!) | **Freshness / health check only** | P2 |

Before starting: `sql/99_reset_lab.sql` is NOT needed; keep the baseline from Lab 1. If things get messy, reset and re-run the baseline (Lab 1 §1.9).

---

## S1 — Source file not delivered (late arrival)

**Inject (Chaos):** nothing to do — there is simply no `landing/sales/sales_20261016.csv` (CLI: `S1 inject` makes sure).
**Symptom:** Chaos says: *"Run PL_Ingest_Sales for business date 20261016 — the POS team says it's ready."* → Trigger now, pRunDate `20261016`.

**Investigate**
1. Email from `alert-adf-pipeline-failed` (1–3 min) with dimension Name = `PL_Ingest_Sales`.
2. Query editor → `SELECT * FROM ops.Incident` → a new **P3** `PL_Ingest_Sales failed - ERR_COPY_SALES` (auto-created by `SP_LogFailure_Copy`).
3. ADF Monitor → Pipeline runs → Failed run → activities: `SP_LogStart` ✔, `Copy_Sales_To_Stg` ✘, `SP_LogFailure_Copy` ✔, `Fail_Copy` ✘ (expected — it *is* the alarm).
4. Copy activity → **Error** icon. Expect a message along the lines of *"…operation failed… The specified path does not exist… PathNotFound…"* with the file `sales_20261016.csv`. Copy the text into the ticket.
5. Verify: Storage → landing → sales → no `sales_20261016.csv`. ✔ Root cause class = **Upstream / late file**.

**Fix & recover**
1. Note in ticket: *"Contacted POS team (ref …). ETA 30 min."* → status **OnHold** (waiting on third party; in real ITSM this can pause the SLA clock — policy dependent).
2. Chaos delivers the file: upload `data/fault_injection/S1_late_sales_20261016.csv` as `landing/sales/sales_20261016.csv` and `S1_late_customers_20261016.csv` as `landing/customers/customers_20261016.csv` (CLI `S1 fix`).
3. Monitor → failed run → **Rerun** (whole pipeline, same parameters).
   - *Why full rerun here:* nothing useful was loaded; pipeline is short and idempotent.
4. Validate: new run Succeeded; `SELECT COUNT(*) FROM dbo.FactSales WHERE LoadDate='20261016'` → **50**.
5. Ticket: OnHold → InProgress → **Resolved**, Resolution *"Late file received 10:42, pipeline rerun RunId …, 50 rows loaded"*, RootCause *"POS export job delayed upstream"*.

**Prevention ideas (write 1 in the ticket):** Event-based (storage event) trigger instead of fixed time; *Validation* activity / *Get Metadata exists* check with timeout; file-arrival SLA agreement with POS team.

---

## S2 — Corrupt values in the file

**Inject:** upload `data/fault_injection/S2_sales_20261014_badtypes.csv` **as** `landing/sales/sales_20261014.csv` (overwrite).
**Symptom:** Trigger now `PL_Ingest_Sales` pRunDate `20261014`.

**Investigate**
1. Ticket auto-created, *ERR_COPY_SALES*. Because an incident for `PL_Ingest_Sales`+`ERR_COPY_SALES` may still be open from S1 if you didn't resolve it → you'd see `OccurrenceCount` increase instead of a new ticket → that's **de-duplication**. (Resolve S1 first to get a clean new ticket.)
2. Copy activity error: a type-conversion message naming a value/column, e.g. converting `'two'` to `Int32` for column `Quantity` (exact wording varies).
3. Open the file (Storage → file → **Edit**/preview): find row with `two`, `N/A`, `2026-14-10`.
4. **Check the Copy output JSON** of the failed activity: `rowsRead`, `rowsCopied` — note that the copy failed **as a whole**; staging is left partly filled or empty. That's why the next step re-copies.

**Fix options — discuss before choosing**

| Option | How | When OK |
|---|---|---|
| A. Ask source to resend clean file | upload `data/corrected/sales_20261014.csv` | **Default** — data owner fixes data |
| B. Enable Copy **fault tolerance** → *Skip incompatible rows*, log to `rejected` container | Copy → Settings → Fault tolerance | Only if business **agreed** that partial loads are acceptable, and someone reviews rejects |
| C. Hand-edit the file | – | ❌ Never in prod without data-owner approval + audit |

**Recover**
1. Option A: upload corrected file (CLI `S2 fix`).
2. Monitor → failed run → **Rerun from failed activity**.
   - Expected: `SP_LogStart` is **not** executed again; the run restarts at `Copy_Sales_To_Stg`. Check the activity list of the new run.
   - Confirm the log: `SELECT TOP 3 * FROM ops.PipelineRunLog ORDER BY LogId DESC` → a row with TriggerName `rerun-from-activity` (our logging self-heals).
3. Validate: 50 rows, revenue 144809.95, `EXEC ops.usp_RunHealthChecks '20261014'` → 0 FAIL.
4. Resolve ticket.

*(Optional 3 min) Try option B:* re-inject, enable fault tolerance, rerun → the run **succeeds** with fewer rows → HC03 still PASS (copied rows = loaded rows) but revenue ≠ expected → discuss: "Green + reconciled + still wrong vs source" → source-to-target reconciliation must compare with **source file row count**, not only copy output. Disable fault tolerance again afterwards and restore the file.

---

## S3 — Empty file (header only)

**Inject:** upload `data/fault_injection/S3_sales_20261014_empty.csv` as `landing/sales/sales_20261014.csv`.
**Symptom:** Trigger now `PL_Ingest_Sales` `20261014`.

**Investigate**
1. Copy **succeeds** (0 rows — an empty file is valid CSV!). `SP_Load_FactSales` fails.
2. Error text contains **`DQ_EMPTY_FILE: stg.Sales has 0 rows…`** (raised by `THROW 50001` in our procedure). Ticket ErrorCode `ERR_LOAD_SALES`.
3. Important: because the load proc validates **before** the `DELETE`, yesterday's good 50 rows for 20261014 are **still in FactSales** → the report still shows the last good data. *Validate-before-delete protects production.*

**Recover — choose the rerun point carefully**
1. Upload corrected file (CLI `S3 fix`).
2. ❌ *Rerun from failed activity* would restart at `SP_Load_FactSales` — staging is **still empty** → fails again. Try it once to see it!
3. ✅ **Rerun** (full) or **Rerun from activity → Copy_Sales_To_Stg** → re-copies the file then loads.
4. Validate & resolve. RootCause: *"Source export produced header-only file (POS job ran before day close)."*

> 🎯 Lesson: *Rerun from failed activity* is not always right. Restart from **where the bad data entered**.

---

## S4 — ADF lost access to storage (RBAC removed)

**Inject (Chaos):** Storage account → **Access control (IAM)** → **Role assignments** → find `adf-ps-<initials>` / Storage Blob Data Contributor → **Remove** (CLI `S4 inject`). Wait ~5 min for propagation.
**Symptom:** Trigger now `PL_Ingest_Sales` `20261014`.

**Investigate**
1. Copy fails; error mentions **403** / *This request is not authorized to perform this operation using this permission* / **AuthorizationPermissionMismatch**.
2. Classify: **Access**. Same pipeline worked yesterday → *"what changed?"*
3. Storage account → **Activity log** → filter last 1 h → operation **"Delete role assignment"** → open → **Event initiated by** = who removed it, and when. Paste into the ticket.
   - (KQL alternative: K11 `AzureActivity` if you exported the activity log.)
4. Severity: all file-based loads are broken → **P2**. Update the ticket severity: `@Severity='P2'`.
5. **Escalate**: L1/L2 normally have no IAM rights → escalate to **L3 Platform/Cloud** with SBAR (Lab 4 §4.4). Add `@EntryType='Escalation', @AssignmentGroup='L3-Platform'`.

**Fix & recover**
1. "L3" re-adds the role (Lab 2 §2.8a) (CLI `S4 fix`). Wait a few minutes; LS_ADLS → **Test connection** until ✅.
2. Monitor → **Rerun from failed activity**. Validate.
3. Resolve: RootCause *"Role assignment removed by <user> during IAM clean-up, no change ticket"*. Problem/CAPA: Azure Policy / resource **lock**, IAM changes via change management, alert on role-assignment deletes.

---

## S5 — Bad secret rotation in Key Vault

**Inject (Chaos):** Key Vault → Secrets → `sql-adfloader-password` → **+ New Version** → value `Wr0ng#Rotated!Pwd` → Create (CLI `S5 inject`).
**Symptom:** Trigger now `PL_Ingest_Sales` `20261014`.

**Investigate**
1. Run fails at **`SP_LogStart`** after its 2 retries (~2–3 min). Error contains **`Login failed for user 'adfloader'`** (SQL error 18456).
2. Query editor: `SELECT * FROM ops.Incident` → **no new ticket!** Why? The logging/ticketing DB is the very thing ADF can't log in to. → **Monitoring blind spot**: this is why the **Azure Monitor alert is independent of the database**.
3. Create the ticket **manually** from the alert:
   ```sql
   EXEC ops.usp_RaiseIncident @PipelineName='PL_Ingest_Sales', @ErrorCode='SQL_LOGIN_FAILED',
        @ErrorMessage='Login failed for user adfloader (from ADF Monitor, RunId ...)',
        @Source='Alert', @Severity='P2', @Category='Credential', @Author='<you>';
   ```
4. ADF Studio → Manage → `LS_AzureSql` → **Test connection** → fails the same way → confirms credential, not pipeline logic.
5. *What changed?* Key Vault → Secrets → `sql-adfloader-password` → **versions list**: newest version created minutes ago. Who? → KQL **K12** (KV AuditEvent → `SecretSet`, caller UPN). Activity Log will **not** show it (data-plane).

**Fix & recover**
1. Correct way: create a **new version with the correct password** (CLI `S5 fix`) — or, if the DB password really was changed, update the DB user to match. Never "fix" by putting the admin password into ADF.
2. Test connection ✅ → Monitor → **Rerun** (full: `SP_LogStart` itself failed).
3. Validate & resolve. CAPA: rotation SOP (change DB password + KV in one controlled step, test connection, rollback = previous version), use **managed identity to SQL** to remove passwords entirely.

---

## S6 — Non-idempotent "hotfix" → duplicates (the silent incident)

**Inject (Chaos):** Query editor → run `sql/90_FAULT_S6_nonidempotent_hotfix.sql`.
**Symptom:** Chaos: *"Operator re-ran the 14-Oct sales load once more because of a network blip"* → Trigger now `PL_Ingest_Sales` `20261014` **once** (20261014 already holds the 50 good rows from earlier).

**Investigate**
1. The run **Succeeded**. No alert. No ticket. 😱
2. Business complaint (Chaos): *"CFO says revenue for 14-Oct doubled."* — or you catch it first:
   Trigger now `PL_HealthCheck` `20261014` → **Failed** → alert → ticket(s) **P2** `Health check HC02/HC03 failed …` (Source = HealthCheck).
3. `SELECT CheckId, Status, Detail FROM ops.vw_LatestHealth` → HC02 FAIL (50 duplicated OrderIds), HC03 FAIL (Copied=50, InFact=100). HC05 FAIL too (only the child ran, so the report still holds the old total). Note: had the *master* been rerun, report and fact would be **equally wrong** and HC05 would PASS — integrity ≠ correctness; that's why HC02/HC03 exist.
4. Lineage: `sql/50` **Q6** → **2 different PipelineRunId** values for LoadDate 20261014 (earlier good load + this rerun, 50 rows each) → rows were *appended*, not replaced.
5. *What changed?* `sql/50` **Q9** → `usp_Load_Sales` modified minutes ago. (In prod: Git history / release pipeline.)

**Fix & recover**
1. Ticket: InProgress, ChangeRef `CHG-LAB-001` (emergency change to restore the code).
2. Run `sql/91_FIX_S6_restore_idempotent_load.sql` (STEP 1 evidence → STEP 2 restore).
3. Data repair = **rerun**, not manual delete: Trigger now `PL_Master_Daily` `20261014` → idempotent load deletes the 100 rows and inserts 50; report rebuilt.
4. Health check → all PASS → resolve. RootCause *"Unreviewed hotfix removed idempotent delete; rerun duplicated data"*. CAPA: unique constraint on OrderId, mandatory code review/Git, health check scheduled hourly.

---

## S6b — Duplicate keys inside the source file

**Inject:** upload `data/fault_injection/S6b_sales_20261014_duplicates.csv` as `landing/sales/sales_20261014.csv`.
**Symptom:** Trigger now `PL_Ingest_Sales` `20261014` → fails at `SP_Load_FactSales` with **`DQ_DUPLICATE_KEYS: 3 OrderId value(s)…`**.
**Investigate:** `SELECT OrderId, COUNT(*) FROM stg.Sales GROUP BY OrderId HAVING COUNT(*)>1` → staging still holds the file → shows the 3 keys (put them in the ticket — the data owner needs them).
**Fix:** source re-sends (CLI `S6b fix` / upload `data/corrected/sales_20261014.csv`) → **Rerun from activity → Copy_Sales_To_Stg** (or full rerun) → validate → resolve.
*Contrast with S6:* here the DQ gate **stopped** bad data (good design); in S6 the gate was removed.

---

## S7 — Trigger stopped: nothing ran (silent SLA breach)

**Story:** It is *17-Oct 08:00*. Files for business date **20261017** arrived on time at night, but a deployment engineer stopped the trigger "temporarily" and forgot to restart it. *(In this lab the trigger's start date is in the future, so we simulate the missed 02:00 run; the investigation is identical.)*

**Inject (Chaos):** upload `data/fault_injection/S7_sales_20261017.csv` → `landing/sales/sales_20261017.csv` and `S7_customers_20261017.csv` → `landing/customers/customers_20261017.csv`; ADF Studio → Manage → Triggers → `TR_Daily_0200_IST` → **Stop** → Publish (CLI `S7 inject`).

**Symptom:** No alert at all. Learner performs the **08:00 daily health-check SOP** (Lab 2 §2.9).

**Investigate**
1. Trigger now `PL_HealthCheck` pRunDate `20261017` → Failed → tickets: **HC01** (0 rows), HC03 (no successful run), HC05.
2. ADF Monitor → Pipeline runs (last 24h) → **no run** for `PL_Master_Daily` with 20261017. Nothing failed — nothing ran.
3. Monitor → **Trigger runs** → no run of `TR_Daily_0200_IST`.
4. Manage → **Triggers** → status **Stopped**.
5. Who/when: Portal → Data factory → **Activity log** → operation like *"Stops a trigger"* → initiated by. (KQL K11.)
6. KQL K7 → `Breach = YES` (once real history exists).

**Fix & recover**
1. **Start** the trigger (Manage → Triggers → Start; Publish if needed) (CLI `S7 fix`).
2. **Backfill** the missed date: Author → `PL_Master_Daily` → Add trigger → **Trigger now** → pRunDate `20261017`.
   - *Why not wait for tonight?* Tonight's run loads 20261018 only — 20261017 would stay missing forever. Backfill = run the missed business dates explicitly.
3. Health check `20261017` → PASS (50 rows). Resolve. Notify business: *"17-Oct report available 08:40 IST (delayed)"*.
4. CAPA: freshness alert (Lab 2 §2.6), trigger state check in release pipeline, "stop trigger" only under a change with a re-enable step.

---

## After all scenarios — reflection (5 min)

| Question | Your answer |
|---|---|
| Which scenarios produced **no** auto-ticket, and why? | S5 (DB unreachable), S6 (green), S7 (no run) |
| Which rerun type did you use per scenario and why? | |
| Which incident would have hurt the business most if undetected? | |
| One monitoring improvement you'd add | |

➡️ Next: `06_Lab4_Incident_Logging_Resolution_Tracking.md`
