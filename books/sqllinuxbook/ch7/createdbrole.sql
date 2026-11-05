USE [WideWorldImporters]
GO
IF (SELECT IS_ROLEMEMBER('Application_Users', 'appuser')) IS NOT NULL
    ALTER ROLE Application_Users DROP MEMBER appuser
GO
DROP ROLE IF EXISTS Application_Users
GO
CREATE ROLE Application_Users
GO
ALTER ROLE Application_Users ADD MEMBER appuser
GO
GRANT CONTROL ON SCHEMA::Application TO Application_Users
GO