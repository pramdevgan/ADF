# Lab 5 — End-to-End Failure Investigation Exercise ("The 16-October Morning")
⏱ ~45 min  |  Individually or in pairs, **timed**. Deliverables: a closed ticket + an RCA document.

## The story
> **Friday 16-Oct-2026, 02:00 IST.** `PL_Master_Daily` should load business date **20261015**.
> You are the on-call engineer. At **02:09** your phone buzzes: *Azure Monitor alert — PL_Master_Daily failed.*
> The CFO opens the dashboard at **09:00**. A new store opened on 15-Oct and onboarded new loyalty customers.
>
> You have the ADF factory, Azure Portal, Query editor, Log Analytics, and this package. **Find out what happened, restore the report, prove it's correct, and write the RCA.**

The investigation unfolds in **3 stages** — the instructor releases each stage's "vendor" files only after you ask the right question (just like real life).

---

## Instructor setup (learners: don't read the files beforehand)
```
bash scripts/10_fault_injection.sh E2E stage1
```
or upload via Portal: `data/e2e/sales_20261015.csv` → `landing/sales/sales_20261015.csv`; `data/e2e/customers_20261015.csv` → `landing/customers/customers_20261015.csv`.
Then **Trigger now** `PL_Master_Daily` pRunDate `20261015` (simulates the 02:00 schedule). Start the clock ⏱.

---

## Stage 1 — "The pipeline failed"

### 1.1 Respond (target: ticket acknowledged within 5 min)
- [ ] Alert email received — note the time (MTTD).
- [ ] Find the tickets: there should be a **P2** for `PL_Master_Daily` (ERR_MASTER) and a **P3** for a child.
- [ ] Acknowledge the P2, link the child (`@ParentIncident`), assign to yourself.
- [ ] Set expectations: post a first **Communication** entry ("investigating, next update in 60 min").

### 1.2 Investigate — answer these in your worksheet (§ Worksheet)
| # | Question | Where to look |
|---|---|---|
| Q1 | Which master RunId failed and at what time? | ADF Monitor → Pipeline runs |
| Q2 | Which activity in the master failed or was skipped? | Master run → activity list |
| Q3 | Which **child** pipeline failed? Child RunId? | Execute Pipeline activity → Output / Error; or Monitor filter by pipeline; KQL K9 |
| Q4 | Which activity in the child failed, exact error text? | Child run → failed activity → Error |
| Q5 | Did `PL_Ingest_Sales` run? Why / why not? | master activity list (Skipped?) |
| Q6 | Did anyone change ADF in the last 48 h? | Data factory → **Activity log** (operations like *Create or Update Pipeline/Linked service*) / KQL K11 |
| Q7 | What's different about the file vs. yesterday's file? | Storage → landing/customers → open both files, compare **header row** |
| Q8 | Classify: Data / Code / Access / Credential / Platform / **Upstream**? | your reasoning |

### 1.3 Decide
You have two options. Write in the ticket which one you choose **and why**:
- **A.** Edit the Copy mapping (`cust_id → CustomerId`) in production and rerun.
- **B.** Contact the vendor, request a file in the agreed format, keep the pipeline unchanged.

> 💬 Discussion point: A is a **production code change** at 03:00 without review/test (needs an emergency change, and will break again tomorrow when the vendor reverts — or silently accept wrong data). B respects the **data contract**. In real life you might choose A *as an approved emergency change* if the SLA can't be met otherwise. For this exercise, choose **B** and ask the instructor ("vendor") for a resend.

---

## Stage 2 — "Green… but is it right?"

**Instructor ("vendor") resends:** `bash scripts/10_fault_injection.sh E2E stage2` (uploads `data/e2e/customers_20261015_resend1.csv` as `customers_20261015.csv`).

### 2.1 Recover
- [ ] Choose a rerun type for the **failed master run** and justify it (Rerun vs Rerun from failed activity).
  - Hint: the master failed at `Exec_Ingest_Customers`; everything after was skipped. What does "from failed activity" restart? Is the child idempotent? (yes: TRUNCATE staging + MERGE / DELETE-INSERT)
- [ ] Monitor → master run → your rerun choice → observe: a **new master RunId** and new child runs.
- [ ] All green? Record the new RunIds in the ticket.

### 2.2 Validate — don't trust green
- [ ] Trigger now `PL_HealthCheck` pRunDate `20261015`.
- [ ] Q9: Which check(s) fail? What is the detail text? → (`ops.vw_LatestHealth`)
- [ ] Q10: How many sale rows and how much revenue is affected? Which customer IDs? → run:
  ```sql
  SELECT f.CustomerId, COUNT(*) Rows_, SUM(f.Amount) Amount
  FROM dbo.FactSales f LEFT JOIN dbo.DimCustomer c ON c.CustomerId=f.CustomerId
  WHERE f.LoadDate='20261015' AND c.CustomerId IS NULL GROUP BY f.CustomerId;
  SELECT Segment, City, Orders, Revenue FROM rpt.DailySalesSummary WHERE ReportDate='2026-10-15' ORDER BY Revenue DESC;
  ```
- [ ] Q11: What would the CFO see on the dashboard right now?
- [ ] Q12: Is the original ticket resolved? (No! The service is "up" but **wrong**.) Keep it **InProgress**, link the new health-check ticket(s) to it, update severity reasoning, send a Communication update.
- [ ] Ask the "vendor" the right question (hint: the new store… new customers…).

---

## Stage 3 — "Complete and correct"

**Instructor ("vendor") sends the complete file:** `bash scripts/10_fault_injection.sh E2E stage3` (uploads `data/corrected/customers_20261015.csv`, 22 customers).

### 3.1 Recover
- [ ] Which pipeline(s) must run now? (Customers must load the 2 new customers; the **report** must be rebuilt. Does FactSales need reloading?) → simplest auditable action: **Trigger now `PL_Master_Daily` 20261015** (idempotent end-to-end).
- [ ] Run `PL_HealthCheck` 20261015 → **0 FAIL**.

### 3.2 Prove it
| Evidence | Expected (see `data/EXPECTED_VALUES.md`) | Yours |
|---|---|---|
| FactSales rows 20261015 | 60 | |
| FactSales revenue | 186667.30 | |
| DimCustomer rows | 22 | |
| Orphan rows (HC04) | 0 | |
| Report revenue = fact revenue (HC05) | PASS | |
| 'Unknown' segment in report | none | |

### 3.3 Close out
- [ ] Resolve all linked tickets with resolution text; close with root cause.
- [ ] Final Communication: "Report for 15-Oct available at hh:mm IST, validated."
- [ ] Stop the clock ⏱ — record **MTTA** and **MTTR** (`sql/60` R1).
- [ ] Write the RCA in `templates/RCA_PIR_Template.md` (≤ 1 page) — include a timeline, **5 Whys**, and at least **3 CAPA** items (one *detect earlier*, one *prevent*, one *process*).

---

## Worksheet

| Q | Answer |
|---|---|
| Q1 Master RunId / time | |
| Q2 Failed/skipped master activities | |
| Q3 Child pipeline + RunId | |
| Q4 Child failed activity + error text | |
| Q5 Did sales load run? why | |
| Q6 ADF changes in 48 h? | |
| Q7 File difference | |
| Q8 Classification | |
| Option chosen (A/B) + reason | |
| Rerun type chosen (stage 2) + reason | |
| Q9 Failing health checks | |
| Q10 Affected rows/amount/customers | |
| Q11 What CFO would see | |
| Q12 Ticket status decision | |
| Final evidence table | |
| MTTA / MTTR | |

## Scoring (instructor)

| Area | Points |
|---|---|
| Ticket acknowledged < 5 min, linked parent/child | 10 |
| Correct child + activity + error identified with RunIds | 15 |
| "What changed" checked (Activity log + file diff) | 10 |
| Correct decision A vs B with justification | 10 |
| Did **not** close after stage 2 green run; health check used | 20 |
| Correct recovery + evidence table | 15 |
| Communication updates logged | 5 |
| RCA with timeline, 5 Whys, 3 CAPA | 15 |
| **Total** | **100** |

Answer key for instructors: `10_Instructor_Guide_and_Answer_Key.md`.
