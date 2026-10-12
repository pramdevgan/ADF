# 07 – Understand Pipeline Execution Flow, Triggers & Monitoring (≈ 30 min)

## Part A – Theory: how a pipeline run executes

### A1. Lifecycle of a run

```
Trigger fires / Debug / Trigger now
        │
        ▼
 Pipeline run created  (RunId = new GUID, parameters resolved)   Status: Queued
        │
        ▼
 Activities with NO dependencies start (in parallel)              Status: In progress
        │
        ▼
 Each finishing activity → dependency conditions evaluated →
 downstream activities start / are Skipped
        │
        ▼
 All activities finished → pipeline status computed              Succeeded / Failed / Cancelled
```

- Activities **without** an arrow between them run **in parallel**.
- An arrow = **dependency**; the downstream activity waits for the upstream one.
- Copy/Data Flow activities run on an **Integration Runtime**; control activities (If, ForEach, Set Variable, Wait) run inside the ADF orchestration engine.

### A2. Dependency conditions (the 4 arrow colours)

| Condition | Arrow | Downstream runs when upstream… |
|---|---|---|
| **Upon Success** | 🟩 green | Succeeded |
| **Upon Failure** | 🟥 red | Failed |
| **Upon Completion** | 🟦 blue | Finished – succeeded *or* failed |
| **Upon Skip** | ⬜ grey | Was Skipped (didn't run) |

If the condition is not met, the downstream activity is marked **Skipped** (and its own downstream chain is evaluated accordingly).

**Multiple incoming arrows = AND.** Activity C with arrows from A (success) and B (success) runs only when **both** succeed.

### A3. How ADF decides the final pipeline status

Microsoft's rule:
1. Look at all **leaf** activities (activities with nothing after them).
2. If a leaf was **Skipped**, evaluate its **parent** instead.
3. Pipeline = **Succeeded** only if **all** evaluated nodes succeeded; otherwise **Failed**.

| Pattern | Design | Copy fails, handler succeeds → Pipeline |
|---|---|---|
| **Try-Catch** | Copy →(failure)→ Handler | ✅ **Succeeded** (leaf = Handler, succeeded) |
| **Do-If-Else** | Copy →(success)→ A, Copy →(failure)→ B | ❌ **Failed** (A skipped → its parent Copy failed) |
| **Do-If-Skip-Else** | Copy →(success)→ A →(skip)→ B, Copy →(failure)→ B | ✅ Succeeded |
| **Generic error handling** | Copy →(success)→ A, Copy →(failure)→ B, A →(completion)→ C | depends on C – use **Fail** activity to force failure |

> That's why in Pipeline 3 (Do-If-Else) the pipeline showed **Failed** even though `LogFailure` succeeded. This is intentional: alerts still fire.

### A4. Activity run statuses
`Queued` → `InProgress` → `Succeeded` | `Failed` | `Skipped` | `Cancelled` (pipeline also has `Cancelling`).

---

## Part B – Lab: `PL_04_Execution_Flow_Demo` (≈ 15 min)

Demonstrates: Set Variable, Wait, Execute Pipeline, If Condition, Fail, and all dependency types.

```
[SetVar_Start] ─✔─► [Wait_5s] ─✔─► [Run_PL01 (Execute Pipeline)] ─✔─► [If_ForceFail]
                                                                       │ True → [Fail_Intentional]
                                                                       │ False→ [SetVar_AllGood]
                                       [If_ForceFail] ─✖ failure─► [SetVar_Handled]
                                       [If_ForceFail] ─● completion─► [Wait_Final_1s]
```

### Step 1 – Pipeline, parameter, variable
1. New pipeline `PL_04_Execution_Flow_Demo`.
2. **Parameters**: `p_ForceFail` – Type **Bool** – Default `false`.
3. **Variables** tab (click empty canvas): `v_Status` – String – default `NotStarted`.

### Step 2 – `SetVar_Start`
General → **Set variable**. Settings: Variable type **Pipeline variable**, Name `v_Status`, Value `Started at @{utcnow()}`.
*Why:* variables hold state during a run; you can read them in later activities.

### Step 3 – `Wait_5s`
General → **Wait** → Wait time `5` seconds. Connect from `SetVar_Start` (Success).
*Why:* simulates delay / staggering; useful for polling patterns. Watch the Gantt view later – you'll see the 5 s gap.

### Step 4 – `Run_PL01`
General → **Execute Pipeline**. Connect from `Wait_5s` (Success).

| Field | Value | Meaning |
|---|---|---|
| Invoked pipeline | `PL_01_Copy_Employees` | Child pipeline (must be published for triggered runs) |
| Wait on completion | ✅ | Parent waits for child to finish and inherits its success/failure. Unchecked = fire-and-forget |

*Why:* modular design – a **master/orchestrator** pipeline calling child pipelines.

### Step 5 – `If_ForceFail`
Iteration & conditionals → **If Condition**. Connect from `Run_PL01` (Success).
- Expression: `@pipeline().parameters.p_ForceFail`
- **True** activities (✏️) → add General → **Fail** activity `Fail_Intentional`:
  - Fail message: `Forced failure for demo, run @{pipeline().RunId}`
  - Error code: `500`
  *Why Fail activity:* deliberately fail a pipeline with a custom message (e.g. validation failed, 0 rows found).
- **False** activities (✏️) → **Set variable** `SetVar_AllGood`, `v_Status` = `All good`.

> Note: Set Variable cannot set the *same* variable in parallel branches safely; here only one branch runs.

### Step 6 – Error and completion handlers (main canvas)
1. `SetVar_Handled` (Set variable, `v_Status` = `Handled failure: @{activity('If_ForceFail').error.message}`) – connect from `If_ForceFail` with **Upon Failure** (hover If → click **+** → *Upon Failure*).
2. `Wait_Final_1s` (Wait 1 s) – connect from `If_ForceFail` with **Upon Completion**.

### Step 7 – Run both scenarios

| Run | p_ForceFail | Expected activity statuses | Expected pipeline status |
|---|---|---|---|
| Debug #1 | `false` | If ✅, SetVar_AllGood ✅, SetVar_Handled **Skipped**, Wait_Final ✅ | **Succeeded** |
| Debug #2 | `true` | Fail_Intentional ❌, If ❌, SetVar_Handled ✅, Wait_Final ✅ | **Succeeded** (Try-Catch: leaves succeeded) |

After each run, open the **Output** of the Set variable activities to read `v_Status`, and check the nested child run of PL_01 (Monitor shows it as a separate pipeline run linked to the parent).

**Experiment:** delete the Upon Failure arrow and `SetVar_Handled`, rerun with `true` → pipeline **Failed**. Now you've seen the status rules in action.

Publish all.

---

## Part C – Triggers (≈ 8 min)

**Manage → Author → Triggers → + New** (or in a pipeline: Add trigger → New/Edit).

| Trigger type | Fires when | Typical use |
|---|---|---|
| **Schedule** | Wall-clock schedule (every N min/hours/days, specific times) | Nightly loads |
| **Tumbling window** | Fixed-size, non-overlapping, contiguous windows; supports backfill, retry, dependencies; 1 trigger ↔ 1 pipeline | Time-sliced incremental loads (`@trigger().outputs.windowStartTime`) |
| **Storage event** | Blob created/deleted in a container (uses Event Grid) | Process a file as soon as it lands |
| **Custom event** | Custom Event Grid topic event | App-driven processing |

### C1. Schedule trigger
1. New trigger: Name `TR_Every15Min`, Type **Schedule**, Start date = now, Time zone **(UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi**, Recurrence **Every 15 Minute(s)**, End **No end**, Activated **Yes** → OK.
2. Open `PL_01_Copy_Employees` → Add trigger → New/Edit → choose `TR_Every15Min` → OK → **Publish all** (triggers only start after publishing).
3. Monitor → **Trigger runs** shows each firing; Pipeline runs shows `Triggered by: TR_Every15Min`.
4. ⚠️ After observing one run: Manage → Triggers → **Stop** (deactivate) the trigger → Publish. Otherwise it keeps running.

### C2. Storage event trigger (optional)
1. Subscription → **Resource providers** → register **Microsoft.EventGrid** (one-time; required).
2. New trigger `TR_NewSalesFile`, Type **Storage events**, storage account `stadflab<initials>`, Container `input`, **Blob path begins with** `sales/`, **Blob path ends with** `.csv`, Event **Blob created**, Ignore empty blobs **Yes**.
3. Attach to `PL_02_Copy_All_Sales_Files`; parameter values can use `@triggerBody().fileName` / `@triggerBody().folderPath`.
4. Publish → upload any CSV to `input/sales/` → a run starts within seconds. Stop the trigger afterwards.

---

## Part D – Monitor hub deep-dive (≈ 7 min)

| Area | What you see / do |
|---|---|
| **Pipeline runs → Triggered / Debug** | All runs; filter by time range, status, pipeline name, annotations, run ID |
| Run → **Activity runs** list | Each activity's status, duration, Input/Output/Details, error message |
| **Gantt** view (toggle List/Gantt) | Visual timeline – shows parallelism and waits |
| **Rerun** | Rerun the whole pipeline with same parameters |
| **Rerun from failed activity** | Restarts only from the failed activity onward – successful earlier steps are not repeated |
| **Cancel** | Stop an in-progress run (recursive cancel available) |
| **Consumption** (📊 icon on a run) | Activity runs, DIU-hours, pipeline orchestration units – basis of billing |
| **Trigger runs** | Each trigger firing and which pipelines it started |
| **Integration runtimes** | Status, region, CPU/memory of IRs |
| **Alerts & metrics** | Create alert rules, e.g. *Failed pipeline runs metrics > 0* → email action group |

**Run-ID trail:** every run has a RunId; child pipelines (Execute Pipeline) get their own RunId and show the parent; the `PipelineRunLog` table from Pipeline 3 stores it – that's how you trace a run end-to-end.

**Retention:** run history is kept 45 days. For longer, configure **Diagnostic settings** on the factory (Azure portal → Data factory → Monitoring → Diagnostic settings) to send PipelineRuns/ActivityRuns/TriggerRuns to a Log Analytics workspace and query with KQL:
```kusto
ADFPipelineRun
| where Status == "Failed"
| project TimeGenerated, PipelineName, RunId, FailureType
```

✅ **Checkpoint:** you can explain why a pipeline ended Succeeded vs Failed by looking at leaf activities, and you have seen a schedule trigger fire.

Reference JSON: `pipeline-json/pipeline_PL_04_Execution_Flow_Demo.json`, `pipeline-json/trigger_TR_Every15Min.json`
