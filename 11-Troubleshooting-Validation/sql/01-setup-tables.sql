/* =====================================================================
   Module 3 – Troubleshooting & Data Validation
   Script 01: schemas, tables, master data, control (manifest) data
   Run in: Azure SQL Database  sqldb-adflab  →  Query editor (preview)
   Paste the WHOLE script and click Run once (no GO needed).
   Safe to re-run: it drops and recreates everything for this module.
   ===================================================================== */

-- ---------- Schemas (EXEC used because CREATE SCHEMA must be alone in a batch)
IF SCHEMA_ID('stg')   IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dim')   IS NULL EXEC('CREATE SCHEMA dim');
IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit');

-- ---------- Drop (re-runnable)
DROP TABLE IF EXISTS dbo.FactOrders;
DROP TABLE IF EXISTS stg.Orders;
DROP TABLE IF EXISTS dim.Customer;
DROP TABLE IF EXISTS dim.Product;
DROP TABLE IF EXISTS audit.RejectedOrders;
DROP TABLE IF EXISTS audit.SourceControl;
DROP TABLE IF EXISTS audit.ValidationResults;
DROP TABLE IF EXISTS audit.LoadLog;

-- ---------- STAGING: raw landing table, every column text
-- Why all NVARCHAR? The file must ALWAYS land, even if values are bad.
-- Type conversion + rejection happens later in SQL where we can see it.
CREATE TABLE stg.Orders (
    OrderID     NVARCHAR(100) NULL,
    OrderDate   NVARCHAR(100) NULL,
    CustomerID  NVARCHAR(100) NULL,
    ProductID   NVARCHAR(100) NULL,
    Quantity    NVARCHAR(100) NULL,
    UnitPrice   NVARCHAR(100) NULL,
    Status      NVARCHAR(100) NULL,
    SourceFile  NVARCHAR(400) NULL,   -- filled by ADF additional column $$FILEPATH
    RunId       NVARCHAR(100) NULL    -- filled by ADF additional column @pipeline().RunId
);

-- ---------- DIMENSIONS (reference / master data)
CREATE TABLE dim.Customer (
    CustomerID   NVARCHAR(10)  NOT NULL PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    City         NVARCHAR(50)  NULL
);
CREATE TABLE dim.Product (
    ProductID   NVARCHAR(10)  NOT NULL PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    ListPrice   DECIMAL(10,2) NOT NULL
);

-- ---------- TARGET: typed fact table
CREATE TABLE dbo.FactOrders (
    FactID     INT IDENTITY(1,1) PRIMARY KEY,
    OrderID    INT           NOT NULL,
    OrderDate  DATE          NOT NULL,
    CustomerID NVARCHAR(10)  NULL,
    ProductID  NVARCHAR(10)  NULL,
    Quantity   INT           NOT NULL,
    UnitPrice  DECIMAL(10,2) NOT NULL,
    Amount     AS (Quantity * UnitPrice) PERSISTED,
    Status     NVARCHAR(20)  NULL,
    LoadDate   DATE          NOT NULL,
    RunId      NVARCHAR(100) NULL,
    LoadedAt   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ---------- AUDIT tables
CREATE TABLE audit.RejectedOrders (
    RejectID     INT IDENTITY(1,1) PRIMARY KEY,
    LoadDate     DATE          NOT NULL,
    RunId        NVARCHAR(100) NULL,
    OrderID      NVARCHAR(100) NULL,
    OrderDate    NVARCHAR(100) NULL,
    CustomerID   NVARCHAR(100) NULL,
    ProductID    NVARCHAR(100) NULL,
    Quantity     NVARCHAR(100) NULL,
    UnitPrice    NVARCHAR(100) NULL,
    Status       NVARCHAR(100) NULL,
    RejectReason NVARCHAR(200) NOT NULL,
    RejectedAt   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Control / manifest: what the SOURCE team says they sent (row count + total)
CREATE TABLE audit.SourceControl (
    LoadDate            DATE          NOT NULL PRIMARY KEY,
    FileName            NVARCHAR(100) NOT NULL,
    ExpectedRows        INT           NOT NULL,
    ExpectedTotalAmount DECIMAL(14,2) NOT NULL,
    ReceivedAt          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE audit.ValidationResults (
    ValidationID INT IDENTITY(1,1) PRIMARY KEY,
    RunId        NVARCHAR(100) NULL,
    LoadDate     DATE          NULL,
    CheckName    NVARCHAR(50)  NOT NULL,
    Severity     NVARCHAR(10)  NOT NULL,   -- CRITICAL | WARNING
    Expected     NVARCHAR(50)  NULL,
    Actual       NVARCHAR(50)  NULL,
    Result       NVARCHAR(10)  NOT NULL,   -- PASS | FAIL | SKIPPED
    CheckedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE audit.LoadLog (
    LogID        INT IDENTITY(1,1) PRIMARY KEY,
    PipelineName NVARCHAR(200) NULL,
    RunId        NVARCHAR(100) NULL,
    LoadDate     DATE          NULL,
    Status       NVARCHAR(20)  NULL,
    RowsRead     INT           NULL,
    RowsCopied   INT           NULL,
    FactRows     INT           NULL,
    RejectedRows INT           NULL,
    Message      NVARCHAR(4000) NULL,
    LoggedAt     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

-- ---------- Master data
INSERT INTO dim.Customer (CustomerID, CustomerName, City) VALUES
('C001','Aarav Traders','Kanpur'),     ('C002','Bharat Retail','Lucknow'),
('C003','Chandra Stores','Delhi'),     ('C004','Deepak Mart','Mumbai'),
('C005','Ekta Enterprises','Pune'),    ('C006','Fateh Supplies','Chandigarh'),
('C007','Ganga Bazaar','Varanasi'),    ('C008','Himalaya Shop','Dehradun'),
('C009','Indus Goods','Jaipur'),       ('C010','Jyoti Electronics','Bhopal'),
('C011','Kaveri Mart','Bengaluru'),    ('C012','Lakshmi Stores','Chennai'),
('C013','Mahi Traders','Ahmedabad'),   ('C014','Narmada Retail','Indore'),
('C015','Omkar Supplies','Nagpur');

INSERT INTO dim.Product (ProductID, ProductName, ListPrice) VALUES
('P001','Laptop',55000.00), ('P002','Wireless Mouse',650.00), ('P003','Keyboard',1500.00),
('P004','Monitor 24in',12000.00), ('P005','Headphones',2500.00), ('P006','USB-C Hub',1800.00);

-- ---------- Control records sent by the source team (simulated manifest)
INSERT INTO audit.SourceControl (LoadDate, FileName, ExpectedRows, ExpectedTotalAmount) VALUES
('2026-10-01','orders_20261001.csv',20,444100.00),
('2026-10-02','orders_20261002.csv',22,347800.00),
('2026-10-03','orders_20261003.csv',18,512150.00),
('2026-10-04','orders_20261004.csv',15,400450.00),
('2026-10-05','orders_20261005.csv',16,784400.00);

-- ---------- Check
SELECT 'dim.Customer' AS TableName, COUNT(*) AS Rows FROM dim.Customer
UNION ALL SELECT 'dim.Product', COUNT(*) FROM dim.Product
UNION ALL SELECT 'audit.SourceControl', COUNT(*) FROM audit.SourceControl;
-- Expected: 15, 6, 5
