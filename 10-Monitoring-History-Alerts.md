# 10 – Monitor Runs, Analyze Execution History & Production Alerts (≈ 20 min)

**Objectives**
1. Monitor successful and failed runs
2. Analyze execution history
3. Review (and create) common production alerts

**Builds on:** the pipelines from Files 04–07. No new resources needed.

| Clock | Part |
|---|---|
| 0:00 – 0:04 | A. Generate success + failure runs (reuse PL_01, PL_03, PL_04) |
| 0:04 – 0:10 | B. Monitor successful and failed runs |
| 0:10 – 0:15 | C. Analyze execution history |
| 0:15 – 0:20 | D. Production alerts – review + create one |
| *(optional, after lab)* | E. Long-term history with Log Analytics + KQL |

---

## Part A – Generate runs to monitor (4 min)

You need at least one success and one failure in the history. Publish everything first (**Publish all**), then use **Add trigger → Trigger now**. Triggered runs show up in Monitor → **Triggered**, which is what production monitoring looks at. Debug runs are on a separate tab.

| # | Pipeline | Parameter / setup | Expected result |
|---|---|---|---|
| 1 | `PL_01_Copy_Employees` | – | ✅ Succeeded |
| 2 | `PL_04_Execution_Flow_Demo` | `p_ForceFail = false` | ✅ Succeeded (also starts PL_01 as a child run) |
| 3 | `PL_04_Execution_Flow_Demo` | `p_ForceFail = true` | ✅ Succeeded – failure was **handled** (Try-Catch, File 07) |
| 4 | `PL_03_Load_Employees_To_Sql` *(if you did File 06)* | Upload `employees_bad.csv` as `input/employees.csv` | ❌ **Failed** |
| 4-alt | No SQL? Use `PL_02_Copy_All_Sales_Files` | `p_SourceFolder = doesnotexist` | ❌ **Failed** (Get Metadata: path not found) |

> After run 4, re-upload the good `employees.csv`.

**Why it matters:** run 3 shows something that confuses people in production. An **activity failed but the pipeline succeeded**. If you only alert on pipeline failures, you won't hear about it. Part D comes back to this.

---

## Part B – Monitor successful and failed runs (6 min)

### B1. Open the Monitor hub
ADF Studio → **Monitor (📈)** → **Runs → Pipeline runs** → **Triggered** tab.

| Tab | Shows |
|---|---|
| **Triggered** | Runs of the **published** pipelines (manual Trigger now, schedule, event, Execute Pipeline children) |
| **Debug** | Runs started with the Debug button – development only |

### B2. Filter the list (toolbar)

| Filter | Set to | Why |
|---|---|---|
| **Time range** | Last 24 hours (or Custom) | Default view; history goes back **45 days** |
| **Pipeline name** | All, or pick one | Narrow to one pipeline |
| **Status** | `Failed` first, then `Succeeded` | Triage failures first |
| **Runs** | *Latest runs* vs *All runs* | *Latest* hides older attempts once a run has been rerun |
| **Triggered by** | Manual trigger / TR_Every15Min | See which trigger started it |
| **Annotations** | `lab` | Tags you set in pipeline Properties (File 04) – group pipelines by team/system |
| **Add filter → Run ID** | paste a GUID | Jump to one specific run (e.g. from a log table or email alert) |

Use **Edit columns** to add *Run ID*, *Parameters*, *Annotations*, *Error*. **Refresh** reloads the list. Status doesn't update live.

### B3. Read a **successful** run (PL_01)
1. Click the pipeline name → **Activity runs** opens.
2. In the row for `CopyEmployees`:
   - **→ Input**: the resolved settings that were sent (source/sink, with expressions evaluated).
   - **← Output**: `rowsRead`, `rowsCopied`, `dataRead`, `copyDuration`, `throughput`, `usedDataIntegrationUnits`.
   - **👓 Details**: the copy monitoring view. Duration is split into *Queue* → *Pre-copy script* → *Transfer (Reading / Writing)*. This is where you find bottlenecks.
3. **What to check on a success:** `rowsCopied` matches what you expected (10). A run that copied **0 rows** still shows *Succeeded*, which is a common silent problem in production.

### B4. Read a **failed** run (run 4)
1. Status filter = **Failed** → click the pipeline name.
2. Find the activity with ❌ → click the **Error** icon (💬) to see:

| Field | Example | Meaning |
|---|---|---|
| Error code | `2200` (Copy), `2108`, `InvalidTemplate` | Look it up in the [ADF troubleshooting guide](https://learn.microsoft.com/azure/data-factory/data-factory-troubleshoot-guide) |
| Failure type | **User configuration issue** / **System error** | *User* = you need to fix data or config. *System* = transient, usually retry |
| Message | `Failed to convert value 'ABC' to type Int32` | The actual cause |
| Failed activity | `CopyToSql` | Where it broke |

3. Compare **Input** with what you meant to configure. Most expression errors show up here, for example a parameter that resolved to empty.

### B5. Gantt view and parent/child runs (PL_04)
1. Open a PL_04 run → switch **List ↔ Gantt** (top of the activity list).
   - Bars that overlap ran **in parallel**. Gaps are Wait activities or dependencies.
   - `Wait_5s` shows as a clear 5-second bar.
2. In the activity list, `Run_PL01` (Execute Pipeline) has a link to the **child run**. Click it to open PL_01's run. The child has its **own Run ID** and shows its parent, so you can follow a master pipeline down to every child.
3. Back in the Triggered list, the PL_01 run started by PL_04 shows **Triggered by: PL_04_Execution_Flow_Demo**.

### B6. Act on runs

| Action | Where | Use when |
|---|---|---|
| **Rerun** | ⟳ icon on the pipeline row | Transient failure; reruns everything with the same parameters |
| **Rerun from failed activity** | Activity runs view → *Rerun from failed activity* | Long pipelines: skips activities that already succeeded |
| **Rerun from activity** | Right-click / select an activity → Rerun from activity | Restart from any chosen step |
| **Cancel** / recursive cancel | ⊘ on an in-progress run | Stuck or wrong run; *recursive* also cancels child pipelines |

Try it: on failed run 4, re-upload the good `employees.csv` → **Rerun from failed activity** → it succeeds. The list now shows the rerun grouped under the original (switch *Runs* to *All runs* to see both).

---

## Part C – Analyze execution history (5 min)

### C1. Questions to answer from history
Use Monitor → Pipeline runs with **Time range = Last 7 days** (or custom up to 45 days):

| Question | How |
|---|---|
| How often does pipeline X fail? | Pipeline name = X, Status = Failed → count rows |
| Is it getting slower? | Sort by **Duration**; compare runs of the same pipeline |
| Which trigger caused the failures? | Filter *Triggered by* |
| Same error every time? | Add the *Error* column; repeated messages point to a config or data cause, not a transient one |
| What did a run cost? | Pipeline row → **Consumption** (📊 icon): activity runs, DIU-hours, orchestration units. This is the basis of the bill |
| Did the schedule actually fire? | **Monitor → Trigger runs** – each firing, status, and which pipelines it started |

### C2. Dashboards (built-in charts)
**Monitor → Dashboards** (in some UI versions, a charts header above the run list). It shows succeeded/failed/in-progress counts for pipeline, activity and trigger runs over the time range. Use it for a quick daily look at overall health.

### C3. Export history
Pipeline runs list → **Export to CSV** (toolbar). Open it in Excel to pivot by pipeline/status/duration. Useful for a weekly report.

### C4. Your own audit log (from File 06)
Your `dbo.PipelineRunLog` table is history that **you control and keep as long as you like**. Monitor only keeps 45 days.
```sql
SELECT PipelineName, Status, COUNT(*) AS Runs,
       SUM(RowsCopied) AS TotalRows, MAX(LogTime) AS LastRun
FROM dbo.PipelineRunLog
GROUP BY PipelineName, Status;
```
The **RunId** in this table matches the Run ID in Monitor (B2 → *Add filter → Run ID*). That's how you connect your business log to ADF's technical log.

### C5. Make history easier to search: User properties
On any activity → **User properties** tab → **+ New** (up to 5 per activity), e.g. on `CopyToSql`:

| Name | Value |
|---|---|
| `SourceFile` | `employees.csv` |
| `TargetTable` | `dbo.Employees` |

After the next run, open Monitor → Activity runs → **Edit columns** → add the user properties. You can now see and filter **what** each activity processed without opening its Input.

---

## Part D – Common production alerts (5 min)

### D1. Where alerts live
- ADF Studio → **Monitor → Alerts & metrics**, **or**
- Azure portal → Data factory `adf-lab-<initials>` → **Monitoring → Alerts**

They are **Azure Monitor metric alerts**. A rule has three parts: **Condition** (metric + threshold), **Action group** (who gets notified and how), and **Details** (name, severity).

### D2. Common production alerts – review

| # | Alert | ADF metric / signal | Typical condition | Severity | Why it matters |
|---|---|---|---|---|---|
| 1 | **Pipeline failed** | *Failed pipeline runs metrics* | Count > 0, dimension *Name* = critical pipelines | Sev 1 | The basic alert – data didn't arrive |
| 2 | **Activity failed** | *Failed activity runs metrics* | Count > 0 (filter *FailureType*) | Sev 2 | Catches **handled** failures that leave the pipeline Succeeded (run 3 in Part A) |
| 3 | **Trigger failed** | *Failed trigger runs metrics* | Count > 0 | Sev 1 | Schedule/event didn't start the pipeline at all |
| 4 | **Pipeline running too long (SLA)** | *Elapsed time pipeline runs metrics* | Count > 0 | Sev 2 | Pipeline exceeded the expected duration you set in pipeline **Settings → Elapsed time metric** |
| 5 | **Self-hosted IR offline** | *Integration runtime available node count* | < 1 | Sev 1 | On-prem copies will all fail |
| 6 | **IR overloaded** | *Integration runtime CPU utilization* / *available memory* | CPU > 80 % for 15 min | Sev 3 | Slow runs, timeouts |
| 7 | **IR queue backing up** | *Integration runtime queue duration* / *queue length* | Above your baseline | Sev 3 | Not enough IR capacity; activities wait before starting |
| 8 | **Factory near limits** | *Total entities count* / *Total factory size (GB)* | > 80 % of limit | Sev 4 | Factory limits on number of objects |
| 9 | **Cancelled runs** | *Cancelled pipeline runs metrics* | Count > 0 | Sev 3 | Someone stopped or timed out production work |
| 10 | **Silent data problem** (0 rows) | *No built-in metric* – design it in the pipeline | If `rowsCopied == 0` → **Fail** activity | Sev 2 | Pipeline succeeds but loads nothing; the Fail activity turns this into alert #1 |

Severity scale: Sev 0 Critical → Sev 4 Verbose.

### D3. Hands-on: create the "Pipeline failed" alert (3 min)

1. **Monitor → Alerts & metrics → + New alert rule**.
2. **Alert rule name:** `ALR-ADF-PipelineFailed` · **Severity:** Sev 1.
3. **Target criteria → + Add criteria**
   - Signal: **Failed pipeline runs metrics**
   - Dimension **Name**: select `PL_03_Load_Employees_To_Sql` (or *Select all*)
   - Dimension **FailureType**: select all
   - Condition: **Greater than**, Threshold **0**
   - Period (aggregation): **Over the last 5 minutes** · Frequency: **Every 1 minute**
   - Click **Add criteria**.

   *Why these values:* any single failure fires the alert. The 1-minute frequency keeps notification delay short.
4. **Configure notification → + Create action group**
   - Name: `AG-DataTeam` · Short name: `DataTeam`
   - **+ Add notification** → Email/SMS/Push/Voice → your email (SMS optional) → OK.
   - *Why an action group:* one reusable list of contacts and actions (email, SMS, Teams/webhook, Logic App, Azure Function) shared by many alert rules.
5. **Create alert rule**.
6. **Test:** trigger the failing run again (Part A, run 4). Within about 5 minutes you get an email from Azure Monitor with the metric value and a link back to the factory.
7. Optional: add a second rule with **Failed activity runs metrics** > 0, then trigger PL_04 with `p_ForceFail = true`. You get this alert even though the pipeline shows Succeeded.

> Metric alerts and Monitor views do **not** show the error message. The email tells you *that* something failed. You still go to Monitor (Part B4) to see *why*.

### D4. Production alert hygiene (talking points)
- Alert on **critical pipelines** using the *Name* dimension, so non-critical ones don't flood you.
- Send Sev 1 to on-call (SMS/Teams) and Sev 3–4 to email or a daily digest.
- Add **Retry = 2–3** on Copy/Script activities (File 04, General tab). This cuts transient *System error* alerts.
- Every alert should have a runbook: which pipeline, who owns it, and what to check first (Part B4).
- Turn off or adjust alerts that fire often without needing action. Otherwise people start ignoring them.

---

## Part E (optional, after the lab) – Keep history beyond 45 days with Log Analytics

1. Azure portal → **Log Analytics workspaces → + Create** → `law-adf-lab` in `rg-adf-lab`.
2. Data factory → **Monitoring → Diagnostic settings → + Add diagnostic setting**
   - Name: `diag-to-law`
   - Logs: ✅ **Pipeline runs log**, ✅ **Activity runs log**, ✅ **Trigger runs log**
   - Metrics: ✅ AllMetrics
   - Destination: **Send to Log Analytics workspace** → `law-adf-lab` → table type **Resource specific**
     *(Resource specific = separate tables `ADFPipelineRun`, `ADFActivityRun`, `ADFTriggerRun`, which are easier to query than the single `AzureDiagnostics` table)*
3. Run a few pipelines and wait about 10–15 minutes for the first data. Then open workspace → **Logs**:

```kusto
// Failures in the last 7 days, newest first
ADFPipelineRun
| where TimeGenerated > ago(7d) and Status == "Failed"
| project TimeGenerated, PipelineName, RunId, FailureType
| order by TimeGenerated desc

// Success rate and average duration per pipeline
ADFPipelineRun
| where TimeGenerated > ago(7d) and Status in ("Succeeded","Failed")
| summarize Runs=count(), Failed=countif(Status=="Failed"),
            AvgMin=avg(datetime_diff('second', End, Start))/60.0 by PipelineName
| extend SuccessRatePct = round(100.0*(Runs-Failed)/Runs, 1)

// Which activity fails most, with error text
ADFActivityRun
| where Status == "Failed"
| summarize Failures=count(), SampleError=any(ErrorMessage) by PipelineName, ActivityName
| order by Failures desc
```

4. A **log search alert** (workspace → Alerts → New rule, signal *Custom log search*) on the first query can include the **error message** in the alert. Metric alerts can't.

---

## Checkpoint – what to show

- [ ] Monitor list filtered to Failed, with the error details of one failed activity open
- [ ] Output of a successful Copy (`rowsCopied`) and the 👓 Details view
- [ ] Gantt view of PL_04 and the linked child run of PL_01
- [ ] A **Rerun from failed activity** that succeeded
- [ ] Alert rule `ALR-ADF-PipelineFailed` + action group `AG-DataTeam` created, and the alert email received

## Quick viva

1. *How long does ADF keep run history, and how do you keep more?* 45 days. Send diagnostic logs to Log Analytics or a storage account.
2. *A pipeline shows Succeeded but an activity failed. How would you get alerted?* Alert on **Failed activity runs metrics**. A pipeline-failure alert won't fire.
3. *Difference between Rerun and Rerun from failed activity?* Rerun repeats everything. Rerun from failed skips the activities that already succeeded.
4. *What is an action group?* A reusable set of notifications and actions (email, SMS, webhook, Logic App) that alert rules call.
5. *How do you catch a run that copied 0 rows?* Check `@activity('Copy').output.rowsCopied` in an If Condition and use a **Fail** activity, so the normal failure alert fires.
6. *User configuration issue vs System error?* User = fix your config or data. System = platform/transient, so retry.

## Cleanup
Delete the alert rule and action group if you're keeping the factory. They're also removed when you delete `rg-adf-lab` (File 09).
