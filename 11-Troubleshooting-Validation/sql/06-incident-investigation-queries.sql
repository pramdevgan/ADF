/* =====================================================================
   Script 06: INCIDENT INVESTIGATION helpers (use during Lab Part B)
   ===================================================================== */

/* ---------- I1. Which dates loaded successfully? (pipeline wrote LoadLog) */
SELECT LoadDate, Status, RowsRead, RowsCopied, FactRows, RejectedRows, RunId, LoggedAt
FROM audit.LoadLog
ORDER BY LoggedAt DESC;

/* ---------- I2. Latest validation results per date */
SELECT v.LoadDate, v.CheckName, v.Severity, v.Expected, v.Actual, v.Result, v.CheckedAt
FROM audit.ValidationResults v
WHERE v.CheckedAt = (SELECT MAX(CheckedAt) FROM audit.ValidationResults x WHERE x.LoadDate = v.LoadDate)
   OR v.RunId IN (SELECT TOP 1 RunId FROM audit.ValidationResults ORDER BY CheckedAt DESC)
ORDER BY v.LoadDate, v.Severity, v.CheckName;

/* ---------- I3. Rejected rows and WHY (data mapping / format incidents) */
SELECT LoadDate, OrderID, OrderDate, Quantity, UnitPrice, RejectReason
FROM audit.RejectedOrders
ORDER BY LoadDate, OrderID;

/* ---------- I4. What is in staging right now? (last file that landed) */
SELECT TOP 5 * FROM stg.Orders;
SELECT SourceFile, RunId, COUNT(*) AS Rows FROM stg.Orders GROUP BY SourceFile, RunId;

/* ---------- I5. Partial-load detector: data present but no success log */
SELECT f.LoadDate, COUNT(*) AS FactRows,
       CASE WHEN EXISTS (SELECT 1 FROM audit.LoadLog l WHERE l.LoadDate = f.LoadDate AND l.Status = 'Succeeded')
            THEN 'Logged OK' ELSE '⚠ NOT LOGGED – partial/failed load?' END AS LogStatus
FROM dbo.FactOrders f
GROUP BY f.LoadDate
ORDER BY f.LoadDate;

/* ---------- I6. Trace one ADF run end-to-end (paste RunId from Monitor) */
DECLARE @run NVARCHAR(100) = '<paste-run-id-here>';
SELECT 'staging'    AS Layer, COUNT(*) AS Rows FROM stg.Orders             WHERE RunId = @run
UNION ALL SELECT 'fact',       COUNT(*) FROM dbo.FactOrders                 WHERE RunId = @run
UNION ALL SELECT 'rejected',   COUNT(*) FROM audit.RejectedOrders           WHERE RunId = @run
UNION ALL SELECT 'validation', COUNT(*) FROM audit.ValidationResults        WHERE RunId = @run
UNION ALL SELECT 'loadlog',    COUNT(*) FROM audit.LoadLog                  WHERE RunId = @run;
