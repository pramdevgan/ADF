# 05 – Hands-on Part D: Prepare RCA Reports (19 min)

**Goal:** turn your investigation evidence into professional Root Cause Analysis reports that a manager, auditor, or the vendor can read.

**Files you need (folder `rca-templates/`):**

| File | Use |
|---|---|
| `Incident-Register.csv` | The log you filled during Part B (one row per incident) |
| `RCA-Template.md` | Blank template: copy it once per report |
| `RCA-Example-INC-001.md` | Fully worked example (missing file). Read this first |

| Step | Time |
|---|---|
| D1. Read the worked example | 3 min |
| D2. Complete the Incident Register | 3 min |
| D3. Write a full RCA for **INC-005b** (assigned) | 9 min |
| D4. Write a short RCA for **INC-006** (2 Oct data quality) | 3 min |
| D5. Peer review with the checklist | 1 min |

---

## D1. Read the worked example (3 min)
Open `RCA-Example-INC-001.md`. Notice:
- The **summary** fits in 3 lines and is readable by a non-technical manager.
- The **timeline** uses exact times (from Monitor + Activity log).
- **5 Whys** stops at a *process* cause, not "the file name was wrong".
- Every **CAPA** action has an **owner** and a **due date**, and is either *corrective* (fix this one) or *preventive* (stop it happening again).
- Blameless language: "the export tool changed", not "the vendor's developer messed up".

## D2. Complete the Incident Register (3 min)
Make sure `Incident-Register.csv` has one complete row for each of INC-001 … INC-005b, plus INC-006 from Part C. Columns:

`IncidentID, Date, DetectedAt, ResolvedAt, Severity, Category, Pipeline, RunId, FailedActivity, ErrorCode, ErrorMessage, ImmediateCause, RootCause, Fix, PreventiveAction, Owner`

Then calculate for the class: **MTTR** = average (ResolvedAt − DetectedAt).

## D3. Full RCA for INC-005b – data format errors (9 min)
Copy `RCA-Template.md` → `RCA-INC-005b.md` and fill **every** section. Your evidence:

| Evidence | Where you got it |
|---|---|
| Error text `DATA VALIDATION FAILED … REJECTED_ROWS (expected 0, actual 6) …` | Monitor → ValidateLoad → Error |
| 6 rejected rows + reasons | `audit.RejectedOrders` (query I3) |
| 10 rows visible in FactOrders before fix (₹5,65,400 vs ₹7,84,400) | Query I5 + control table |
| 4 of 6 bad rows = late September orders in dd/MM/yyyy | Rejected rows' OrderDate |
| Fixed by vendor re-send + rerun → 16 rows, ₹7,84,400 | LoadLog + FactOrders |

**Hints for 5 Whys:** Why partial numbers? → Why were rows rejected? → Why different formats? → Why didn't we catch it before publishing? → Why is there no contract?
**Expect two root causes:** (1) the source has no format contract; (2) the pipeline design publishes before validating.

## D4. Short RCA for INC-006 – "green but wrong" (3 min)
Only these sections: Summary · Impact (₹10,500 overstated) · Root cause · 3 CAPA actions.
Hint: *why didn't the control total catch it?*

## D5. Peer review checklist (1 min)
Swap with your neighbour and tick:
- [ ] Summary understandable without technical knowledge
- [ ] Impact is **quantified** (rows, ₹, hours, which report)
- [ ] Timeline has detection, response, and resolution times
- [ ] Root cause is a **process/design** cause, not only the symptom
- [ ] Evidence is cited (Run ID, error code, query result)
- [ ] Each action has owner + due date + type (corrective/preventive)
- [ ] Blameless wording

---

## Model answer – INC-005b (instructor key; don't open before D3)

<details>
<summary>Click to expand</summary>

**Summary:** On 5 Oct the daily orders load failed its data-quality gate because 6 of 16 rows in the vendor file had invalid formats. 10 valid rows had already been written to the reporting table, so the Finance dashboard showed ₹5,65,400 instead of ₹7,84,400 until the vendor re-sent the file.

**Severity:** Sev 1 (financial reporting wrong). **Duration:** ~45 min.

**Impact:** 6 orders (₹2,19,000) missing from the 5 Oct revenue for ~45 min; Finance dashboard understated by 27.9%. No data loss after the fix.

**5 Whys:**
1. Why was revenue understated? → Only 10 of 16 orders were in FactOrders.
2. Why only 10? → 6 rows failed conversion (4 dates in dd/MM/yyyy, 1 Quantity 'N/A', 1 price '12,000.00').
3. Why did the vendor send these formats? → Their system formats back-dated (late) orders and some numeric fields differently; there's no agreed format spec.
4. Why did partial data reach the dashboard? → `usp_Load_Orders` writes to the fact table **before** `usp_Validate_Load` runs.
5. Why was this design accepted? → Validation was added as a final step, without reviewing what happens to already-loaded data when it fails.

**Root causes:** (a) no data contract with the vendor; (b) the pipeline publishes before validating.

**CAPA:**

| # | Action | Type | Owner | Due |
|---|---|---|---|---|
| 1 | Re-load 5 Oct with corrected file | Corrective | On-call DE | Done |
| 2 | Agree a data contract (ISO dates, plain numbers, no 'N/A') with the vendor | Preventive | Data Product Owner | +2 weeks |
| 3 | Run critical checks on **staging before** LoadFact; load fact in a transaction | Preventive | DE team | +1 week |
| 4 | Show rejected-row details in the failure alert and send them to the vendor automatically | Detective | DE team | +1 week |

</details>
