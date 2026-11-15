USE [CaldovaRegionalCare];
GO

IF DATABASEPROPERTYEX(DB_NAME(), 'Edition') <> 'Hyperscale'
    THROW 50100, 'CaldovaRegionalCare is not a Hyperscale database.', 1;

IF (SELECT COUNT(*) FROM ai.ModelEndpoint WHERE IsActive = 1) <> 1
    THROW 50101, 'Exactly one model endpoint must be active.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM ai.ModelEndpoint
    WHERE EndpointName = N'MicrosoftFoundry'
      AND IsActive = 1
      AND CredentialName IS NOT NULL
)
    THROW 50102, 'The Microsoft Foundry endpoint is not active.', 1;

IF OBJECT_ID(N'ai.usp_InvokeTransferSkill', N'P') IS NULL
    THROW 50103, 'The shared skill invocation procedure is missing.', 1;

SELECT
    DB_NAME() AS DatabaseName,
    DATABASEPROPERTYEX(DB_NAME(), 'Edition') AS Edition,
    DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective') AS ServiceObjective,
    endpoint.EndpointName,
    endpoint.BaseUrl,
    endpoint.ModelId,
    endpoint.IsActive
FROM ai.ModelEndpoint AS endpoint
WHERE endpoint.IsActive = 1;
GO