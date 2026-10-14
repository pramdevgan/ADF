/* =====================================================================
   Script 07: RESET – clear loaded data but keep tables, SPs, masters,
   control records. Use to repeat the lab from Part A3.
   ===================================================================== */
TRUNCATE TABLE stg.Orders;
TRUNCATE TABLE dbo.FactOrders;
TRUNCATE TABLE audit.RejectedOrders;
TRUNCATE TABLE audit.ValidationResults;
TRUNCATE TABLE audit.LoadLog;
SELECT 'reset done' AS Info;
