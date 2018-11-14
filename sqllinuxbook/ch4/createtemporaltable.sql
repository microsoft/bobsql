USE [WideWorldImporters]
GO
-- If you have already created the table we need to turn off system versioning first
--
IF EXISTS (SELECT * FROM sys.objects where name = 'NewPeople')
	ALTER TABLE [Application].[NewPeople] SET (SYSTEM_VERSIONING = OFF)
GO
-- Drop the archive table if it exists
-- 
DROP TABLE IF EXISTS [Application].[NewPeople_Archive]
GO
DROP TABLE IF EXISTS [Application].[NewPeople]
GO
CREATE TABLE [Application].[NewPeople](
	[PersonID] [int] PRIMARY KEY NOT NULL,
	[FullName] [nvarchar](50) NOT NULL,
	[PreferredName] [nvarchar](50) NOT NULL,
	[SearchName]  AS (concat([PreferredName],N' ',[FullName])) PERSISTED NOT NULL,
	[IsPermittedToLogon] [bit] NOT NULL,
	[LogonName] [nvarchar](50) NULL,
	[IsExternalLogonProvider] [bit] NOT NULL,
	[HashedPassword] [varbinary](max) NULL,
	[IsSystemUser] [bit] NOT NULL,
	[IsEmployee] [bit] NOT NULL,
	[IsSalesperson] [bit] NOT NULL,
	[UserPreferences] [nvarchar](max) NULL,
	[PhoneNumber] [nvarchar](20) NULL,
	[FaxNumber] [nvarchar](20) NULL,
	[EmailAddress] [nvarchar](256) NULL,
	[Photo] [varbinary](max) NULL,
	[CustomFields] [nvarchar](max) NULL,
	[OtherLanguages]  AS (json_query([CustomFields],N'$.OtherLanguages')),
	[LastEditedBy] [int] NOT NULL,
	[ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL,
	[ValidTo] [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL,
PERIOD FOR SYSTEM_TIME ([ValidFrom], [ValidTo])
)
WITH (SYSTEM_VERSIONING = ON ( HISTORY_TABLE = [Application].[NewPeople_Archive]))
GO
