USE [WideWorldImporters]
GO
INSERT INTO [Application].[People]
([PersonID], [FullName], [PreferredName], [IsPermittedToLogon],
[LogonName], [IsExternalLogonProvider], [IsSystemUser],
[IsEmployee], [IsSalesPerson], [LastEditedBy])
VALUES (0, 'Robert Dorr', 'TheKraken', 1, 'rdorr', 0, 1, 1, 0, 0)
GO
INSERT INTO [Application].[People]
([FullName], [PreferredName], [IsPermittedToLogon],
[LogonName], [IsExternalLogonProvider], [IsSystemUser],
[IsEmployee], [IsSalesPerson], [LastEditedBy])
VALUES ('Slava Oks', 'thegodfather', 1, 'slavao', 0, 1, 1, 0, 0)
GO
INSERT INTO [Application].[People]
([FullName], [PreferredName], [IsPermittedToLogon],
[LogonName], [IsExternalLogonProvider], [IsSystemUser],
[IsEmployee], [IsSalesPerson], [LastEditedBy])
VALUES ('Tobias Ternstrom', 'theswede', 1, 'tobiast', 0, 1, 1, 0, 0)
GO