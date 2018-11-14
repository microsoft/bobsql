USE [WideWorldImporters]
GO
DECLARE @CustomerID INT
SET @CustomerID = NEXT VALUE for [Sequences].[CustomerID]
INSERT INTO [Sales].[Customers]
([CustomerID], [CustomerName], [BillToCustomerID], [CustomerCategoryID], [PrimaryContactPersonID],
[AlternateContactPersonID], [DeliveryMethodID], [DeliveryCityID], [PostalCityID], 
[AccountOpenedDate], [StandardDiscountPercentage], [IsStatementSent], [IsOnCreditHold],
[PaymentDays], [PhoneNumber], [FaxNumber], [WebsiteURL], [DeliveryAddressLine1], 
[DeliveryPostalCode], [PostalAddressLine1], [PostalPostalCode], [LastEditedBy])
VALUES (@CustomerID, 'WeLoveSQLOnLinux', @CustomerID, 1, 1, 2, 1, 1, 1, getdate(), 0.10, 0, 0, 30, 
'817-111-1111', '817-222-2222', 'www.welovesqlonlinux.com', 'Texas', '76182', 'Texas', '76182', 0)
GO