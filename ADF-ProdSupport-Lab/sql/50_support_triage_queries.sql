/* =====================================================================
   50_support_triage_queries.sql
   L1/L2 "first 10 minutes" query pack. Run section by section.
   ===================================================================== */

-- Q1. What ran recently and how did it end? (our own log - independent of ADF Monitor)
SELECT TOP (30) LogId, PipelineName, RunDate, Status, StartUtc, EndUtc, DurationSec,
       RowsRead, RowsWritten, FailedActivity, ErrorCode, LEFT(ErrorMessage, 300) AS ErrorMessage, RunId
FROM ops.PipelineRunLog
ORDER BY LogId DESC;

-- Q2. Runs still "InProgress" for > 30 min  (hung run / log never closed = blind spot!)
SELECT * FROM ops.PipelineRunLog
WHERE Status = 'InProgress' AND StartUtc < DATEADD(MINUTE,-30,SYSUTCDATETIME());

-- Q3. Open tickets, worst first
SELECT i.IncidentNumber, i.Severity, i.Status, i.Title, i.PipelineName, i.ErrorCode,
       i.OccurrenceCount, i.AssignmentGroup, i.AssignedTo,
       DATEDIFF(MINUTE, i.CreatedUtc, SYSUTCDATETIME()) AS AgeMins,
       e.AckWithinMins, e.ResolveWithinHrs,
       CASE WHEN i.AcknowledgedUtc IS NULL AND DATEDIFF(MINUTE,i.CreatedUtc,SYSUTCDATETIME()) > e.AckWithinMins
            THEN 'ACK SLA BREACHED' ELSE '' END AS AckFlag
FROM ops.Incident i JOIN ops.EscalationMatrix e ON e.Severity = i.Severity
WHERE i.Status NOT IN ('Resolved','Closed')
ORDER BY i.Severity, i.CreatedUtc;

-- Q4. Full ticket with timeline
-- EXEC ops.usp_GetIncident @IncidentNumber = 'INC000001';

-- Q5. Data state for a business date
DECLARE @RunDate char(8) = '20261014';
SELECT 'stg.Sales' AS obj, COUNT(*) AS rows_, NULL AS amount FROM stg.Sales
UNION ALL SELECT 'FactSales', COUNT(*), SUM(Amount) FROM dbo.FactSales WHERE LoadDate=@RunDate
UNION ALL SELECT 'DailySalesSummary', SUM(Orders), SUM(Revenue) FROM rpt.DailySalesSummary WHERE ReportDate=CONVERT(date,@RunDate,112)
UNION ALL SELECT 'DimCustomer', COUNT(*), NULL FROM dbo.DimCustomer;

-- Q6. Which ADF run wrote the current data? (lineage)
SELECT PipelineRunId, COUNT(*) AS Rows, MIN(LoadedAtUtc) AS FirstLoaded, MAX(LoadedAtUtc) AS LastLoaded
FROM dbo.FactSales WHERE LoadDate = '20261014' GROUP BY PipelineRunId;

-- Q7. Latest health check
SELECT CheckId, CheckName, Status, Detail, CheckedAtUtc FROM ops.vw_LatestHealth ORDER BY CheckId;

-- Q8. Run the health check now
-- EXEC ops.usp_RunHealthChecks @RunDate = '20261014';

-- Q9. Recently modified code in the DB (did someone change something? "What changed?" is question #1)
SELECT SCHEMA_NAME(schema_id) AS sch, name, type_desc, modify_date
FROM sys.objects WHERE type IN ('P','V','U','FN','TF') AND modify_date > DATEADD(DAY,-2,SYSUTCDATETIME())
ORDER BY modify_date DESC;

-- Q10. Sessions currently running / blocked (performance incidents)
SELECT r.session_id, r.status, r.command, r.wait_type, r.blocking_session_id, r.total_elapsed_time/1000 AS elapsed_s,
       s.login_name, SUBSTRING(t.text,1,200) AS sql_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID;
