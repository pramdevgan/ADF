# Lab 2 — Monitoring, Alerting & Health Checks
⏱ ~35 min  |  Goal: **we hear about a problem before the CFO does.**

Detection layers we build:

| Layer | Detects | Tool |
|---|---|---|
| 1. Metric alert | Any pipeline run **Failed** | Azure Monitor metric `PipelineFailedRuns` |
| 2. Log-search alert | Failed runs with pipeline name / RunId in the alert payload | Log Analytics + KQL |
| 3. Health-check pipeline | Data **wrong** or **missing** though pipelines are green | `PL_HealthCheck` + `ops.usp_RunHealthChecks` |
| 4. Freshness query | **Nothing ran** (trigger stopped) | KQL K7 / HC01 |
| 5. Service/Resource health | Azure platform outage | Service Health alert |

---

## 2.1 Send ADF logs to Log Analytics (Diagnostic settings)

1. Portal → Data factory → **Monitoring → Diagnostic settings** → **+ Add diagnostic setting**.
2. Name: `diag-adf-to-law`.
3. **Logs → Categories** ✅ **Pipeline runs log**, ✅ **Activity runs log**, ✅ **Trigger runs log**. (Leave SSIS/Sandbox/Airflow categories off — not used.)
   **Metrics** ✅ AllMetrics.
4. **Destination details** ✅ **Send to Log Analytics workspace** → `law-adf-ps` → Destination table: **Resource specific**.
   - *Why resource specific:* creates clean typed tables `ADFPipelineRun`, `ADFActivityRun`, `ADFTriggerRun` instead of one generic `AzureDiagnostics` table → simpler, faster KQL.
5. **Save**.
6. Do the same on the **Key Vault**: Monitoring → Diagnostic settings → ✅ **audit** (AuditEvent) → `law-adf-ps` → Save.
   - *Why:* secret changes are **data-plane** operations — they do **not** appear in the Activity Log. Without this you cannot answer "who changed the password?" in S5.
7. (Optional, for "who changed what") Portal → **Monitor → Activity log → Export Activity Logs** → + Add diagnostic setting → ✅ Administrative → `law-adf-ps`. Enables KQL K11 (`AzureActivity`).

> ⏳ First logs appear after ~5–15 min. Trigger a run of `PL_Master_Daily` (pRunDate `20261014`) now so data is there when you query.

---

## 2.2 ADF Studio Monitor hub — guided tour (do each click)

| Where | What you see | Prod-support use |
|---|---|---|
| Monitor → **Pipeline runs** → *Triggered* | All runs; filters: time range, status, pipeline, **Run ID**, annotations | Morning check: filter *Status = Failed*, last 24h |
| Toggle **List / Gantt** | Overlapping runs on a timeline | Spot long-runners, concurrency clashes |
| Click a run name | **Activity runs** list + diagram | Which activity failed, duration per activity |
| Activity row → **Input** / **Output** / **Error** icons (hover) | JSON for that activity | Rows read/copied, throughput, **errorCode + message** |
| Copy activity → 👓 **Details** | Copy monitoring view | Rows, throughput, queue time, **which stage was slow** |
| Run row → **Rerun** / **Rerun from failed activity** / ... | Recovery | Used in Lab 3 |
| Run row → **Consumption** | DIU-hours, activity runs | Cost incidents |
| Monitor → **Trigger runs** | Did the schedule fire? Status | Freshness incidents (S7) |
| Monitor → **Integration runtimes** | IR status, node health (self-hosted) | IR outage incidents |
| Monitor → **Alerts & metrics** | ADF's shortcut to Azure Monitor alerts | Create/edit alerts from inside ADF |

> Data retention in ADF Monitor = **45 days**. Older than that → Log Analytics.

---

## 2.3 Action group (who gets notified)

1. Portal → **Monitor → Alerts → Action groups → + Create**.
2. Basics: RG `rg-adf-prodsupport-lab`, Region Global, Name `ag-adf-ps-oncall`, Display name `adfoncall` (≤12 chars).
3. **Notifications**: type **Email/SMS message/Push/Voice** → name `oncall-email` → ✅ Email → your address.
   - *Prod:* also SMS/voice for P1, a webhook/ITSM connector to create a ServiceNow/Jira ticket, or Logic App to post in Teams.
4. **Review + create**. Confirm the "added to action group" email you receive.

---

## 2.4 Metric alert — any failed pipeline run

1. Data factory → **Monitoring → Alerts → + Create → Alert rule** (scope pre-filled with the factory).
2. **Condition** → Signal name: **Failed pipeline runs metrics** (`PipelineFailedRuns`).
   - Split by dimensions: **Name** (pipeline name) → *Select all* (also **Include all future values**). Optionally **FailureType**.
     - *Why split:* one alert per failing pipeline with its name in the email, instead of one vague "something failed".
   - Threshold: Static · Aggregation **Total** · Operator **Greater than** · Value **0**.
   - **Check every 1 minute**, **Lookback period 5 minutes**.
3. **Actions** → select `ag-adf-ps-oncall`.
4. **Details** → Severity **2 – Warning** (Azure alert severity 0=Critical…4=Verbose; it is *not* the same as P1–P4 ticket priority); Name `alert-adf-pipeline-failed`; Description "Any ADF pipeline failed – follow Runbook_PL_Master_Daily"; ✅ Automatically resolve alerts.
   - *Tip:* put the **runbook link** in the description — the on-call engineer opens it from the email.
5. **Review + create**.

Other useful ADF metrics: *Failed activity runs metrics*, *Failed trigger runs metrics*, *Cancelled pipeline runs metrics*, *Integration runtime available node count* (self-hosted IR).

---

## 2.5 Log-search alert (richer payload)

1. **Log Analytics workspace `law-adf-ps` → Logs** → paste query **K10** from `kql/adf_support_queries.kql` → Run (after a failure exists you'll see rows).
2. **+ New alert rule** (from the query toolbar).
3. Condition: Measure **Table rows**, Aggregation granularity **5 min**; **Split by dimensions**: `PipelineName`, `RunId`; Operator **Greater than 0**; Frequency **5 min**.
4. Actions: `ag-adf-ps-oncall`. Details: Severity 2, name `alert-adf-failed-run-log`.
5. Create.

*Why both alerts?* Metric alerts are **fast** (~1–2 min). Log alerts are slower (ingestion delay) but carry **RunId** and allow complex logic (e.g., "failed AND business hours", duration anomalies K6, freshness K7).

---

## 2.6 Freshness alert (catches "nothing ran")

1. In `law-adf-ps` → Logs → paste **K7** → Run.
2. New alert rule → Measure **Table rows**, condition with a query filter: modify the last line to `| where Breach == "YES"` → rows > 0 → frequency 1 h → action group → name `alert-adf-master-stale`.
   - This is the only alert that fires when the trigger is **stopped** (Scenario S7) — the failed-run alerts stay silent because nothing fails.

---

## 2.7 Platform health

1. Portal → **Service Health → Health alerts → + Create service health alert** → Services: *Data Factory, SQL Database, Storage, Key Vault*; Regions: *Central India*; Event types: Service issue, Planned maintenance → action group → create.
   - *Why:* when Azure itself has an outage, your first runbook step is **"Is it us or Microsoft?"** — this answers it in your inbox.
2. Bookmark: each resource → **Help → Resource health**.

---

## 2.8 Run the health checks manually and understand each

```sql
EXEC ops.usp_RunHealthChecks @RunDate = '20261014';
SELECT CheckId, CheckName, Status, Detail FROM ops.vw_LatestHealth ORDER BY CheckId;
```

| Check | Question it answers | Failure means |
|---|---|---|
| HC01 Freshness | Is today's data there? | Load didn't run / failed / wrong date |
| HC02 Duplicates | Same order twice? | Non-idempotent rerun, duplicate source |
| HC03 Reconciliation | Rows in table = rows copied? | Partial load, duplication, manual tampering |
| HC04 Referential | Every sale has a customer? | Incomplete master data → report shows "Unknown" |
| HC05 Report integrity | Report total = fact total? | Report not rebuilt after a fix |
| HC06 (WARN) | Any failed run in 24h? | Open/unfinished incidents |
| HC07 (WARN) | P1/P2 ticket past SLA? | Escalation needed |
| HC08 (WARN) | Customer dim refreshed? | Customer feed stale (MERGE only touches changed rows → informational) |

Then run the pipeline version: `PL_HealthCheck` → Trigger now → `20261014` → Succeeded.

---

## 2.9 Daily health-check SOP (L1, 08:00 IST) — practise it once now

| # | Step | Where | Expected |
|---|---|---|---|
| 1 | Any fired alerts in last 24h? | Monitor → Alerts | None / all have tickets |
| 2 | Failed runs last 24h | ADF Monitor (Status=Failed) **or** KQL K1 | 0 or each has ticket |
| 3 | Did the 02:00 trigger fire? | Monitor → Trigger runs | 1 Succeeded |
| 4 | Master succeeded for yesterday? | KQL K7 / `ops.PipelineRunLog` | Succeeded |
| 5 | Durations normal? | KQL K6 | no rows |
| 6 | Data checks | `EXEC ops.usp_RunHealthChecks` | 0 FAIL |
| 7 | Open tickets & SLA | `sql/50` Q3 | none breaching |
| 8 | Azure platform | Service Health | no active issue |
| 9 | Write shift handover | `templates/Shift_Handover_Template.md` | |

➡️ Next: `05_Lab3_Simulated_Incidents.md`
