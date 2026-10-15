/* =====================================================================
   03_business_load_procs.sql
   Load procedures called by ADF after the Copy activity has filled stg.*
   Design principles taught in this lab:
     1. VALIDATE before you load (fail fast with a clear business error code)
     2. IDEMPOTENT  (delete-then-insert per LoadDate inside one transaction)
        -> any rerun / "Rerun from failed activity" is SAFE
     3. LINEAGE     (PipelineRunId stamped on every row)
   ===================================================================== */

CREATE OR ALTER PROCEDURE dbo.usp_Load_Sales
    @RunDate char(8),
    @RunId   varchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;      -- any runtime error rolls back the whole transaction

    DECLARE @cnt int, @msg nvarchar(400);

    /* ---- Data-quality gates (business errors 5000x) ---- */
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

    /* ---- Idempotent load ---- */
    BEGIN TRAN;
        DELETE FROM dbo.FactSales WHERE LoadDate = @RunDate;

        INSERT dbo.FactSales (OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, LoadDate, PipelineRunId)
        SELECT OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, @RunDate, @RunId
        FROM stg.Sales;
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Customers
    @RunId varchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM stg.Customers)
        THROW 50011, 'DQ_EMPTY_FILE: stg.Customers has 0 rows. Load aborted.', 1;

    IF EXISTS (SELECT CustomerId FROM stg.Customers GROUP BY CustomerId HAVING COUNT(*) > 1)
        THROW 50012, 'DQ_DUPLICATE_KEYS: duplicate CustomerId in customer file. Load aborted.', 1;

    -- SCD Type 1 upsert : naturally idempotent
    MERGE dbo.DimCustomer AS t
    USING stg.Customers AS s ON t.CustomerId = s.CustomerId
    WHEN MATCHED AND (ISNULL(t.CustomerName,'') <> ISNULL(s.CustomerName,'')
                   OR ISNULL(t.City,'')         <> ISNULL(s.City,'')
                   OR ISNULL(t.Segment,'')      <> ISNULL(s.Segment,''))
        THEN UPDATE SET CustomerName = s.CustomerName, City = s.City, Segment = s.Segment,
                        SignupDate = s.SignupDate, UpdatedAtUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET
        THEN INSERT (CustomerId, CustomerName, City, Segment, SignupDate)
             VALUES (s.CustomerId, s.CustomerName, s.City, s.Segment, s.SignupDate);
    -- (no delete: customers are never removed by a daily snapshot in this design)
END
GO

/* Report layer: what the CFO dashboard reads */
CREATE OR ALTER PROCEDURE rpt.usp_Build_DailySalesSummary
    @RunDate char(8),
    @RunId   varchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @d date = CONVERT(date, @RunDate, 112);

    BEGIN TRAN;
        DELETE FROM rpt.DailySalesSummary WHERE ReportDate = @d;

        -- LEFT JOIN on purpose: unknown customers do not drop revenue, they show as 'Unknown'
        -- (and health check HC04 flags them).  This is how "green pipeline, wrong report" happens.
        INSERT rpt.DailySalesSummary (ReportDate, Segment, City, Orders, Revenue, PipelineRunId)
        SELECT @d,
               COALESCE(c.Segment, 'Unknown'),
               COALESCE(c.City, N'Unknown'),
               COUNT(*), SUM(f.Amount), @RunId
        FROM dbo.FactSales f
        LEFT JOIN dbo.DimCustomer c ON c.CustomerId = f.CustomerId
        WHERE f.LoadDate = @RunDate
        GROUP BY COALESCE(c.Segment, 'Unknown'), COALESCE(c.City, N'Unknown');
    COMMIT;
END
GO
PRINT 'Business load procedures created.';
