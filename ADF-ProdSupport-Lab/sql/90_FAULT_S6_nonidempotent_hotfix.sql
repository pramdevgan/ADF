/* =====================================================================
   90_FAULT_S6_nonidempotent_hotfix.sql      *** FAULT INJECTION ***
   Story: a developer pushed a "quick hotfix" to dbo.usp_Load_Sales at night
   to "make it faster" and removed the DELETE step. No review, no change ticket.
   Effect: every rerun APPENDS the same rows again -> revenue doubles.
   The pipeline stays GREEN. Only the health check (HC02/HC03/HC05) catches it.
   Restore with 91_FIX_S6_restore_idempotent_load.sql
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Load_Sales
    @RunDate char(8),
    @RunId   varchar(64)
AS
BEGIN
    SET NOCOUNT ON;
    -- "hotfix": validations and delete removed for speed  (BAD!)
    INSERT dbo.FactSales (OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, LoadDate, PipelineRunId)
    SELECT OrderId, OrderDate, CustomerId, ProductId, Quantity, UnitPrice, Amount, StoreCode, @RunDate, @RunId
    FROM stg.Sales;
END
GO
PRINT 'FAULT S6 injected: dbo.usp_Load_Sales is now NON-idempotent.';
