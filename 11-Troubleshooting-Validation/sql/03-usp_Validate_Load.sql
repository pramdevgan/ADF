/* =====================================================================
   Script 03: audit.usp_Validate_Load  – the DATA QUALITY GATE
   Runs source-to-target checks, writes every result to
   audit.ValidationResults, and THROWS an error if any CRITICAL check
   fails → the ADF Stored Procedure activity fails → pipeline fails →
   alert fires.  WARNING checks are recorded but do not stop the load.
   Run this script ALONE in Query editor.
   ===================================================================== */
CREATE OR ALTER PROCEDURE audit.usp_Validate_Load
    @LoadDate   NVARCHAR(10),
    @RunId      NVARCHAR(100),
    @SourceRows INT              -- @activity('CopyToStaging').output.rowsRead
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @d DATE = CONVERT(DATE, @LoadDate, 23);

    DECLARE @stg     INT = (SELECT COUNT(*) FROM stg.Orders);
    DECLARE @fact    INT = (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d);
    DECLARE @rej     INT = (SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate = @d);
    DECLARE @factAmt DECIMAL(14,2) = (SELECT ISNULL(SUM(Amount), 0) FROM dbo.FactOrders WHERE LoadDate = @d);
    DECLARE @ctlRows INT, @ctlAmt DECIMAL(14,2);
    SELECT  @ctlRows = ExpectedRows, @ctlAmt = ExpectedTotalAmount
    FROM    audit.SourceControl WHERE LoadDate = @d;

    DECLARE @dupRows   INT = (SELECT ISNULL(SUM(c - 1), 0) FROM
                               (SELECT COUNT(*) AS c FROM dbo.FactOrders WHERE LoadDate = @d
                                GROUP BY OrderID HAVING COUNT(*) > 1) x);
    DECLARE @nullCust  INT = (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d AND CustomerID IS NULL);
    DECLARE @orphCust  INT = (SELECT COUNT(*) FROM dbo.FactOrders f
                               LEFT JOIN dim.Customer c ON c.CustomerID = f.CustomerID
                              WHERE f.LoadDate = @d AND f.CustomerID IS NOT NULL AND c.CustomerID IS NULL);
    DECLARE @orphProd  INT = (SELECT COUNT(*) FROM dbo.FactOrders f
                               LEFT JOIN dim.Product p ON p.ProductID = f.ProductID
                              WHERE f.LoadDate = @d AND (f.ProductID IS NULL OR p.ProductID IS NULL));
    DECLARE @badQty    INT = (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d AND Quantity <= 0);
    DECLARE @badStatus INT = (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d
                               AND (Status IS NULL OR Status NOT IN ('Placed','Shipped','Delivered','Cancelled')));

    DECLARE @r TABLE (CheckName NVARCHAR(50), Severity NVARCHAR(10),
                      Expected NVARCHAR(50), Actual NVARCHAR(50), Result NVARCHAR(10));

    -- ===== CRITICAL: completeness & accuracy (source ↔ staging ↔ target)
    INSERT @r VALUES ('ROWCOUNT_SOURCE_VS_STAGING', 'CRITICAL',
        CAST(@SourceRows AS NVARCHAR(50)), CAST(@stg AS NVARCHAR(50)),
        CASE WHEN @SourceRows = @stg THEN 'PASS' ELSE 'FAIL' END);

    INSERT @r VALUES ('ROWCOUNT_STAGING_VS_TARGET', 'CRITICAL',
        CAST(@stg AS NVARCHAR(50)), CAST(@fact + @rej AS NVARCHAR(50)) ,
        CASE WHEN @stg = @fact + @rej THEN 'PASS' ELSE 'FAIL' END);

    INSERT @r VALUES ('REJECTED_ROWS', 'CRITICAL', '0', CAST(@rej AS NVARCHAR(50)),
        CASE WHEN @rej = 0 THEN 'PASS' ELSE 'FAIL' END);

    IF @ctlRows IS NULL
    BEGIN
        INSERT @r VALUES ('CONTROL_ROWCOUNT',     'WARNING', 'no control record', CAST(@stg AS NVARCHAR(50)), 'SKIPPED');
        INSERT @r VALUES ('CONTROL_TOTAL_AMOUNT', 'WARNING', 'no control record', CAST(@factAmt AS NVARCHAR(50)), 'SKIPPED');
    END
    ELSE
    BEGIN
        INSERT @r VALUES ('CONTROL_ROWCOUNT', 'CRITICAL',
            CAST(@ctlRows AS NVARCHAR(50)), CAST(@stg AS NVARCHAR(50)),
            CASE WHEN @ctlRows = @stg THEN 'PASS' ELSE 'FAIL' END);
        INSERT @r VALUES ('CONTROL_TOTAL_AMOUNT', 'CRITICAL',
            CAST(@ctlAmt AS NVARCHAR(50)), CAST(@factAmt AS NVARCHAR(50)),
            CASE WHEN @ctlAmt = @factAmt THEN 'PASS' ELSE 'FAIL' END);
    END

    -- ===== WARNING: data quality (load continues, but must be reviewed)
    INSERT @r VALUES ('DUPLICATE_ORDERID',  'WARNING', '0', CAST(@dupRows   AS NVARCHAR(50)), CASE WHEN @dupRows   = 0 THEN 'PASS' ELSE 'FAIL' END);
    INSERT @r VALUES ('NULL_CUSTOMERID',    'WARNING', '0', CAST(@nullCust  AS NVARCHAR(50)), CASE WHEN @nullCust  = 0 THEN 'PASS' ELSE 'FAIL' END);
    INSERT @r VALUES ('ORPHAN_CUSTOMERID',  'WARNING', '0', CAST(@orphCust  AS NVARCHAR(50)), CASE WHEN @orphCust  = 0 THEN 'PASS' ELSE 'FAIL' END);
    INSERT @r VALUES ('ORPHAN_PRODUCTID',   'WARNING', '0', CAST(@orphProd  AS NVARCHAR(50)), CASE WHEN @orphProd  = 0 THEN 'PASS' ELSE 'FAIL' END);
    INSERT @r VALUES ('INVALID_QUANTITY',   'WARNING', '0', CAST(@badQty    AS NVARCHAR(50)), CASE WHEN @badQty    = 0 THEN 'PASS' ELSE 'FAIL' END);
    INSERT @r VALUES ('INVALID_STATUS',     'WARNING', '0', CAST(@badStatus AS NVARCHAR(50)), CASE WHEN @badStatus = 0 THEN 'PASS' ELSE 'FAIL' END);

    DELETE FROM audit.ValidationResults WHERE RunId = @RunId;
    INSERT INTO audit.ValidationResults (RunId, LoadDate, CheckName, Severity, Expected, Actual, Result)
    SELECT @RunId, @d, CheckName, Severity, Expected, Actual, Result FROM @r;

    -- ===== Gate: any CRITICAL failure → raise error → ADF activity fails
    IF EXISTS (SELECT 1 FROM @r WHERE Severity = 'CRITICAL' AND Result = 'FAIL')
    BEGIN
        DECLARE @msg NVARCHAR(2000) =
            N'DATA VALIDATION FAILED for LoadDate ' + @LoadDate + N': ' +
            (SELECT STRING_AGG(CheckName + N' (expected ' + ISNULL(Expected,'?') + N', actual ' + ISNULL(Actual,'?') + N')', N'; ')
             FROM @r WHERE Severity = 'CRITICAL' AND Result = 'FAIL');
        THROW 50001, @msg, 1;
    END;

    SELECT * FROM @r;
END
