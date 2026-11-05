USE [WideWorldImporters]
GO
-- The table definition for the [Application].[People] table
--
DROP TABLE IF EXISTS [Application].[People]
GO
CREATE TABLE [Application].[People](
	[PersonID] [int] NOT NULL,
	[FullName] [nvarchar](50) NOT NULL,
	[PreferredName] [nvarchar](50) NOT NULL,
--	[SearchName]  AS (concat([PreferredName],N' ',[FullName])) PERSISTED NOT NULL,
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
--	[OtherLanguages]  AS (json_query([CustomFields],N'$.OtherLanguages')),
	[LastEditedBy] [int] NOT NULL,
--	[ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL,
--	[ValidTo] [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL
 CONSTRAINT [PK_Application_People] PRIMARY KEY CLUSTERED 
(
	[PersonID] ASC
)
)
GO
-- Foreign key for a column within the People table referenced to the primary key
--
ALTER TABLE [Application].[People] WITH CHECK ADD CONSTRAINT [FK_Application_People_Application_People] FOREIGN KEY([LastEditedBy])
REFERENCES [Application].[People] ([PersonID])
GO
-- The default value for PersonID is a SEQUENCE value
--
ALTER TABLE [Application].[People] ADD CONSTRAINT [DF_Application_People_PersonID]  DEFAULT (NEXT VALUE FOR [Sequences].[PersonID]) FOR [PersonID]
GO
