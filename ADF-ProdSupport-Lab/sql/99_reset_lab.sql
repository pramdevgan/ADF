/* =====================================================================
   99_reset_lab.sql  -- wipe data (keep objects) to restart any lab cleanly
   ===================================================================== */
TRUNCATE TABLE stg.Sales;
TRUNCATE TABLE stg.Customers;
TRUNCATE TABLE dbo.FactSales;
DELETE FROM dbo.DimCustomer;
TRUNCATE TABLE rpt.DailySalesSummary;
TRUNCATE TABLE ops.PipelineRunLog;
TRUNCATE TABLE ops.HealthCheckResult;
DELETE FROM ops.IncidentWorkLog;
DELETE FROM ops.Incident;
DBCC CHECKIDENT ('ops.Incident', RESEED, 0);   -- next ticket = INC000001
PRINT 'Lab data reset.';
