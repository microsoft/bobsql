USE [WideWorldImporters]
GO
DROP PROCEDURE IF EXISTS [Sales].[InsertCustomer]
GO
CREATE PROCEDURE [Sales].[InsertCustomer]
@PrimaryContactID INT, @AlternateContactID INT
AS
-- Find the normal editor with a known PersonID = 0
--
DECLARE @EditedBy INT
SELECT @EditedBy = PersonID FROM [Application].[People]
WHERE PersonID = 0

-- INSERT into Customers
-- Primary and Alternate Contacs are passed in as parameters
DECLARE @CustomerID INT
SET @CustomerID = NEXT VALUE for [Sequences].[CustomerID]
INSERT INTO [Sales].[Customers]
([CustomerID], [CustomerName], [BillToCustomerID], [CustomerCategoryID], [PrimaryContactPersonID],
[AlternateContactPersonID], [DeliveryMethodID], [DeliveryCityID], [PostalCityID], 
[AccountOpenedDate], [StandardDiscountPercentage], [IsStatementSent], [IsOnCreditHold],
[PaymentDays], [PhoneNumber], [FaxNumber], [WebsiteURL], [DeliveryAddressLine1], 
[DeliveryPostalCode], [PostalAddressLine1], [PostalPostalCode], [LastEditedBy])
VALUES (@CustomerID, 'WeAllLoveSQLOnLinux', @CustomerID, 1, @PrimaryContactID, @AlternateContactID, 1, 1, 1, getdate(), 0.10, 0, 0, 30, 
'817-111-1111', '817-222-2222', 'www.welovesqlonlinux.com', 'Texas', '76182', 'Texas', '76182', @EditedBy)
GO