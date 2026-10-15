/* =====================================================================
   00_create_adf_login_user.sql
   Run in: Azure SQL Database [sqldb-retail]  (NOT master)
   Creates a CONTAINED database user that ADF uses to connect.
   Password is stored in Key Vault secret 'sql-adfloader-password'.

   Why a dedicated least-privilege user (and not the server admin)?
   - Blast radius: if ADF credentials leak, attacker can't drop the server.
   - Audit: queries from 'adfloader' are clearly the pipeline.
   - Scenario S5 rotates this password to simulate a credential incident.

   Production best practice: use ADF Managed Identity
     CREATE USER [adf-ps-<initials>] FROM EXTERNAL PROVIDER;
   (needs a Microsoft Entra admin on the SQL server). The lab uses SQL auth +
   Key Vault so we can practise a secret-rotation incident.
   ===================================================================== */

-- >>> CHANGE THE PASSWORD BELOW and put the SAME value in Key Vault <<<
CREATE USER adfloader WITH PASSWORD = 'Adf#Loader2026!ChangeMe';
GO
ALTER ROLE db_datareader ADD MEMBER adfloader;
ALTER ROLE db_datawriter ADD MEMBER adfloader;
GRANT EXECUTE ON SCHEMA::dbo TO adfloader;
GRANT EXECUTE ON SCHEMA::ops TO adfloader;
GRANT EXECUTE ON SCHEMA::rpt TO adfloader;
GRANT ALTER   ON SCHEMA::stg TO adfloader;  -- required for TRUNCATE TABLE in Copy pre-copy script
GO

-- verify
SELECT dp.name, dp.type_desc, r.name AS role_name
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members rm ON rm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
WHERE dp.name = 'adfloader';
