/* =====================================================================
   60_incident_kpi_reports.sql   --  "Resolution tracking" reports
   KPIs every support manager asks for:
     MTTA  = Mean Time To Acknowledge   (CreatedUtc -> AcknowledgedUtc)
     MTTR  = Mean Time To Resolve       (CreatedUtc -> ResolvedUtc)
     SLA % = tickets resolved within ResolveWithinHrs
     Repeat rate, Top error codes, Backlog ageing
   ===================================================================== */

-- R1. KPI by severity
SELECT i.Severity,
       COUNT(*)                                                                  AS Tickets,
       SUM(IIF(i.Status IN ('Resolved','Closed'),1,0))                           AS ResolvedOrClosed,
       AVG(DATEDIFF(MINUTE, i.CreatedUtc, i.AcknowledgedUtc) * 1.0)              AS MTTA_Mins,
       AVG(DATEDIFF(MINUTE, i.CreatedUtc, i.ResolvedUtc) * 1.0)                  AS MTTR_Mins,
       100.0 * SUM(IIF(i.ResolvedUtc IS NOT NULL
                       AND DATEDIFF(MINUTE,i.CreatedUtc,i.ResolvedUtc) <= e.ResolveWithinHrs*60,1,0))
             / NULLIF(SUM(IIF(i.ResolvedUtc IS NOT NULL,1,0)),0)                 AS ResolveSLA_Pct
FROM ops.Incident i JOIN ops.EscalationMatrix e ON e.Severity = i.Severity
GROUP BY i.Severity ORDER BY i.Severity;

-- R2. Top recurring problems (candidates for PROBLEM management / permanent fix)
SELECT PipelineName, ErrorCode, COUNT(*) AS Tickets, SUM(OccurrenceCount) AS Occurrences,
       MAX(CreatedUtc) AS LastSeen
FROM ops.Incident
GROUP BY PipelineName, ErrorCode
ORDER BY Occurrences DESC;

-- R3. Backlog ageing buckets
SELECT CASE WHEN DATEDIFF(HOUR,CreatedUtc,SYSUTCDATETIME()) < 4  THEN '0-4h'
            WHEN DATEDIFF(HOUR,CreatedUtc,SYSUTCDATETIME()) < 24 THEN '4-24h'
            ELSE '>24h' END AS AgeBucket,
       Severity, COUNT(*) AS OpenTickets
FROM ops.Incident WHERE Status NOT IN ('Resolved','Closed')
GROUP BY CASE WHEN DATEDIFF(HOUR,CreatedUtc,SYSUTCDATETIME()) < 4  THEN '0-4h'
              WHEN DATEDIFF(HOUR,CreatedUtc,SYSUTCDATETIME()) < 24 THEN '4-24h'
              ELSE '>24h' END, Severity;

-- R4. Ticket quality audit: resolved/closed tickets missing root cause or with 1-line work log
SELECT i.IncidentNumber, i.Status, i.Title,
       IIF(i.RootCause IS NULL,'MISSING','ok') AS RootCause,
       (SELECT COUNT(*) FROM ops.IncidentWorkLog w WHERE w.IncidentId=i.IncidentId AND w.Author<>'system') AS HumanNotes
FROM ops.Incident i
WHERE i.Status IN ('Resolved','Closed');

-- R5. Escalation history
SELECT i.IncidentNumber, w.EntryUtc, w.Author, w.Note
FROM ops.IncidentWorkLog w JOIN ops.Incident i ON i.IncidentId = w.IncidentId
WHERE w.EntryType = 'Escalation'
ORDER BY w.EntryUtc;

-- R6. Class leaderboard (if all learners share one DB, AssignedTo = learner name)
SELECT AssignedTo, COUNT(*) AS Resolved, AVG(DATEDIFF(MINUTE, CreatedUtc, ResolvedUtc)) AS AvgMTTR_Mins
FROM ops.Incident WHERE ResolvedUtc IS NOT NULL AND AssignedTo IS NOT NULL
GROUP BY AssignedTo ORDER BY AvgMTTR_Mins;
