# 04 – Hands-on Part C: Validate Source-to-Target Data (30 min)

> 🎫 **Ticket (Sev 3, 10:30):** "The 2 Oct pipeline run was **green**, but the Sales Head says revenue for 2 Oct *looks too high*. Please confirm whether the data is correct."

**The lesson of this part:** a green pipeline does **not** mean correct data. You will prove (or disprove) correctness with SQL, layer by layer.

```
SOURCE (file + control manifest)  ──►  STAGING (stg.Orders)  ──►  TARGET (dbo.FactOrders)
          audit.SourceControl              raw text                    typed, reported
                ▲                               ▲                             ▲
           Level 1: Completeness  ─ row counts at every layer ─────────────────┤
           Level 2: Accuracy      ─ sums, EXCEPT, hash ────────────────────────┤
           Level 3: Validity      ─ duplicates, NULLs, orphans, ranges, rules ─┤
           Level 4: Impact        ─ what did it do to the business number? ────┘
```

Use script **`sql/05-validation-queries.sql`**. Run **one block at a time**: select it with the mouse, then **Run**. Write each result in the worksheet table at the bottom of this file.

---

## C1. Load the 2 Oct file (3 min)

1. **Trigger now** → `p_LoadDate = 2026-10-02`.
2. Monitor → ✅ **Succeeded** (all 7 activities green).
3. Note the Run ID.
4. Don't run any other load until Part C is finished, because staging must still contain the 2 Oct file.

**Question before you start:** the pipeline passed all CRITICAL checks. Does that prove the data is right? *(Write your guess; you'll check it at the end.)*

---

## C2. Level 1 – Completeness (5 min)

### V1 – Row counts at every layer
```sql
DECLARE @d DATE = '2026-10-02';
SELECT (SELECT ExpectedRows FROM audit.SourceControl WHERE LoadDate=@d) AS Control_Rows,
       (SELECT COUNT(*) FROM stg.Orders)                                 AS Staging_Rows,
       (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate=@d)           AS Target_Rows,
       (SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate=@d)     AS Rejected_Rows;
```
✅ **22 | 22 | 22 | 0** → the rule *Control = Staging = Target + Rejected* holds. Nothing was lost.

**Concepts used:** `COUNT(*)`, scalar subqueries, a variable `@d`.

### V2 – Reconciliation across all days
Run block V2. You get one row per date in the manifest with **MATCH / MISMATCH**.
- 10-01 … 10-05 = MATCH (if you finished all incidents).
- Any date you didn't load (e.g. you skipped an incident) = MISMATCH with TargetRows 0. **That's how you detect a missing load** with SQL.

**Concepts:** `LEFT JOIN` (keeps control dates even with no target rows), `GROUP BY`, `CASE`.

---

## C3. Level 2 – Accuracy (7 min)

### V3 – Control total (sum check)
✅ **347800.00 | 347800.00 | 347800.00**. Money matches the vendor's manifest. *So far everything says "correct"…*

**Why convert in staging?** `stg.Orders.Quantity` is text, so we use `TRY_CONVERT` to do maths on it, the same way the load does.

### V4 – Column profile (min / max / sum / distinct)
✅ Both rows identical: same dates (2026-10-02), same total quantity.
👀 **Look closer:** `DistinctOrders = 20`, but there are **22 rows**. **First red flag 🚩: 2 rows share an OrderID.**

### V5 – Row-by-row comparison with EXCEPT
Run the block (staging EXCEPT target) → **0 rows**. Swap the two halves (target EXCEPT staging) → **0 rows**.
❓ *If there are duplicates, why does EXCEPT find nothing?*
→ `EXCEPT` compares **distinct** rows. Two identical copies collapse into one, so duplicates are invisible to EXCEPT. **Always pair EXCEPT with COUNT checks.**

### V5b – Hash comparison
✅ 0 rows. `HASHBYTES('SHA2_256', CONCAT_WS('|', …))` builds one fingerprint per row. That's quicker than comparing 50 columns one by one in big tables. The same limitation applies: it compares values, not how many copies exist.

**Level 2 verdict:** staging → target transformation is **accurate** (ADF and the SP didn't corrupt anything). If the data is wrong, the problem is **in the source itself**.

---

## C4. Level 3 – Validity / data quality (8 min)

### V6 – Duplicates
```sql
SELECT OrderID, COUNT(*) AS Copies, SUM(Amount) AS AmountCounted
FROM dbo.FactOrders WHERE LoadDate='2026-10-02'
GROUP BY OrderID HAVING COUNT(*) > 1;
```
✅ **50025 (2 copies, 15000.00)** and **50031 (2 copies, 6000.00)** 🚩

### V7 – NULLs in mandatory columns
✅ **50036**: CustomerID is NULL 🚩 (the order can't be attributed to a customer)

### V8 – Orphans (referential integrity)
✅ **50028 → C999** 🚩 (customer doesn't exist in `dim.Customer`)
**Pattern:** `LEFT JOIN dim … WHERE dim.key IS NULL`. Remember to exclude NULL keys (V7 handles those).

### V9 – Domain and range rules
✅ **50033** Quantity = −2 🚩 · **50039** Status = 'Shiped' 🚩 (typo; it won't appear in a "Shipped" filter on the dashboard)

### V10 – Business rule: price = list price
✅ 0 rows. Prices are fine.

### V11 – Freshness
Shows every LoadDate with load time. Is the latest expected date present? (Part B's trigger incident added today's date.)

### V13 – Compare with the automated gate
Run block **V13** from the script. It reads `audit.ValidationResults`, which the pipeline's `ValidateLoad` activity wrote for this run.
✅ All CRITICAL = **PASS**. WARNING = **FAIL** for DUPLICATE_ORDERID (2), NULL_CUSTOMERID (1), ORPHAN_CUSTOMERID (1), INVALID_QUANTITY (1), INVALID_STATUS (1).
👉 The pipeline **did** detect these, but only as WARNINGs, which nobody reviewed. That's a process gap for the RCA.

---

## C5. Level 4 – Business impact (4 min)

### V12 – How wrong is the revenue number?
```sql
SELECT SUM(Amount) AS Reported_Revenue,
       SUM(CASE WHEN rn=1 THEN Amount ELSE 0 END) AS Revenue_Without_Duplicates,
       SUM(Amount) - SUM(CASE WHEN rn=1 THEN Amount ELSE 0 END) AS Overstated_By
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY FactID) AS rn
      FROM dbo.FactOrders WHERE LoadDate='2026-10-02') x;
```
✅ **347800.00 | 337300.00 | 10500.00**. The Sales Head was right: revenue is **overstated by ₹10,500** (3.1%).

**Why didn't CONTROL_TOTAL_AMOUNT catch it?** The vendor built the manifest **from the same faulty export**, so it also counted the duplicates. *A control total only proves "we loaded what was sent", not "what was sent is correct".* 💡

**Also notice:** the −2 quantity reduces revenue by ₹5,000 (50033: −2 × 2500). Should a negative quantity be a return? Ask the business; don't "fix" it yourself.

---

## C6. Remediation (optional, 3 min)
1. Un-comment block **R1** (ROW_NUMBER delete) → run → V6 returns 0 rows → V12 shows 337300.00.
2. **Discuss:** fixing production data by hand is risky and not repeatable. The proper fix belongs in `usp_Load_Orders` (deduplicate with `ROW_NUMBER`) **plus** a request to the vendor. Re-running the pipeline after a hand fix would bring the duplicates back. Why? *(Because the SP deletes and reloads that date from staging.)*

---

## 📋 Validation worksheet (fill in and submit)

| # | Check | Level | Expected | Your result | PASS/FAIL |
|---|---|---|---|---|---|
| V1 | Control = Staging = Target + Rejected | Completeness | 22=22=22+0 | | |
| V3 | Control amount = Target amount | Accuracy | 347800.00 | | |
| V4 | Distinct OrderIDs = rows | Accuracy | 20 vs 22 | | |
| V5 | Staging EXCEPT Target (both ways) | Accuracy | 0 rows | | |
| V6 | Duplicate OrderIDs | Validity | 0 | | |
| V7 | NULL CustomerID | Validity | 0 | | |
| V8 | Orphan CustomerID | Validity | 0 | | |
| V9 | Qty ≤ 0 / invalid status | Validity | 0 | | |
| V10 | Price = list price | Validity | 0 rows | | |
| V12 | Revenue overstated by | Impact | ₹0 | | |

**Conclusion (2–3 lines):** *Is the 2 Oct data correct? What is wrong, what is the impact, and is it ADF's fault?*

> Model answer: *ADF loaded the file completely and accurately (counts and sums match at every layer). However, the **source file itself** has quality defects: 2 duplicate orders (+₹10,500), 1 order with a missing customer, 1 unknown customer C999, 1 negative quantity, and 1 misspelt status. Reported revenue is overstated by ₹10,500. Root cause is upstream (vendor export); the WARNING-level checks detected it but weren't monitored.* → write this up as **INC-006** in Part D.

➡️ Next: `05-RCA-Hands-on.md`
