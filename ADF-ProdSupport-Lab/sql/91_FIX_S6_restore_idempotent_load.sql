/* =====================================================================
   91_FIX_S6_restore_idempotent_load.sql
   Recovery for Scenario S6 (duplicate data after rerun)
   Step 1  evidence  -> Step 2 restore code -> Step 3 repair data -> Step 4 verify
   ===================================================================== */

-- STEP 1 : capture evidence BEFORE fixing (paste result into the ticket work log)
SELECT LoadDate, COUNT(*) AS Rows, COUNT(DISTINCT OrderId) AS DistinctOrders,
       SUM(Amount) AS Revenue, COUNT(DISTINCT PipelineRunId) AS RunsThatWrote
FROM dbo.FactSales
WHERE LoadDate = '20261014'
GROUP BY LoadDate;

-- Who changed the procedure and when? (object modify date)
SELECT name, create_date, modify_date FROM sys.procedures WHERE name = 'usp_Load_Sales';
GO

-- STEP 2 : restore the reviewed, idempotent version (same as 03_business_load_procs.sql)
CREATE OR ALTER PROCEDURE dbo.usp_Load_Sales
    @RunDate char(8),
    @RunId   varchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @cnt int, @msg nvarchar(400);

    SELECT @cnt = COUNT(*) FROM stg.Sales;
    IF @cnt = 0
        THROW 50001, 'DQ_EMPTY_FILE: stg.Sales has 0 rows. Source file was empty (header only?). Load aborted.', 1;

    SELECT @cnt = COUNT(*) FROM (SELECT OrderId FROM stg.Sales GROUP BY OrderId HAVING COUNT(*) > 1) d;
    IF @cnt > 0
    BEGIN
        SET @msg = CONCAT('DQ_DUPLICATE_KEYS: ', @cnt, ' OrderId value(s) appear more than once in source file. Load aborted.');
        THROW 50002, @msg, 1;
    END

    SELECT @cnt = COUNT(*) FROM stg.Sales WHERE Amount < 0 OR Quantity <= 0;
    IF @cnt > 0
    BEGIN
        SET @msg = CONCAT('DQ_NEGATIVE_VALUES: ', @cnt, ' row(s) with Amount<0 or Quantity<=0. Load aborted.');
        THROW 50003, @msg, 1;
    END

    SELECT @cnt = COUNT(*) FROM stg.Sales WHERE CONVERT(char(8), OrderDate, 112) <> @RunDate;
    IF @cnt > 0
    BEGIN
        SET @msg = CONCAT('DQ_WRONG_BUSINESS_DATE: ', @cnt, ' row(s) have OrderDate different from RunDate ', @RunDate, '. Wrong file?');
        THROW 50004, @msg, 1;
    END

    BEGIN TRAN;
        DELETE FROM dbo.FactSales WHERE LoadDate = @RunDate;
        INSERT dbo.FactSales (OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, LoadDate, PipelineRunId)
        SELECT OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, @RunDate, @RunId
        FROM stg.Sales;
    COMMIT;
END
GO

-- STEP 3 : repair data
--   Preferred: simply rerun PL_Master_Daily (or PL_Ingest_Sales + report) for 20261014
--   from ADF Monitor. Because the load is idempotent again, the rerun DELETEs the
--   duplicated rows and inserts one clean copy.  (Do NOT hand-delete rows in prod
--   unless the runbook says so - a rerun is auditable & repeatable.)

-- STEP 4 : verify after the rerun
--   EXEC ops.usp_RunHealthChecks @RunDate = '20261014';   -- HC02, HC03, HC05 must be PASS
