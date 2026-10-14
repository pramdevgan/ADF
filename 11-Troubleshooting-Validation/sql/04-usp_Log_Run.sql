/* =====================================================================
   Script 04: audit.usp_Log_Run – writes one row per successful load
   Run this script ALONE in Query editor.
   ===================================================================== */
CREATE OR ALTER PROCEDURE audit.usp_Log_Run
    @PipelineName NVARCHAR(200),
    @RunId        NVARCHAR(100),
    @LoadDate     NVARCHAR(10),
    @Status       NVARCHAR(20),
    @RowsRead     INT,
    @RowsCopied   INT,
    @Message      NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @d DATE = CONVERT(DATE, @LoadDate, 23);
    INSERT INTO audit.LoadLog (PipelineName, RunId, LoadDate, Status, RowsRead, RowsCopied, FactRows, RejectedRows, Message)
    VALUES (@PipelineName, @RunId, @d, @Status, @RowsRead, @RowsCopied,
            (SELECT COUNT(*) FROM dbo.FactOrders       WHERE LoadDate = @d),
            (SELECT COUNT(*) FROM audit.RejectedOrders WHERE LoadDate = @d),
            @Message);
END
