/* =====================================================================
   01_schemas_and_tables.sql
   Run in: Azure SQL Database  [sqldb-retail]  (Portal > SQL database > Query editor)
   Purpose: business tables (stg / dbo / rpt) + operations tables (ops)
            that act as our lightweight logging + ticketing (ITSM) system.
   Safe to re-run: drops & recreates objects.
   ===================================================================== */

-- ---------- Schemas ----------
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg AUTHORIZATION dbo');
IF SCHEMA_ID('ops') IS NULL EXEC('CREATE SCHEMA ops AUTHORIZATION dbo');
IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt AUTHORIZATION dbo');
GO

-- ---------- Drop (re-run friendly) ----------
DROP TABLE IF EXISTS ops.IncidentWorkLog;
DROP TABLE IF EXISTS ops.Incident;
DROP TABLE IF EXISTS ops.HealthCheckResult;
DROP TABLE IF EXISTS ops.PipelineRunLog;
DROP TABLE IF EXISTS ops.EscalationMatrix;
DROP TABLE IF EXISTS ops.IncidentStatusTransition;
DROP TABLE IF EXISTS rpt.DailySalesSummary;
DROP TABLE IF EXISTS dbo.FactSales;
DROP TABLE IF EXISTS dbo.DimCustomer;
DROP TABLE IF EXISTS stg.Sales;
DROP TABLE IF EXISTS stg.Customers;
GO

/* ---------- STAGING : landing zone in SQL, truncated before every load ----------
   Typed columns ON PURPOSE: if the CSV contains 'two' in quantity, the Copy activity
   fails with a type-conversion error (Scenario S2).                                  */
CREATE TABLE stg.Sales (
    OrderId     varchar(20)    NOT NULL,
    OrderDate   date           NULL,
    CustomerId  varchar(20)    NULL,
    ProductId   varchar(20)    NULL,
    Quantity    int            NULL,
    UnitPrice   decimal(10,2)  NULL,
    Amount      decimal(12,2)  NULL,
    StoreCode   varchar(10)    NULL
);

CREATE TABLE stg.Customers (
    CustomerId   varchar(20)   NOT NULL,
    CustomerName nvarchar(100) NULL,
    City         nvarchar(50)  NULL,
    Segment      varchar(20)   NULL,
    SignupDate   date          NULL
);

/* ---------- CORE ---------- */
CREATE TABLE dbo.DimCustomer (
    CustomerId   varchar(20)   NOT NULL CONSTRAINT PK_DimCustomer PRIMARY KEY,
    CustomerName nvarchar(100) NULL,
    City         nvarchar(50)  NULL,
    Segment      varchar(20)   NULL,
    SignupDate   date          NULL,
    UpdatedAtUtc datetime2(0)  NOT NULL CONSTRAINT DF_DimCustomer_Upd DEFAULT SYSUTCDATETIME()
);

/* NOTE: no unique constraint on OrderId -- deliberately, so the non-idempotent
   "hotfix" in Scenario S6 can create duplicates and the health check must catch it.
   In real production you WOULD add UNIQUE(OrderId) as a defence-in-depth control. */
CREATE TABLE dbo.FactSales (
    SalesKey      bigint IDENTITY(1,1) CONSTRAINT PK_FactSales PRIMARY KEY,
    OrderId       varchar(20)   NOT NULL,
    OrderDate     date          NOT NULL,
    CustomerId    varchar(20)   NOT NULL,
    ProductId     varchar(20)   NOT NULL,
    Quantity      int           NOT NULL,
    UnitPrice     decimal(10,2) NOT NULL,
    Amount        decimal(12,2) NOT NULL,
    StoreCode     varchar(10)   NULL,
    LoadDate      char(8)       NOT NULL,      -- business/run date yyyyMMdd
    PipelineRunId varchar(64)   NULL,          -- lineage back to ADF run
    LoadedAtUtc   datetime2(0)  NOT NULL CONSTRAINT DF_FactSales_Loaded DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_FactSales_LoadDate ON dbo.FactSales(LoadDate) INCLUDE (OrderId, CustomerId, Amount);

/* ---------- REPORT (what the business/CFO dashboard reads) ---------- */
CREATE TABLE rpt.DailySalesSummary (
    ReportDate   date          NOT NULL,
    Segment      varchar(20)   NOT NULL,
    City         nvarchar(50)  NOT NULL,
    Orders       int           NOT NULL,
    Revenue      decimal(14,2) NOT NULL,
    BuiltAtUtc   datetime2(0)  NOT NULL CONSTRAINT DF_DSS_Built DEFAULT SYSUTCDATETIME(),
    PipelineRunId varchar(64)  NULL
);

/* =====================================================================
   OPS  -- operational logging + mini ITSM (ticketing) tables
   ===================================================================== */

-- One row per pipeline run (written by ADF Stored Procedure activities)
CREATE TABLE ops.PipelineRunLog (
    LogId          bigint IDENTITY(1,1) CONSTRAINT PK_PipelineRunLog PRIMARY KEY,
    RunId          varchar(64)    NOT NULL,
    PipelineName   varchar(128)   NOT NULL,
    TriggerName    varchar(128)   NULL,
    RunDate        char(8)        NULL,
    Status         varchar(20)    NOT NULL,     -- InProgress | Succeeded | Failed
    StartUtc       datetime2(0)   NOT NULL CONSTRAINT DF_PRL_Start DEFAULT SYSUTCDATETIME(),
    EndUtc         datetime2(0)   NULL,
    DurationSec    AS DATEDIFF(SECOND, StartUtc, EndUtc),
    RowsRead       bigint         NULL,
    RowsWritten    bigint         NULL,
    FailedActivity varchar(128)   NULL,
    ErrorCode      varchar(50)    NULL,
    ErrorMessage   nvarchar(4000) NULL
);
CREATE UNIQUE INDEX UX_PRL_RunId ON ops.PipelineRunLog(RunId);

-- Ticket header (our "ServiceNow" for the lab)
CREATE TABLE ops.Incident (
    IncidentId       int IDENTITY(1,1) CONSTRAINT PK_Incident PRIMARY KEY,
    IncidentNumber   AS ('INC' + RIGHT('000000' + CAST(IncidentId AS varchar(10)), 6)) PERSISTED,
    Title            nvarchar(200)  NOT NULL,
    Description      nvarchar(max)  NULL,
    Severity         char(2)        NOT NULL CONSTRAINT DF_Inc_Sev DEFAULT 'P3'
                     CONSTRAINT CK_Inc_Sev CHECK (Severity IN ('P1','P2','P3','P4')),
    Status           varchar(20)    NOT NULL CONSTRAINT DF_Inc_Status DEFAULT 'New',
    Category         varchar(50)    NULL,       -- Data Pipeline | Data Quality | Access | Platform
    Source           varchar(20)    NOT NULL,   -- Auto-ADF | HealthCheck | Manual | Alert
    PipelineName     varchar(128)   NULL,
    RunId            varchar(64)    NULL,       -- latest failing run
    ErrorCode        varchar(50)    NULL,
    ErrorMessage     nvarchar(4000) NULL,
    OccurrenceCount  int            NOT NULL CONSTRAINT DF_Inc_Occ DEFAULT 1,
    AssignmentGroup  varchar(50)    NOT NULL CONSTRAINT DF_Inc_AG DEFAULT 'L1-DataOps',
    AssignedTo       varchar(100)   NULL,
    CreatedUtc       datetime2(0)   NOT NULL CONSTRAINT DF_Inc_Created DEFAULT SYSUTCDATETIME(),
    AcknowledgedUtc  datetime2(0)   NULL,
    ResolvedUtc      datetime2(0)   NULL,
    ClosedUtc        datetime2(0)   NULL,
    LastUpdatedUtc   datetime2(0)   NOT NULL CONSTRAINT DF_Inc_LU DEFAULT SYSUTCDATETIME(),
    RootCause        nvarchar(2000) NULL,
    Resolution       nvarchar(2000) NULL,
    ParentIncident   varchar(12)    NULL,       -- link child incident to master incident
    ChangeRef        varchar(50)    NULL        -- CHG number if a fix needed a change
);

-- Ticket timeline (every note / status change / escalation)
CREATE TABLE ops.IncidentWorkLog (
    WorkLogId   bigint IDENTITY(1,1) CONSTRAINT PK_IncidentWorkLog PRIMARY KEY,
    IncidentId  int           NOT NULL CONSTRAINT FK_IWL_Inc REFERENCES ops.Incident(IncidentId),
    EntryUtc    datetime2(0)  NOT NULL CONSTRAINT DF_IWL_Entry DEFAULT SYSUTCDATETIME(),
    Author      varchar(100)  NOT NULL,
    EntryType   varchar(20)   NOT NULL,   -- Note | StatusChange | Escalation | Communication | System
    Note        nvarchar(4000) NOT NULL
);

-- Results of every health-check execution
CREATE TABLE ops.HealthCheckResult (
    ResultId     bigint IDENTITY(1,1) CONSTRAINT PK_HCR PRIMARY KEY,
    CheckRunId   uniqueidentifier NOT NULL,
    RunDate      char(8)        NOT NULL,
    CheckId      varchar(10)    NOT NULL,
    CheckName    varchar(200)   NOT NULL,
    Status       varchar(4)     NOT NULL,   -- PASS | WARN | FAIL
    Detail       nvarchar(1000) NULL,
    CheckedAtUtc datetime2(0)   NOT NULL CONSTRAINT DF_HCR_At DEFAULT SYSUTCDATETIME()
);

-- Severity -> SLA -> who to call (reference data used in labs)
CREATE TABLE ops.EscalationMatrix (
    Severity          char(2)      NOT NULL PRIMARY KEY,
    Meaning           varchar(200) NOT NULL,
    AckWithinMins     int          NOT NULL,
    ResolveWithinHrs  int          NOT NULL,
    UpdateEveryMins   int          NOT NULL,
    L1                varchar(60)  NOT NULL,
    L2                varchar(60)  NOT NULL,
    L3                varchar(60)  NOT NULL,
    Management        varchar(60)  NOT NULL
);
INSERT ops.EscalationMatrix VALUES
('P1','Business-critical outage, no workaround (e.g. CFO report + regulatory feed down)',15, 4, 30,'L1-DataOps on-call','L2 Data Engineering lead','L3 Platform/Cloud + Microsoft Sev A','Delivery Head'),
('P2','Major degradation / SLA at risk, workaround possible',                          30, 8, 60,'L1-DataOps on-call','L2 Data Engineering','L3 Platform/Cloud','Support Manager'),
('P3','Single pipeline failed, limited impact, within SLA',                             120,24,240,'L1-DataOps','L2 Data Engineering','L3 on request','-'),
('P4','Minor / cosmetic / informational',                                               480,72,1440,'L1-DataOps','L2 backlog','-','-');

-- Allowed ticket lifecycle moves (enforced by ops.usp_UpdateIncident)
CREATE TABLE ops.IncidentStatusTransition (
    FromStatus varchar(20) NOT NULL,
    ToStatus   varchar(20) NOT NULL,
    CONSTRAINT PK_IST PRIMARY KEY (FromStatus, ToStatus)
);
INSERT ops.IncidentStatusTransition VALUES
('New','Acknowledged'),('New','Closed'),            -- Closed directly only for duplicates/false alarms
('Acknowledged','InProgress'),
('InProgress','Escalated'),('Escalated','InProgress'),
('InProgress','OnHold'),('OnHold','InProgress'),
('InProgress','Resolved'),('Escalated','Resolved'),
('Resolved','InProgress'),                          -- reopen
('Resolved','Closed');
GO

PRINT 'Schemas and tables created.';
