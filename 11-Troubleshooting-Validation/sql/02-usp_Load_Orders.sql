/* =====================================================================
   Script 02: dbo.usp_Load_Orders
   Moves rows from stg.Orders (text) → dbo.FactOrders (typed).
   Rows that cannot be converted go to audit.RejectedOrders with a reason.
   Idempotent: deletes any previous load of the same LoadDate first.
   Run this script ALONE in Query editor (CREATE PROCEDURE must be the
   only statement in the batch).
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Load_Orders
    @LoadDate NVARCHAR(10),       -- 'yyyy-MM-dd' passed from ADF
    @RunId    NVARCHAR(100)       -- @pipeline().RunId
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @d DATE = CONVERT(DATE, @LoadDate, 23);

    -- 1. Re-runnable: remove earlier attempt for this date
    DELETE FROM dbo.FactOrders       WHERE LoadDate = @d;
    DELETE FROM audit.RejectedOrders WHERE LoadDate = @d;

    -- 2. Convert once into a temp table
    SELECT  s.OrderID, s.OrderDate, s.CustomerID, s.ProductID,
            s.Quantity, s.UnitPrice, s.Status,
            TRY_CONVERT(INT, s.OrderID)              AS c_OrderID,
            TRY_CONVERT(DATE, s.OrderDate, 23)       AS c_OrderDate,   -- style 23 = yyyy-mm-dd
            TRY_CONVERT(INT, s.Quantity)             AS c_Quantity,
            TRY_CONVERT(DECIMAL(10,2), s.UnitPrice)  AS c_UnitPrice
    INTO    #src
    FROM    stg.Orders AS s;

    -- 3. Bad rows → audit.RejectedOrders
    INSERT INTO audit.RejectedOrders
           (LoadDate, RunId, OrderID, OrderDate, CustomerID, ProductID, Quantity, UnitPrice, Status, RejectReason)
    SELECT  @d, @RunId, OrderID, OrderDate, CustomerID, ProductID, Quantity, UnitPrice, Status,
            CASE WHEN c_OrderID   IS NULL THEN 'Invalid OrderID'
                 WHEN c_OrderDate IS NULL THEN 'Invalid OrderDate (expected yyyy-MM-dd): ' + ISNULL(OrderDate,'NULL')
                 WHEN c_Quantity  IS NULL THEN 'Invalid Quantity: '  + ISNULL(Quantity,'NULL')
                 WHEN c_UnitPrice IS NULL THEN 'Invalid UnitPrice: ' + ISNULL(UnitPrice,'NULL')
            END
    FROM    #src
    WHERE   c_OrderID IS NULL OR c_OrderDate IS NULL OR c_Quantity IS NULL OR c_UnitPrice IS NULL;

    -- 4. Good rows → dbo.FactOrders
    INSERT INTO dbo.FactOrders
           (OrderID, OrderDate, CustomerID, ProductID, Quantity, UnitPrice, Status, LoadDate, RunId)
    SELECT  c_OrderID, c_OrderDate,
            NULLIF(LTRIM(RTRIM(CustomerID)), ''),
            NULLIF(LTRIM(RTRIM(ProductID)), ''),
            c_Quantity, c_UnitPrice,
            NULLIF(LTRIM(RTRIM(Status)), ''),
            @d, @RunId
    FROM    #src
    WHERE   c_OrderID IS NOT NULL AND c_OrderDate IS NOT NULL
      AND   c_Quantity IS NOT NULL AND c_UnitPrice IS NOT NULL;

    -- 5. Summary (visible when you run the SP manually)
    SELECT  @LoadDate AS LoadDate,
            (SELECT COUNT(*) FROM #src)                                           AS StagingRows,
            (SELECT COUNT(*) FROM dbo.FactOrders WHERE LoadDate = @d)             AS FactRows,
            (SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate = @d)       AS RejectedRows;
END
