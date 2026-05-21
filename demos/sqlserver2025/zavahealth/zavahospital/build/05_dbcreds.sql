/* =======================================================================
   NIM on AKS — Database Master Key + TLS trust
   
   The AKS ingress uses a self-signed cert (CN=nim-aks.local).
   Import nim-aks.local.cer into SQL Server's trusted cert store:
     1. Copy k8s\tls.cer to a path accessible by SQL Server
     2. Import into Local Computer → Trusted Root CAs via certlm.msc
     3. Restart SQL Server to pick up the new trust store
   
   No DATABASE SCOPED CREDENTIAL needed — NIM endpoints are open
   (no api-key), only TLS is required for sp_invoke_external_rest_endpoint.

   Pass the master-key password via sqlcmd -v, or edit the :setvar below:
     sqlcmd -S localhost -d zavahospital -E -i 05_dbcreds.sql ^
        -v MasterKeyPassword="<your-strong-password>"
   ======================================================================= */
:setvar MasterKeyPassword "REPLACE_WITH_STRONG_PASSWORD"

USE zavahospital;
GO

IF NOT EXISTS(SELECT * FROM sys.symmetric_keys WHERE [name] = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'$(MasterKeyPassword)';
END;
GO
