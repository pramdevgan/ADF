/* =====================================================================
   04_health_checks.sql
   ops.usp_RunHealthChecks  -- the "doctor's check-up" for the data platform.
   Called by ADF pipeline PL_HealthCheck (Lookup activity) every hour and
   manually by support engineers. Returns ONE row: FailCount, WarnCount, CheckRunId.
   Every FAIL also raises/updates an incident (Source = 'HealthCheck').

   Checks
   HC01 Freshness        : FactSales has rows for RunDate
   HC02 Duplicates       : no OrderId repeated for RunDate
   HC03 Reconciliation   : FactSales rows = rows copied by last successful PL_Ingest_Sales run
   HC04 Referential      : every sale has a customer in DimCustomer (orphans)
   HC05 Report integrity : rpt revenue = FactSales revenue for RunDate
   HC06 Failed runs 24h  : (WARN) any failed pipeline in ops log in last 24h
   HC07 SLA breach       : (WARN) open P1/P2 tickets older than ResolveWithinHrs
   HC08 Customer feed    : (WARN) DimCustomer updated in last 26 hours
   ===================================================================== */
CREATE OR ALTER PROCEDURE ops.usp_RunHealthChecks
    @RunDate char(8)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CheckRunId uniqueidentifier = NEWID();
    DECLARE @d date = CONVERT(date, @RunDate, 112);
    DECLARE @n bigint, @m bigint, @x decimal(18,2), @y decimal(18,2);

    DECLARE @r TABLE (CheckId varchar(10), CheckName varchar(200), Status varchar(4), Detail nvarchar(1000));

    -- HC01 Freshness
    SELECT @n = COUNT(*) FROM dbo.FactSales WHERE LoadDate = @RunDate;
    INSERT @r VALUES ('HC01','Sales data present for business date',
        IIF(@n > 0,'PASS','FAIL'), CONCAT('FactSales rows for ', @RunDate, ' = ', @n));

    -- HC02 Duplicates
    SELECT @m = COUNT(*) FROM (SELECT OrderId FROM dbo.FactSales WHERE LoadDate=@RunDate
                               GROUP BY OrderId HAVING COUNT(*) > 1) z;
    INSERT @r VALUES ('HC02','No duplicate OrderId in FactSales',
        IIF(@m = 0,'PASS','FAIL'), CONCAT(@m, ' duplicated OrderId value(s)'));

    -- HC03 Reconciliation source vs target
    SET @m = NULL;   -- SELECT @var = ... keeps the OLD value when no row matches!
    SELECT TOP (1) @m = RowsWritten FROM ops.PipelineRunLog
    WHERE PipelineName = 'PL_Ingest_Sales' AND RunDate = @RunDate AND Status = 'Succeeded'
    ORDER BY EndUtc DESC;
    INSERT @r VALUES ('HC03','Rows loaded = rows copied by last successful ingest',
        CASE WHEN @m IS NULL THEN 'FAIL' WHEN @m = @n THEN 'PASS' ELSE 'FAIL' END,
        CONCAT('Copied=', ISNULL(CAST(@m AS varchar(20)),'no successful run'), ' | InFact=', @n));

    -- HC04 Orphan customers
    SELECT @m = COUNT(*), @x = ISNULL(SUM(f.Amount),0)
    FROM dbo.FactSales f LEFT JOIN dbo.DimCustomer c ON c.CustomerId = f.CustomerId
    WHERE f.LoadDate = @RunDate AND c.CustomerId IS NULL;
    INSERT @r VALUES ('HC04','Every sale maps to a known customer',
        IIF(@m = 0,'PASS','FAIL'),
        CONCAT(@m, ' orphan sale row(s), amount ', @x, '. Missing ids: ',
               ISNULL((SELECT STRING_AGG(CustomerId, ',') FROM (SELECT DISTINCT f.CustomerId
                        FROM dbo.FactSales f LEFT JOIN dbo.DimCustomer c ON c.CustomerId=f.CustomerId
                        WHERE f.LoadDate=@RunDate AND c.CustomerId IS NULL) q), '-')));

    -- HC05 Report integrity
    SELECT @x = ISNULL(SUM(Revenue),0) FROM rpt.DailySalesSummary WHERE ReportDate = @d;
    SELECT @y = ISNULL(SUM(Amount),0)  FROM dbo.FactSales        WHERE LoadDate   = @RunDate;
    INSERT @r VALUES ('HC05','Report revenue = fact revenue',
        IIF(@x = @y AND @y > 0,'PASS','FAIL'), CONCAT('Report=', @x, ' | Fact=', @y));

    -- HC06 Failed runs (warning only - incidents already exist for them)
    SELECT @m = COUNT(*) FROM ops.PipelineRunLog
    WHERE Status = 'Failed' AND StartUtc >= DATEADD(HOUR,-24,SYSUTCDATETIME());
    INSERT @r VALUES ('HC06','Failed pipeline runs in last 24h',
        IIF(@m = 0,'PASS','WARN'), CONCAT(@m, ' failed run(s)'));

    -- HC07 SLA breach on open high-severity tickets
    SELECT @m = COUNT(*) FROM ops.Incident i JOIN ops.EscalationMatrix e ON e.Severity = i.Severity
    WHERE i.Status NOT IN ('Resolved','Closed') AND i.Severity IN ('P1','P2')
      AND DATEDIFF(MINUTE, i.CreatedUtc, SYSUTCDATETIME()) > e.ResolveWithinHrs * 60;
    INSERT @r VALUES ('HC07','No open P1/P2 ticket breaching resolve SLA',
        IIF(@m = 0,'PASS','WARN'), CONCAT(@m, ' ticket(s) in breach'));

    -- HC08 Customer feed freshness
    SELECT @m = COUNT(*) FROM dbo.DimCustomer WHERE UpdatedAtUtc >= DATEADD(HOUR,-26,SYSUTCDATETIME());
    SELECT @n = COUNT(*) FROM dbo.DimCustomer;
    INSERT @r VALUES ('HC08','Customer dimension refreshed recently',
        IIF(@n > 0 AND @m > 0,'PASS','WARN'), CONCAT(@m, ' of ', @n, ' customers touched in last 26h (MERGE only touches changed rows - WARN is informational)'));

    -- persist
    INSERT ops.HealthCheckResult (CheckRunId, RunDate, CheckId, CheckName, Status, Detail)
    SELECT @CheckRunId, @RunDate, CheckId, CheckName, Status, Detail FROM @r;

    -- raise incidents for FAILs (deduped by pipeline+check id)
    DECLARE @cid varchar(10), @cname varchar(200), @det nvarchar(1000), @title nvarchar(200);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT CheckId, CheckName, Detail FROM @r WHERE Status = 'FAIL';
    OPEN c; FETCH NEXT FROM c INTO @cid, @cname, @det;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @title = CONCAT('Health check ', @cid, ' failed for ', @RunDate, ': ', @cname);
        EXEC ops.usp_RaiseIncident @PipelineName='PL_HealthCheck', @RunId=NULL, @ErrorCode=@cid,
             @ErrorMessage=@det, @Source='HealthCheck', @Title=@title, @Category='Data Quality';
        FETCH NEXT FROM c INTO @cid, @cname, @det;
    END
    CLOSE c; DEALLOCATE c;

    -- single-row result for the ADF Lookup activity
    SELECT SUM(IIF(Status='FAIL',1,0)) AS FailCount,
           SUM(IIF(Status='WARN',1,0)) AS WarnCount,
           CAST(@CheckRunId AS varchar(36)) AS CheckRunId
    FROM @r;
END
GO

/* Convenience view: latest health-check result per check */
CREATE OR ALTER VIEW ops.vw_LatestHealth AS
SELECT h.*
FROM ops.HealthCheckResult h
WHERE h.CheckRunId = (SELECT TOP (1) CheckRunId FROM ops.HealthCheckResult ORDER BY ResultId DESC);
GO
PRINT 'Health check procedure created.';
