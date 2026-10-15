/* =====================================================================
   02_ops_logging_and_incident_procs.sql
   Logging framework + automatic ticket creation + ticket lifecycle.
   Called by ADF "Stored procedure" activities and by support engineers.
   ===================================================================== */

/* ---------------------------------------------------------------
   ops.usp_RaiseIncident
   Creates a ticket, OR (de-duplication) bumps OccurrenceCount on an
   already-open ticket for the same pipeline + error code.
   WHY dedupe: a pipeline retried 5 times should not create 5 tickets
   (alert storm / ticket noise is a classic prod-support anti-pattern).
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.usp_RaiseIncident
    @PipelineName varchar(128),
    @RunId        varchar(64)    = NULL,
    @ErrorCode    varchar(50)    = NULL,
    @ErrorMessage nvarchar(4000) = NULL,
    @Source       varchar(20)    = 'Auto-ADF',
    @Severity     char(2)        = NULL,
    @Title        nvarchar(200)  = NULL,
    @Category     varchar(50)    = 'Data Pipeline',
    @Author       varchar(100)   = 'system'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @IncidentId int;

    -- default severity rules (business impact based)
    IF @Severity IS NULL
        SET @Severity = CASE
            WHEN @PipelineName = 'PL_Master_Daily'           THEN 'P2'  -- CFO report impacted
            WHEN @Source = 'HealthCheck'
                 AND @ErrorCode IN ('HC01','HC02','HC03','HC04','HC05') THEN 'P2'  -- wrong/missing numbers
            WHEN @Source = 'HealthCheck'                      THEN 'P3'
            ELSE 'P3' END;

    SELECT TOP (1) @IncidentId = IncidentId
    FROM ops.Incident
    WHERE PipelineName = @PipelineName
      AND ISNULL(ErrorCode,'') = ISNULL(@ErrorCode,'')
      AND Status NOT IN ('Resolved','Closed')
    ORDER BY IncidentId DESC;

    IF @IncidentId IS NOT NULL
    BEGIN
        UPDATE ops.Incident
           SET OccurrenceCount = OccurrenceCount + 1,
               RunId           = ISNULL(@RunId, RunId),
               ErrorMessage    = ISNULL(@ErrorMessage, ErrorMessage),
               LastUpdatedUtc  = SYSUTCDATETIME()
         WHERE IncidentId = @IncidentId;

        INSERT ops.IncidentWorkLog(IncidentId, Author, EntryType, Note)
        VALUES (@IncidentId, @Author, 'System',
                CONCAT('Repeat occurrence. RunId=', @RunId, ' | ', LEFT(@ErrorMessage, 3500)));
    END
    ELSE
    BEGIN
        INSERT ops.Incident(Title, Description, Severity, Category, Source, PipelineName, RunId, ErrorCode, ErrorMessage)
        VALUES (ISNULL(@Title, CONCAT(@PipelineName, ' failed - ', ISNULL(@ErrorCode,'UNKNOWN'))),
                CONCAT('Auto-generated. Pipeline=', @PipelineName, '; RunId=', @RunId, CHAR(10), @ErrorMessage),
                @Severity, @Category, @Source, @PipelineName, @RunId, @ErrorCode, @ErrorMessage);
        SET @IncidentId = SCOPE_IDENTITY();

        INSERT ops.IncidentWorkLog(IncidentId, Author, EntryType, Note)
        VALUES (@IncidentId, @Author, 'System', CONCAT('Incident created from ', @Source, '. Severity ', @Severity));
    END
END
GO

/* ---------------------------------------------------------------
   ops.usp_LogRunStart  -- first activity of every pipeline
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.usp_LogRunStart
    @RunId        varchar(64),
    @PipelineName varchar(128),
    @TriggerName  varchar(128) = NULL,
    @RunDate      char(8)      = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- a rerun gets a NEW RunId in ADF, so normally no collision; MERGE keeps it safe anyway
    MERGE ops.PipelineRunLog AS t
    USING (SELECT @RunId AS RunId) AS s ON t.RunId = s.RunId
    WHEN MATCHED THEN UPDATE SET Status='InProgress', StartUtc=SYSUTCDATETIME(), EndUtc=NULL,
                                 ErrorCode=NULL, ErrorMessage=NULL, FailedActivity=NULL
    WHEN NOT MATCHED THEN INSERT (RunId, PipelineName, TriggerName, RunDate, Status)
                          VALUES (@RunId, @PipelineName, @TriggerName, @RunDate, 'InProgress');
END
GO

/* ---------------------------------------------------------------
   ops.usp_LogRunEnd  -- success path or failure path
   On failure -> automatically raises / updates an incident.
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.usp_LogRunEnd
    @RunId          varchar(64),
    @Status         varchar(20),              -- Succeeded | Failed
    @RowsRead       bigint         = NULL,
    @RowsWritten    bigint         = NULL,
    @FailedActivity varchar(128)   = NULL,
    @ErrorCode      varchar(50)    = NULL,
    @ErrorMessage   nvarchar(4000) = NULL,
    @PipelineName   varchar(128)   = NULL,
    @RunDate        char(8)        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Pipeline varchar(128);

    /* "Rerun from failed activity" creates a NEW RunId but SKIPS SP_LogStart
       (it already succeeded in the original run). Without this block the end
       log would update 0 rows and reconciliation (HC03) would break.
       Lesson: logging must survive every rerun mode. */
    IF NOT EXISTS (SELECT 1 FROM ops.PipelineRunLog WHERE RunId = @RunId)
        INSERT ops.PipelineRunLog (RunId, PipelineName, TriggerName, RunDate, Status)
        VALUES (@RunId, ISNULL(@PipelineName,'UNKNOWN'), 'rerun-from-activity', @RunDate, 'InProgress');

    UPDATE ops.PipelineRunLog
       SET Status = @Status, EndUtc = SYSUTCDATETIME(),
           RowsRead = @RowsRead, RowsWritten = @RowsWritten,
           FailedActivity = @FailedActivity, ErrorCode = @ErrorCode,
           ErrorMessage = LEFT(@ErrorMessage, 4000),
           @Pipeline = PipelineName
     WHERE RunId = @RunId;

    IF @Status = 'Failed'
        EXEC ops.usp_RaiseIncident
             @PipelineName = @Pipeline, @RunId = @RunId,
             @ErrorCode = @ErrorCode,
             @ErrorMessage = @ErrorMessage,
             @Source = 'Auto-ADF';
END
GO

/* ---------------------------------------------------------------
   ops.usp_UpdateIncident  -- used by humans during the labs
   Enforces lifecycle via ops.IncidentStatusTransition and
   stamps Ack/Resolve/Close times (needed for MTTA / MTTR).
   Pass @NewStatus = NULL to only add a work note.
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.usp_UpdateIncident
    @IncidentNumber varchar(12),
    @Author         varchar(100),
    @Note           nvarchar(4000),
    @NewStatus      varchar(20)    = NULL,
    @EntryType      varchar(20)    = NULL,    -- Note | Escalation | Communication (auto 'StatusChange' if status changes)
    @AssignTo       varchar(100)   = NULL,
    @AssignmentGroup varchar(50)   = NULL,
    @Severity       char(2)        = NULL,
    @RootCause      nvarchar(2000) = NULL,
    @Resolution     nvarchar(2000) = NULL,
    @ParentIncident varchar(12)    = NULL,
    @ChangeRef      varchar(50)    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Id int, @Cur varchar(20), @CurRC nvarchar(2000), @CurRes nvarchar(2000), @CurSev char(2);

    SELECT @Id = IncidentId, @Cur = Status, @CurRC = RootCause, @CurRes = Resolution, @CurSev = Severity
    FROM ops.Incident WHERE IncidentNumber = @IncidentNumber;

    IF @Id IS NULL
        THROW 50100, 'Incident number not found.', 1;

    IF @NewStatus IS NOT NULL AND @NewStatus <> @Cur
       AND NOT EXISTS (SELECT 1 FROM ops.IncidentStatusTransition WHERE FromStatus=@Cur AND ToStatus=@NewStatus)
    BEGIN
        DECLARE @msg nvarchar(300) = CONCAT('Invalid status transition ', @Cur, ' -> ', @NewStatus,
                    '. Check ops.IncidentStatusTransition.');
        THROW 50101, @msg, 1;
    END

    IF @NewStatus = 'Resolved' AND COALESCE(@Resolution, @CurRes) IS NULL
        THROW 50102, 'Resolution text is mandatory before moving to Resolved.', 1;

    IF @NewStatus = 'Closed' AND @Cur = 'Resolved' AND COALESCE(@RootCause, @CurRC) IS NULL
        THROW 50103, 'Root cause is mandatory before closing (Resolved -> Closed).', 1;

    UPDATE ops.Incident
       SET Status          = ISNULL(@NewStatus, Status),
           AssignedTo      = ISNULL(@AssignTo, AssignedTo),
           AssignmentGroup = ISNULL(@AssignmentGroup, AssignmentGroup),
           Severity        = ISNULL(@Severity, Severity),
           RootCause       = ISNULL(@RootCause, RootCause),
           Resolution      = ISNULL(@Resolution, Resolution),
           ParentIncident  = ISNULL(@ParentIncident, ParentIncident),
           ChangeRef       = ISNULL(@ChangeRef, ChangeRef),
           AcknowledgedUtc = CASE WHEN @NewStatus='Acknowledged' AND AcknowledgedUtc IS NULL THEN SYSUTCDATETIME() ELSE AcknowledgedUtc END,
           ResolvedUtc     = CASE WHEN @NewStatus='Resolved' THEN SYSUTCDATETIME()
                                  WHEN @NewStatus='InProgress' AND @Cur='Resolved' THEN NULL ELSE ResolvedUtc END,
           ClosedUtc       = CASE WHEN @NewStatus='Closed' THEN SYSUTCDATETIME() ELSE ClosedUtc END,
           LastUpdatedUtc  = SYSUTCDATETIME()
     WHERE IncidentId = @Id;

    INSERT ops.IncidentWorkLog(IncidentId, Author, EntryType, Note)
    VALUES (@Id, @Author,
            COALESCE(@EntryType, CASE WHEN @NewStatus IS NOT NULL AND @NewStatus<>@Cur THEN 'StatusChange' ELSE 'Note' END),
            CONCAT(CASE WHEN @NewStatus IS NOT NULL AND @NewStatus<>@Cur THEN CONCAT('[', @Cur, ' -> ', @NewStatus, '] ') ELSE '' END,
                   CASE WHEN @Severity IS NOT NULL AND @Severity<>@CurSev THEN CONCAT('[Severity ', @CurSev, ' -> ', @Severity, '] ') ELSE '' END,
                   CASE WHEN @AssignmentGroup IS NOT NULL THEN CONCAT('[Group=', @AssignmentGroup, '] ') ELSE '' END,
                   @Note));

    SELECT IncidentNumber, Status, Severity, AssignmentGroup, AssignedTo, LastUpdatedUtc
    FROM ops.Incident WHERE IncidentId = @Id;
END
GO

/* ---------------------------------------------------------------
   ops.usp_GetIncident  -- one-shot view of a ticket + timeline
   --------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.usp_GetIncident
    @IncidentNumber varchar(12)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM ops.Incident WHERE IncidentNumber = @IncidentNumber;
    SELECT w.EntryUtc, w.Author, w.EntryType, w.Note
    FROM ops.IncidentWorkLog w JOIN ops.Incident i ON i.IncidentId = w.IncidentId
    WHERE i.IncidentNumber = @IncidentNumber
    ORDER BY w.WorkLogId;
END
GO
PRINT 'Ops logging & incident procedures created.';
