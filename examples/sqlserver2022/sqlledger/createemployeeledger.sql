USE ContosoHR;
GO
-- Create the Employees table and make it an updatetable Ledger table
DROP TABLE IF EXISTS [dbo].[Employees];
GO
CREATE TABLE [dbo].[Employees](
	[EmployeeID] [int] IDENTITY(1,1) NOT NULL,
	[SSN] [char](11) NOT NULL,
	[FirstName] [nvarchar](50) NOT NULL,
	[LastName] [nvarchar](50) NOT NULL,
	[Salary] [money] NOT NULL
	)
WITH 
(
  SYSTEM_VERSIONING = ON,
  LEDGER = ON
); 
GO
