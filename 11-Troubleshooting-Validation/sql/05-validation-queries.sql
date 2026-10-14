/* =====================================================================
   Script 05: SOURCE-TO-TARGET VALIDATION – hands-on queries (Lab Part C)
   Run AFTER PL_20_Daily_Orders_Load has run for LoadDate = 2026-10-02
   (staging must still contain the 2026-10-02 file).
   Run each block one at a time (select the block → Run).
   Expected answers are in comments  →  -- ✅ expect: ...
   ===================================================================== */

/* ---------- V0. Warm-up: what tables do I have? */
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN ('stg','dim','dbo','audit')
ORDER BY TABLE_SCHEMA, TABLE_NAME;

/* =====================================================================
   LEVEL 1 – COMPLETENESS  (did every row arrive?)
   ===================================================================== */

/* ---------- V1. Row count: source (control) vs staging vs target vs rejected */
DECLARE @d DATE = '2026-10-02';
SELECT
    (SELECT ExpectedRows FROM audit.SourceControl WHERE LoadDate = @d) AS Control_Rows,
    (SELECT COUNT(*) FROM stg.Orders)                                  AS Staging_Rows,
    (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d)          AS Target_Rows,
    (SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate = @d)    AS Rejected_Rows;
-- ✅ expect: 22 | 22 | 22 | 0
-- Rule: Control = Staging = Target + Rejected

/* ---------- V2. Row count per day for ALL loads (reconciliation report) */
SELECT  sc.LoadDate, sc.FileName, sc.ExpectedRows,
        COUNT(f.FactID)                                   AS TargetRows,
        (SELECT COUNT(*) FROM audit.RejectedOrders r WHERE r.LoadDate = sc.LoadDate) AS RejectedRows,
        CASE WHEN sc.ExpectedRows = COUNT(f.FactID)
                  + (SELECT COUNT(*) FROM audit.RejectedOrders r WHERE r.LoadDate = sc.LoadDate)
             THEN 'MATCH' ELSE 'MISMATCH' END             AS RowCountStatus
FROM    audit.SourceControl sc
LEFT JOIN dbo.FactOrders f ON f.LoadDate = sc.LoadDate
GROUP BY sc.LoadDate, sc.FileName, sc.ExpectedRows
ORDER BY sc.LoadDate;
-- Days not loaded yet show TargetRows = 0 → MISMATCH (a "missing load")

/* =====================================================================
   LEVEL 2 – ACCURACY  (are the values the same?)
   ===================================================================== */

/* ---------- V3. Control total (sum check) */
DECLARE @d3 DATE = '2026-10-02';
SELECT
    (SELECT ExpectedTotalAmount FROM audit.SourceControl WHERE LoadDate = @d3)  AS Control_Amount,
    (SELECT SUM(TRY_CONVERT(INT,Quantity) * TRY_CONVERT(DECIMAL(10,2),UnitPrice))
       FROM stg.Orders)                                                         AS Staging_Amount,
    (SELECT SUM(Amount) FROM dbo.FactOrders WHERE LoadDate = @d3)               AS Target_Amount;
-- ✅ expect: 347800.00 | 347800.00 | 347800.00   → all three match

/* ---------- V4. Column-level aggregates (min/max/sum per column) */
SELECT 'staging' AS Layer,
       COUNT(DISTINCT OrderID) AS DistinctOrders,
       MIN(TRY_CONVERT(DATE,OrderDate,23)) AS MinDate, MAX(TRY_CONVERT(DATE,OrderDate,23)) AS MaxDate,
       SUM(TRY_CONVERT(INT,Quantity)) AS TotalQty
FROM stg.Orders
UNION ALL
SELECT 'target', COUNT(DISTINCT OrderID), MIN(OrderDate), MAX(OrderDate), SUM(Quantity)
FROM dbo.FactOrders WHERE LoadDate = '2026-10-02';
-- ✅ expect both rows identical; DistinctOrders = 20 (but 22 rows! → duplicates)

/* ---------- V5. Row-by-row comparison with EXCEPT (both directions) */
-- Rows in staging that are NOT in target
SELECT TRY_CONVERT(INT,OrderID) AS OrderID, TRY_CONVERT(DATE,OrderDate,23) AS OrderDate,
       NULLIF(LTRIM(RTRIM(CustomerID)),'') AS CustomerID, ProductID,
       TRY_CONVERT(INT,Quantity) AS Quantity, TRY_CONVERT(DECIMAL(10,2),UnitPrice) AS UnitPrice, Status
FROM stg.Orders
EXCEPT
SELECT OrderID, OrderDate, CustomerID, ProductID, Quantity, UnitPrice, Status
FROM dbo.FactOrders WHERE LoadDate = '2026-10-02';
-- ✅ expect: 0 rows
-- Now swap the two halves (target EXCEPT staging) → ✅ expect: 0 rows
-- ⚠️ Lesson: EXCEPT works on DISTINCT rows – it CANNOT see duplicates.
--    That is why row counts (V1) and duplicate checks (V6) are also needed.

/* ---------- V5b. Hash comparison (fast for wide/large tables) */
WITH s AS (
    SELECT TRY_CONVERT(INT,OrderID) AS OrderID,
           HASHBYTES('SHA2_256', CONCAT_WS('|', OrderID, OrderDate, NULLIF(LTRIM(RTRIM(CustomerID)),''),
                     ProductID, Quantity, TRY_CONVERT(DECIMAL(10,2),UnitPrice), Status)) AS h
    FROM stg.Orders),
t AS (
    SELECT OrderID,
           HASHBYTES('SHA2_256', CONCAT_WS('|', OrderID, CONVERT(CHAR(10),OrderDate,23), CustomerID,
                     ProductID, Quantity, UnitPrice, Status)) AS h
    FROM dbo.FactOrders WHERE LoadDate = '2026-10-02')
SELECT COALESCE(s.OrderID, t.OrderID) AS OrderID,
       CASE WHEN s.h IS NULL THEN 'Only in target'
            WHEN t.h IS NULL THEN 'Only in source'
            ELSE 'Values differ' END AS Issue
FROM (SELECT DISTINCT * FROM s) s
FULL OUTER JOIN (SELECT DISTINCT * FROM t) t ON s.OrderID = t.OrderID
WHERE s.h IS NULL OR t.h IS NULL OR s.h <> t.h;
-- ✅ expect: 0 rows

/* =====================================================================
   LEVEL 3 – VALIDITY / QUALITY  (is the data correct for the business?)
   ===================================================================== */

/* ---------- V6. Duplicates (uniqueness) */
SELECT OrderID, COUNT(*) AS Copies, SUM(Amount) AS AmountCounted
FROM dbo.FactOrders WHERE LoadDate = '2026-10-02'
GROUP BY OrderID
HAVING COUNT(*) > 1;
-- ✅ expect: 50025 (2 copies, 15000.00) and 50031 (2 copies, 6000.00)

/* ---------- V7. NULL check on mandatory columns */
SELECT OrderID, CustomerID, ProductID, Status
FROM dbo.FactOrders
WHERE LoadDate = '2026-10-02'
  AND (CustomerID IS NULL OR ProductID IS NULL OR Status IS NULL);
-- ✅ expect: 1 row → 50036 (CustomerID NULL)

/* ---------- V8. Referential integrity (orphans) with LEFT JOIN */
SELECT f.OrderID, f.CustomerID
FROM dbo.FactOrders f
LEFT JOIN dim.Customer c ON c.CustomerID = f.CustomerID
WHERE f.LoadDate = '2026-10-02'
  AND f.CustomerID IS NOT NULL
  AND c.CustomerID IS NULL;
-- ✅ expect: 1 row → 50028, C999

/* ---------- V9. Domain / range checks */
SELECT OrderID, Quantity, Status,
       CASE WHEN Quantity <= 0 THEN 'Quantity must be > 0'
            WHEN Status NOT IN ('Placed','Shipped','Delivered','Cancelled') THEN 'Unknown status'
       END AS Problem
FROM dbo.FactOrders
WHERE LoadDate = '2026-10-02'
  AND (Quantity <= 0 OR Status NOT IN ('Placed','Shipped','Delivered','Cancelled'));
-- ✅ expect: 50033 (Quantity -2) and 50039 (Status 'Shiped')

/* ---------- V10. Business rule: price must match product list price */
SELECT f.OrderID, f.ProductID, f.UnitPrice, p.ListPrice
FROM dbo.FactOrders f
JOIN dim.Product p ON p.ProductID = f.ProductID
WHERE f.LoadDate = '2026-10-02' AND f.UnitPrice <> p.ListPrice;
-- ✅ expect: 0 rows

/* ---------- V11. Freshness / timeliness */
SELECT LoadDate, MIN(LoadedAt) AS FirstLoadedUtc, MAX(LoadedAt) AS LastLoadedUtc, COUNT(*) AS Rows
FROM dbo.FactOrders GROUP BY LoadDate ORDER BY LoadDate;
-- Is yesterday's date present? If not → missing/late load.

/* =====================================================================
   LEVEL 4 – IMPACT ANALYSIS  (for the RCA report)
   ===================================================================== */

/* ---------- V12. What did the bad data do to the business number? */
SELECT
    SUM(Amount)                                                    AS Reported_Revenue,
    SUM(CASE WHEN rn = 1 THEN Amount ELSE 0 END)                   AS Revenue_Without_Duplicates,
    SUM(Amount) - SUM(CASE WHEN rn = 1 THEN Amount ELSE 0 END)     AS Overstated_By
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY FactID) AS rn
      FROM dbo.FactOrders WHERE LoadDate = '2026-10-02') x;
-- ✅ expect: 347800.00 | 337300.00 | 10500.00

/* ---------- V13. Automated results written by the pipeline */
SELECT CheckName, Severity, Expected, Actual, Result
FROM audit.ValidationResults
WHERE LoadDate = '2026-10-02'
  AND RunId = (SELECT TOP 1 RunId FROM audit.ValidationResults WHERE LoadDate = '2026-10-02' ORDER BY CheckedAt DESC)
ORDER BY Severity, CheckName;
-- ✅ expect: all CRITICAL = PASS; WARNING FAIL for DUPLICATE_ORDERID(2), NULL_CUSTOMERID(1),
--            ORPHAN_CUSTOMERID(1), INVALID_QUANTITY(1), INVALID_STATUS(1)

/* =====================================================================
   OPTIONAL – REMEDIATION (fix the data, then re-validate)
   ===================================================================== */

/* ---------- R1. Remove duplicate copies, keep the first one */
-- WITH d AS (SELECT FactID, ROW_NUMBER() OVER (PARTITION BY OrderID ORDER BY FactID) AS rn
--            FROM dbo.FactOrders WHERE LoadDate = '2026-10-02')
-- DELETE FROM d WHERE rn > 1;
-- Then re-run V6 → 0 rows.  (In production: fix in usp_Load_Orders, not by hand.)
