# Lab 4 — Incident Logging, Escalation & Resolution Tracking
⏱ ~30 min  |  Goal: run a ticket through its **whole life** correctly, escalate properly, and measure performance (MTTA / MTTR / SLA).

> Our "ITSM tool" is the `ops` schema in `sqldb-retail`. It mirrors the fields of ServiceNow / Jira Service Management, so the habits transfer 1:1.

| Lab table/column | ServiceNow equivalent |
|---|---|
| `ops.Incident.IncidentNumber` | Number (INC…) |
| Severity P1–P4 | Priority (from Impact × Urgency) |
| Status | State |
| AssignmentGroup / AssignedTo | Assignment group / Assigned to |
| `ops.IncidentWorkLog` (Note / Communication) | Work notes / Additional comments (customer-visible) |
| RootCause / Resolution | Resolution code + notes, Cause |
| ParentIncident | Parent incident (major incident linking) |
| ChangeRef | Caused by change / Change request |
| OccurrenceCount | Event/alert de-duplication count |

---

## 4.1 The lifecycle rules (enforced by `ops.usp_UpdateIncident`)

```
        ┌────────────┐
 New ──►│Acknowledged│──► InProgress ──► Resolved ──► Closed
  │     └────────────┘      ▲  │  ▲          │
  │                         │  │  │          └─(reopen)─► InProgress
  │              OnHold ◄───┘  │  └── Escalated
  │                 └──────────┘        ▲ │
  └─► Closed (duplicate / false alarm)  └─┘
```
- `Resolved` requires a **Resolution** text. `Closed` (from Resolved) requires a **RootCause**.
- Ack time → MTTA; Resolved time → MTTR. **Every status change auto-writes a timeline entry.**

**Try a forbidden move** (learn by error):
```sql
-- pick any New ticket
EXEC ops.usp_UpdateIncident @IncidentNumber='INC000001', @Author='me', @NewStatus='Resolved', @Note='done';
-- Msg 50101: Invalid status transition New -> Resolved   (you must Acknowledge first)
```

---

## 4.2 Exercise A — Full lifecycle of a P2 (use your S4 ticket, or create one)

If you need a fresh ticket:
```sql
EXEC ops.usp_RaiseIncident @PipelineName='PL_Ingest_Sales', @ErrorCode='ERR_COPY_SALES',
     @ErrorMessage='403 AuthorizationPermissionMismatch on landing/sales/sales_20261014.csv',
     @Source='Alert', @Severity='P3', @Category='Access', @Author='alert-adf-pipeline-failed';
SELECT TOP 1 IncidentNumber FROM ops.Incident ORDER BY IncidentId DESC;   -- e.g. INC000009
```
Replace `INC000009` below with yours. Note the **time** of each step.

```sql
-- 1) ACKNOWLEDGE (within 30 min for P2!)
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01', 'Acknowledged. L1 on-call investigating.',
     @NewStatus='Acknowledged', @AssignTo='learner01';

-- 2) TRIAGE: correct severity with justification
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01',
     'Impact: ALL file loads fail (sales+customers). 9AM CFO report at risk. Urgency medium (6h to SLA). => P2',
     @NewStatus='InProgress', @Severity='P2';

-- 3) EVIDENCE as work notes (text, RunIds - not just screenshots)
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01',
     'RunId 3f2a... Copy_Sales_To_Stg failed 403 AuthorizationPermissionMismatch. LS_ADLS test connection fails. Storage Activity log: Delete role assignment by user X at 10:05 IST.';

-- 4) ESCALATE (functional) with SBAR
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01',
     'S: All ADF file ingestion failing, P2. B: since 10:05 IST, role assignment for ADF MI removed on storage. A: Needs IAM fix, L1 has no rights. R: L3-Platform please re-add Storage Blob Data Contributor for adf-ps-xx by 11:00.',
     @NewStatus='Escalated', @EntryType='Escalation', @AssignmentGroup='L3-Platform';

-- 5) STAKEHOLDER COMMUNICATION (customer-visible update, every 60 min for P2)
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01',
     'Update to Finance BI team: Daily sales load delayed due to access issue on storage. Fix in progress with platform team. Next update 11:30 IST.',
     @EntryType='Communication';

-- 6) BACK FROM L3, recover
EXEC ops.usp_UpdateIncident 'INC000009', 'l3-platform', 'Role re-assigned 10:48. Test connection OK.',
     @NewStatus='InProgress', @AssignmentGroup='L1-DataOps';
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01', 'Rerun from failed activity, new RunId 77bc..., Succeeded. Health check 0 FAIL.';

-- 7) RESOLVE (service restored)
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01', 'Service restored, data validated (50 rows / 144809.95).',
     @NewStatus='Resolved',
     @Resolution='Re-added Storage Blob Data Contributor to ADF MI; reran PL_Ingest_Sales from failed activity; validated with health checks.';

-- 8) CLOSE (after confirmation / RCA)
EXEC ops.usp_UpdateIncident 'INC000009', 'learner01', 'User confirmed report OK. Problem PRB-LAB-01 raised for IAM change control.',
     @NewStatus='Closed',
     @RootCause='Role assignment deleted during unmanaged IAM clean-up (no change ticket). Contributing: no alert on role-assignment deletion.',
     @ChangeRef='CHG-LAB-002';

-- 9) REVIEW the whole ticket
EXEC ops.usp_GetIncident 'INC000009';
```

**Why each step matters**

| Step | If you skip it… |
|---|---|
| Acknowledge | Others don't know someone is on it → duplicate work, or nobody works it; MTTA breached |
| Severity justification | Next shift can't tell why it's P2; wrong people woken (or not) |
| Text evidence + RunIds | L2/L3 must redo your investigation; Microsoft support needs RunIds |
| Escalation note | "I called them" is not auditable; escalation SLA can't be measured |
| Communication | Business escalates to management instead → hierarchical escalation against you |
| Resolution vs Root cause | Resolution = what restored service; Root cause = why it broke. Mixing them blocks problem management |

---

## 4.3 Exercise B — Link child and parent incidents

A failing child under the master creates **two tickets**: child `P3 … ERR_COPY_*` (technical) and master `P2 PL_Master_Daily failed - ERR_MASTER` (business impact). Production practice: **one master incident**, children linked, comms only on the master.

1. Trigger now `PL_Master_Daily` with pRunDate `20261099` (a date with no files) → master + child fail.
2. ```sql
   SELECT IncidentNumber, Severity, PipelineName, ErrorCode, Status FROM ops.Incident WHERE Status='New' ORDER BY IncidentId;
   ```
3. Link the child to the master and close the master as the communication anchor later:
   ```sql
   EXEC ops.usp_UpdateIncident '<child INC>', 'learner01', 'Linked to master incident; technical work tracked here.', @ParentIncident='<master INC>';
   EXEC ops.usp_UpdateIncident '<master INC>', 'learner01', 'Business-impact incident. Child: <child INC>.', @NewStatus='Acknowledged';
   ```
4. Since 20261099 is not a real business date → close both as **false alarm / test** (New → Closed is allowed for this) with a note.
   - Requires: move master from Acknowledged → InProgress → Resolved → Closed with Resolution/RootCause, *or* do step 4 before acknowledging. Practise whichever path you're in.

---

## 4.4 Exercise C — De-duplication & alert storms
1. Make sure the S1 ticket (`PL_Ingest_Sales`/`ERR_COPY_SALES`) is still **open** (or create one by running with a missing date, e.g. `20261098`).
2. Trigger the same failing run 3 times.
3. `SELECT IncidentNumber, OccurrenceCount, LastUpdatedUtc FROM ops.Incident WHERE ErrorCode='ERR_COPY_SALES'` → **one** ticket, OccurrenceCount 4.
4. Discuss: why is OccurrenceCount useful? (Shows flapping, justifies severity increase, feeds problem management.) What would 4 separate tickets cost the on-call?

---

## 4.5 Exercise D — Time-based escalation & SLA watch
```sql
-- ticket ageing vs matrix  (sql/50 Q3)
SELECT i.IncidentNumber, i.Severity, i.Status, DATEDIFF(MINUTE,i.CreatedUtc,SYSUTCDATETIME()) AgeMin,
       e.AckWithinMins, e.ResolveWithinHrs*60 AS ResolveMins, e.L2, e.Management
FROM ops.Incident i JOIN ops.EscalationMatrix e ON e.Severity=i.Severity
WHERE i.Status NOT IN ('Resolved','Closed');
```
Rule of thumb used in this lab: **at 50 % of resolve SLA without a clear fix → escalate functionally; at 75 % → inform management (hierarchical).** For a P2 (8 h) that's 4 h and 6 h.

Simulate a breach for the HC07 check:
```sql
UPDATE ops.Incident SET CreatedUtc = DATEADD(HOUR,-9,CreatedUtc) WHERE IncidentNumber='<an open P2>';
EXEC ops.usp_RunHealthChecks '20261014';
SELECT * FROM ops.vw_LatestHealth WHERE CheckId='HC07';   -- WARN: 1 ticket in breach
```

---

## 4.6 Resolution tracking — KPIs

Run `sql/60_incident_kpi_reports.sql`:

| Report | Read it as |
|---|---|
| R1 KPI by severity | MTTA/MTTR per P; ResolveSLA_Pct target ≥ 95 % |
| R2 Top recurring | Same pipeline+error many times → raise a **Problem** record |
| R3 Backlog ageing | Anything > 24 h open needs a plan |
| R4 Ticket quality audit | Closed without root cause or with only system notes = bad hygiene |
| R5 Escalation history | Were escalations timely? |
| R6 Leaderboard | (fun) fastest MTTR in class |

Fill in for your session:

| KPI | Value | Comment |
|---|---|---|
| Tickets created | | |
| Auto vs manual | | |
| MTTA (P2) | | |
| MTTR (P2) | | |
| Repeat pipeline+error | | Problem candidate? |

---

## 4.7 Ticket quality peer review (swap with a neighbour, 5 min)

Score your neighbour's best ticket (`EXEC ops.usp_GetIncident`), 1 point each:

| # | Criterion | ✔ |
|---|---|---|
| 1 | Title says what/where/when (not "pipeline failed") | |
| 2 | Severity justified with impact + urgency | |
| 3 | RunId(s) recorded | |
| 4 | Exact error text recorded | |
| 5 | Business impact stated | |
| 6 | Timeline of actions with times | |
| 7 | Escalation logged (if any) with SBAR | |
| 8 | Recovery + validation evidence (rows/amount/health check) | |
| 9 | Resolution ≠ Root cause, both present | |
| 10 | Prevention / follow-up (Problem/CAPA) | |

**8–10 = production ready.**

---

## 4.8 Shift handover
Fill `templates/Shift_Handover_Template.md` for your open tickets and hand it to your partner. The partner must be able to continue **without asking you a single question**.

➡️ Next: `07_Lab5_E2E_Failure_Investigation.md`
