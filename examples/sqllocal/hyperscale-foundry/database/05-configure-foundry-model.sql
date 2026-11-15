/* ============================================================================
   Caldova Regional Care Transfer Center
   05-configure-foundry-model.sql : register Microsoft Foundry with Entra auth
   ============================================================================ */

USE [CaldovaRegionalCare];
GO

IF EXISTS
(
    SELECT 1
    FROM sys.database_scoped_credentials
    WHERE [name] = N'https://$(FoundryResourceName).services.ai.azure.com/'
)
    DROP DATABASE SCOPED CREDENTIAL [https://$(FoundryResourceName).services.ai.azure.com/];
GO

CREATE DATABASE SCOPED CREDENTIAL [https://$(FoundryResourceName).services.ai.azure.com/]
WITH IDENTITY = 'Managed Identity',
     SECRET = '{"resourceid":"https://cognitiveservices.azure.com"}';
GO

UPDATE ai.ModelEndpoint
SET IsActive = 0
WHERE IsActive = 1;

IF EXISTS (SELECT 1 FROM ai.ModelEndpoint WHERE EndpointName = N'MicrosoftFoundry')
BEGIN
    UPDATE ai.ModelEndpoint
    SET BaseUrl = N'https://$(FoundryResourceName).services.ai.azure.com/openai',
        ModelId = N'$(ModelDeployment)',
        CredentialName = N'https://$(FoundryResourceName).services.ai.azure.com/',
        TimeoutSeconds = 180,
        IsActive = 1
    WHERE EndpointName = N'MicrosoftFoundry';
END;
ELSE
BEGIN
    INSERT ai.ModelEndpoint
        (EndpointName, BaseUrl, ModelId, CredentialName, TimeoutSeconds, IsActive)
    VALUES
        (N'MicrosoftFoundry',
         N'https://$(FoundryResourceName).services.ai.azure.com/openai',
         N'$(ModelDeployment)',
         N'https://$(FoundryResourceName).services.ai.azure.com/', 180, 1);
END;
GO

SELECT EndpointName, BaseUrl, ModelId, CredentialName, TimeoutSeconds, IsActive
FROM ai.ModelEndpoint
ORDER BY EndpointName;
GO