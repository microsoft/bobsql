USE [WideWorldImporters]
GO
-- The table definition for the [Sales].[Customer] table
--
DROP TABLE IF EXISTS [Sales].[Customers]
GO
CREATE TABLE [Sales].[Customers](
	[CustomerID] [int] NOT NULL,
	[CustomerName] [nvarchar](100) NOT NULL,
	[BillToCustomerID] [int] NOT NULL,
	[CustomerCategoryID] [int] NOT NULL,
	[BuyingGroupID] [int] NULL,
	[PrimaryContactPersonID] [int] NOT NULL,
	[AlternateContactPersonID] [int] NULL,
	[DeliveryMethodID] [int] NOT NULL,
	[DeliveryCityID] [int] NOT NULL,
	[PostalCityID] [int] NOT NULL,
	[CreditLimit] [decimal](18, 2) NULL,
	[AccountOpenedDate] [date] NOT NULL,
	[StandardDiscountPercentage] [decimal](18, 3) NOT NULL,
	[IsStatementSent] [bit] NOT NULL,
	[IsOnCreditHold] [bit] NOT NULL,
	[PaymentDays] [int] NOT NULL,
	[PhoneNumber] [nvarchar](20) NOT NULL,
	[FaxNumber] [nvarchar](20) NOT NULL,
	[DeliveryRun] [nvarchar](5) NULL,
	[RunPosition] [nvarchar](5) NULL,
	[WebsiteURL] [nvarchar](256) NOT NULL,
	[DeliveryAddressLine1] [nvarchar](60) NOT NULL,
	[DeliveryAddressLine2] [nvarchar](60) NULL,
	[DeliveryPostalCode] [nvarchar](10) NOT NULL,
	[DeliveryLocation] [geography] NULL,
	[PostalAddressLine1] [nvarchar](60) NOT NULL,
	[PostalAddressLine2] [nvarchar](60) NULL,
	[PostalPostalCode] [nvarchar](10) NOT NULL,
	[LastEditedBy] [int] NOT NULL,
--	[ValidFrom] [datetime2](7) GENERATED ALWAYS AS ROW START NOT NULL,
--	[ValidTo] [datetime2](7) GENERATED ALWAYS AS ROW END NOT NULL
 CONSTRAINT [PK_Sales_Customers] PRIMARY KEY CLUSTERED 
(
	[CustomerID] ASC
),
 CONSTRAINT [UQ_Sales_Customers_CustomerName] UNIQUE NONCLUSTERED 
(
	[CustomerName] ASC)
)
GO
-- Foreign Key Constraints
--
ALTER TABLE [Sales].[Customers]  WITH CHECK ADD  CONSTRAINT [FK_Sales_Customers_AlternateContactPersonID_Application_People] FOREIGN KEY([AlternateContactPersonID])
REFERENCES [Application].[People] ([PersonID])
GO
ALTER TABLE [Sales].[Customers]  WITH CHECK ADD  CONSTRAINT [FK_Sales_Customers_Application_People] FOREIGN KEY([LastEditedBy])
REFERENCES [Application].[People] ([PersonID])
GO
ALTER TABLE [Sales].[Customers]  WITH CHECK ADD  CONSTRAINT [FK_Sales_Customers_BillToCustomerID_Sales_Customers] FOREIGN KEY([BillToCustomerID])
REFERENCES [Sales].[Customers] ([CustomerID])
GO
ALTER TABLE [Sales].[Customers]  WITH CHECK ADD  CONSTRAINT [FK_Sales_Customers_PrimaryContactPersonID_Application_People] FOREIGN KEY([PrimaryContactPersonID])
REFERENCES [Application].[People] ([PersonID])
GO
-- Default Value Constraint
--
ALTER TABLE [Sales].[Customers] ADD  CONSTRAINT [DF_Sales_Customers_CustomerID]  DEFAULT (NEXT VALUE FOR [Sequences].[CustomerID]) FOR [CustomerID]
GO

