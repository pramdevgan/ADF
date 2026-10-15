# Module 1 — Theory (40 min, Hinglish)
## Production Support Readiness for Azure Data Factory

> **Ek hi example poore session me chalega — "RetailMart ka 9 AM CFO Report"**
>
> RetailMart ek retail company hai. Har raat **02:00 AM IST** pe ADF ka pipeline `PL_Master_Daily` chalta hai:
> 1. Vendor ki **customers** file ADLS me aati hai → `DimCustomer` me load hoti hai
> 2. POS system ki **sales** file aati hai → `FactSales` me load hoti hai
> 3. Dono join karke `rpt.DailySalesSummary` banta hai → **CFO 9:00 AM pe Power BI dashboard dekhta hai**
>
> Ek din 02:07 AM pe pipeline fail ho jata hai. Ab kya hoga? Kaun dekhega? Kaise pata chalega? Kitni der me theek karna hai? Kisko batana hai? Yahi poora session hai.

---

### Time plan (40 min)

| Min | Topic |
|---|---|
| 0–5 | Production support kya hai, L1/L2/L3 model |
| 5–15 | Incident Management Process (ITIL lifecycle, severity, SLA) |
| 15–23 | Ticket Documentation & Escalation |
| 23–30 | Runbooks & SOPs |
| 30–37 | Health Checks & Recovery Procedures (ADF-specific) |
| 37–40 | Recap + lab briefing |

---

## 1. Production Support kya hai? (0–5 min)

Development me hum **build** karte hain. Production support me hum **run** karte hain — matlab jo system live hai, use **available, correct aur on-time** rakhna.

Data platform ke liye 3 cheezein sabse important:

| Pillar | Matlab | RetailMart example |
|---|---|---|
| **Availability** | Pipeline chala ya nahi | 02:00 ka run trigger hua? |
| **Timeliness (SLA)** | Time pe data aaya ya nahi | 9:00 AM se pehle report ready? |
| **Correctness (Data Quality)** | Data sahi hai ya nahi | Revenue double to nahi ho gaya? |

> 💡 **Sabse khatarnak incident wo hai jo "green" dikhta hai.** Pipeline Succeeded hai lekin data galat hai — CFO galat number pe decision le lega. Isliye hum sirf "failed alert" pe depend nahi karte, **health checks** bhi lagate hain.

### Support tiers (L1 / L2 / L3)

| Tier | Kaun | Kya karta hai | RetailMart me |
|---|---|---|---|
| **L1** – Monitoring / Ops | DataOps on-call | Alert dekhna, ticket banana, runbook follow karna, simple rerun | 02:10 pe alert aaya → ticket INC banaya → runbook step 1–4 |
| **L2** – Data Engineering | Pipeline owners | Root cause dhoondhna, data fix, code/config fix | Copy activity ka mapping/data issue analyse |
| **L3** – Platform / Vendor | Cloud team, Microsoft Support, source vendor | Infra, network, product bug, upstream system | Vendor ko sahi file bhejna, Azure outage |

**Functional escalation** = problem ko zyada skilled team ko dena (L1 → L2 → L3).
**Hierarchical escalation** = management ko inform karna (Support Manager → Delivery Head) jab impact bada ho ya SLA breach ho raha ho.

---

## 2. Incident Management Process (5–15 min)

### 2.1 Incident vs Problem vs Change (ITIL terms)

| Term | Definition | Goal | RetailMart example |
|---|---|---|---|
| **Incident** | Service me unplanned interruption ya degradation | **Jaldi service restore** karo | Aaj ka report nahi bana |
| **Problem** | Ek ya zyada incidents ka **underlying cause** | Cause **permanently** hatao | Har Monday vendor file late aati hai |
| **Change** | Production me planned modification | Risk control karke change | Copy mapping me naya column add karna (CHG ticket) |
| **Service Request** | Normal request, kuch tuta nahi | Fulfil karo | "Mujhe pipeline ka read access chahiye" |

> Incident me **pehle aag bujhao (restore)**, phir Problem me **aag kyun lagi (root cause)** dhoondo. L1 ka kaam root cause nahi, **restore + accurate documentation** hai.

### 2.2 Incident Lifecycle

```
 Detect ─► Log ─► Categorise & Prioritise ─► Diagnose ─► Escalate? ─► Resolve ─► Recover/Validate ─► Close ─► Post-Incident Review
   ▲                                                                                                                   │
   └──────────────────────────────── learnings → runbook / alert / code improvements ◄─────────────────────────────────┘
```

| Stage | Kya karte hain | ADF me kaise | Lab me |
|---|---|---|---|
| **Detect** | Pata chalna ki kuch galat hai | Azure Monitor metric alert (`PipelineFailedRuns`), log alert, health-check pipeline, user complaint | Lab 2 |
| **Log** | Ticket banana — har incident ka record | Humne `ops.usp_RaiseIncident` se **auto-ticket** banaya | Lab 4 |
| **Categorise/Prioritise** | Category + Severity (Impact × Urgency) | Category: Data Pipeline / Data Quality / Access / Platform | Lab 4 |
| **Diagnose** | Kya fail hua, kyun | ADF Monitor → pipeline run → activity → Error JSON; Log Analytics KQL | Lab 3, 5 |
| **Escalate** | Agar L1 resolve nahi kar sakta ya SLA risk | Escalation matrix | Lab 4, 5 |
| **Resolve** | Workaround ya fix | File fix, RBAC fix, secret fix | Lab 3 |
| **Recover/Validate** | Data ko sahi state me lana + verify | Rerun / Rerun from failed activity / backfill + health check | Lab 3, 5 |
| **Close** | Root cause + resolution ke saath close | `Resolved → Closed` (RootCause mandatory) | Lab 4 |
| **PIR / RCA** | Seekh lena | 5-Whys, CAPA | Lab 5 |

### 2.3 Severity / Priority — Impact × Urgency

| | **Urgency High** (SLA abhi breach hoga) | **Urgency Medium** | **Urgency Low** |
|---|---|---|---|
| **Impact High** (CFO report, regulatory) | **P1** | P2 | P3 |
| **Impact Medium** (ek team affected) | P2 | P3 | P3 |
| **Impact Low** (dev/test, cosmetic) | P3 | P4 | P4 |

Lab ka escalation matrix (`ops.EscalationMatrix`):

| Sev | Ack within | Resolve within | Update every | Example |
|---|---|---|---|---|
| P1 | 15 min | 4 h | 30 min | Report + regulatory feed dono down, koi workaround nahi |
| P2 | 30 min | 8 h | 60 min | Master pipeline fail, 9 AM report at risk |
| P3 | 2 h | 24 h | 4 h | Ek child pipeline fail, retry se theek ho sakta hai |
| P4 | 8 h | 72 h | daily | Warning, cosmetic |

> **RetailMart example:** 02:07 AM pe `PL_Master_Daily` fail. CFO report 9 AM pe chahiye → **Impact High**, abhi 7 ghante baaki → **Urgency Medium** → **P2**. Agar 08:30 tak fix nahi hua → urgency High → **upgrade to P1** aur management ko inform (hierarchical escalation).

### 2.4 Key metrics (KPIs)

| KPI | Formula | Kyun important |
|---|---|---|
| **MTTD** – Mean Time To Detect | failure time → alert time | Monitoring kitna accha hai |
| **MTTA** – Mean Time To Acknowledge | ticket created → acknowledged | On-call kitna responsive hai |
| **MTTR** – Mean Time To Resolve/Restore | ticket created → resolved | Runbooks kitne effective hain |
| **SLA compliance %** | resolved within SLA / total | Business ko promise |
| **Repeat incidents** | same error code dobara | Problem management ki zarurat |

Lab 4 me `sql/60_incident_kpi_reports.sql` yahi sab calculate karta hai.

---

## 3. Ticket Documentation & Escalation (15–23 min)

### 3.1 Accha ticket kaisa hota hai?

**Golden rule:** Ticket aisa likho ki **raat 3 baje naya engineer bina call kiye** samajh jaye ki kya hua, kya kiya gaya, aur aage kya karna hai.

❌ **Bad ticket**
> "Pipeline failed. Rerun kiya. Ab theek hai."

✅ **Good ticket**
> **Title:** PL_Master_Daily failed for 20261015 – Copy_Customers_To_Stg column 'customer_id' not found
> **Severity:** P2 (CFO 9 AM report at risk) **Category:** Data Pipeline / Source data
> **Detected:** 02:09 IST via Azure Monitor alert `alert-adf-pipeline-failed`
> **Impact:** `rpt.DailySalesSummary` for 15-Oct not built. Customers & Sales not loaded.
> **Evidence:** Master RunId `8c1f…`, child RunId `a42d…`, activity `Copy_Customers_To_Stg`, error text (copy-paste, not screenshot only)
> **Diagnosis:** Source file header changed `customer_id` → `cust_id`. No ADF change in Activity Log in last 48 h. Upstream change.
> **Actions:** 02:25 informed vendor (email ref V-123); 02:40 escalated to L2 Data Eng; 04:10 corrected file received; 04:15 rerun from failed activity; 04:22 health check PASS.
> **Resolution:** Corrected file reprocessed. Report available 04:25 IST.
> **Root cause:** Vendor deployed new export version without notice (no data contract).
> **Follow-up:** PRB raised – add schema validation step + data contract with vendor.

### 3.2 Ticket ke mandatory fields

| Field | Kyun |
|---|---|
| Title (what + where + when) | Search / dedupe ke liye |
| Severity + justification | Galat severity = galat log jaagte hain ya koi nahi jaagta |
| Affected service / pipeline / business date | Scope clear |
| Detection source & time | MTTD |
| Run IDs (pipeline + activity) | ADF me seedha drill-down |
| Exact error code + message (text) | Search, KB match, Microsoft support |
| Business impact | Prioritisation, comms |
| Timeline / work notes (time-stamped) | Handover, audit, RCA |
| Workaround / resolution | Knowledge base |
| Root cause + CAPA link | Problem management |

### 3.3 Escalation — kab aur kaise

Escalate **karo** jab:
1. Runbook ke steps khatam ho gaye, issue abhi bhi hai
2. Fix ke liye access/skill nahi hai (code change, RBAC, vendor)
3. **SLA ka 50% time** nikal gaya aur resolution clear nahi (time-based escalation)
4. Severity badh gayi (P2 → P1)
5. Security/data-leak ka shak — turant

Escalation message format (**SBAR**):
- **S**ituation – "PL_Master_Daily failed, report at risk (P2)"
- **B**ackground – "Fail at Copy_Customers_To_Stg since 02:07, rerun once failed same error"
- **A**ssessment – "Source header changed; ADF config unchanged"
- **R**equest – "Need L2 to confirm approach / vendor contact by 05:00"

> ⚠️ Escalation **ticket me log** karo (EntryType = Escalation). Phone pe bola, ticket me nahi likha = hua hi nahi.

---

## 4. Runbooks & SOPs (23–30 min)

| | **SOP** (Standard Operating Procedure) | **Runbook** |
|---|---|---|
| Scope | Generic, repeatable **task** | Specific **system/alert** ke liye |
| Example | "How to rerun an ADF pipeline", "How to rotate a Key Vault secret" | "Runbook: PL_Master_Daily failure" |
| Trigger | Planned / on-demand | Alert / incident |
| Style | Step-by-step instructions | Decision tree: *if error X → do Y* |

**Accha runbook = decision tree + copy-paste commands + verification + escalation point.**

RetailMart runbook snippet:
```
Alert: PL_Master_Daily failed
1. ADF Monitor → Pipeline runs → open failed master run → note RunId
2. Which child failed? (Execute Pipeline activity → output → child RunId)
3. Open child → failed activity → Error
   ├─ "PathNotFound / does not exist"       → Source file missing → SOP-03 Late file
   ├─ "AuthorizationPermissionMismatch/403" → Access → escalate L3 Platform (P2)
   ├─ "Login failed for user"               → Secret/credential → SOP-05 Credential
   ├─ "DQ_..." business error               → Data quality → inform data owner
   └─ anything else                         → escalate L2 with evidence
4. After fix → SOP-01 Rerun → SOP-02 Health check → update ticket
```

Is package me ready-made: `templates/Runbook_PL_Master_Daily.md` aur `templates/SOP_*.md`.

---

## 5. Health Checks & Recovery Procedures (30–37 min)

### 5.1 Health checks — reactive nahi, proactive

| Type | Kya check | ADF/Azure me kaise | Lab |
|---|---|---|---|
| **Platform** | ADF, IR, SQL, Storage up? | Azure Service Health, Resource Health, IR status in Monitor | Lab 2 |
| **Execution** | Pipelines failed? trigger chala? | ADF Monitor, metric alert, KQL K1/K8 | Lab 2 |
| **Timeliness / Freshness** | Data time pe aaya? | KQL K7 (no success in 26h), HC01 | Lab 3-S7 |
| **Data quality / Reconciliation** | Rows match? duplicates? orphans? | `ops.usp_RunHealthChecks` HC02–HC05 | Lab 3-S6, Lab 5 |
| **Performance** | Run normal se slow? | KQL K6 (mean + 2σ) | Lab 2 |

> **RetailMart lesson:** Ek din trigger kisi ne stop kar diya (deployment ke time). Koi pipeline **fail nahi hua** → koi alert nahi → 9 AM CFO ne bola "report purana hai". Isliye **freshness check** zaroori hai — "kuch fail hua?" ke saath "kuch chala bhi?" bhi poochho.

### 5.2 ADF recovery options — kab kaunsa

| Option | Kahan | Kya karta hai | Kab use |
|---|---|---|---|
| **Rerun** | Monitor → Pipeline runs → ↻ | Poora pipeline same parameters ke saath **naye RunId** se | Failure shuru me hua, ya idempotent pipeline |
| **Rerun from failed activity** | Monitor → run → "Rerun from failed activity" | Succeeded activities skip, failed se aage | Lambi pipeline, pehle steps expensive |
| **Rerun from activity** | Run detail → activity select → "Rerun from activity" | Chosen activity se aage | Data fix ke baad specific step se |
| **Trigger now (new params)** | Author → pipeline → Add trigger → Trigger now | Naya run, parameters change kar sakte | **Backfill** purani date |
| **Cancel** | Monitor → run → Cancel | Hung/long run rokna | Run atka hua, ya galat data load ho raha |
| **Retry policy** | Activity → General → Retry | Transient errors pe auto retry | Network blip, SQL failover |
| **Code rollback** | Git (ADF Studio → Git) revert + republish | Bad deployment wapas | Change ke baad failures |
| **Data restore** | Azure SQL Point-in-time restore | DB ko pehle ke time pe | Data corruption, galat delete |

> 🔑 **Idempotency** = same run 2 baar chalao, result same. Hamare `usp_Load_Sales` me `DELETE WHERE LoadDate = @RunDate` + `INSERT` hai, isliye rerun safe hai. Lab S6 me hum dikhayenge ki agar idempotency tooti to **rerun hi incident bana deta hai** (revenue double).

> ⚠️ **ADF gotcha — "Upon Failure" path:** Agar kisi activity ka failure, ek "On failure" activity handle kar le aur woh succeed ho jaye, to **pipeline status Succeeded** dikh sakta hai (try-catch pattern). Matlab alert nahi aayega! Isliye hamare pipelines me logging ke baad **Fail activity** hai jo pipeline ko deliberately Failed mark karti hai.

---

## 6. Recap (37–40 min)

1. **Detect** fast (alerts + health checks), **log** everything (auto-ticket), **restore** first, **root-cause** later.
2. Severity = Impact × Urgency; SLA clock ticket banne se chalti hai.
3. Ticket = evidence + timeline + resolution + root cause. Screenshot nahi, **text** + RunId.
4. Runbook = decision tree; SOP = repeatable task.
5. Green ≠ correct. Freshness + reconciliation checks lagao.
6. Rerun tabhi safe jab pipeline idempotent ho.

**Ab hands-on:** Hum RetailMart ka poora mini-production Azure me banayenge, use todenge (7 scenarios), tickets track karenge, aur last me ek end-to-end investigation karenge. 👉 `02_Lab_Environment_Setup.md`

---

### Quick check (2 min, verbal)
1. Pipeline Succeeded hai par report me revenue double hai — ye incident hai? Severity? *(Haan, Data Quality, P2/P1 depending on time)*
2. "Rerun from failed activity" kab **unsafe** hai? *(Jab pehle wale steps ne partial/non-idempotent data likha ho)*
3. Trigger stop hone pe `PipelineFailedRuns` alert aayega? *(Nahi — freshness check chahiye)*
