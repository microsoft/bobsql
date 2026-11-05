USE [WideWorldImporters]
GO
DROP TABLE IF EXISTS CustomerRates
GO
CREATE TABLE CustomerRates
(CustomerRegion NVARCHAR(30),
StandardDiscountPercentage [decimal](18,3),
PaymentDays INT
)
INSERT INTO CustomerRates VALUES ('Texas', 10.0, 30)
GO
DROP PROCEDURE IF EXISTS [Sales].[InsertCustomer]
GO
CREATE PROCEDURE [Sales].[InsertCustomer]
@PrimaryContactID INT, @AlternateContactID INT, @CustomerRegion NVARCHAR(30)
AS
-- Declare local variables
-- 
DECLARE @StandardDiscountPercentage DECIMAL(18,3)
DECLARE @PaymentDays INT

-- Find the normal editor with a known PersonID = 0
--
DECLARE @EditedBy INT
SELECT @EditedBy = PersonID FROM [Application].[People]
WHERE PersonID = 0

-- Create a temporary table to store results for customer payment information
--
CREATE TABLE #CustomerPayment
(StandardDiscountPercentage [DECIMAL](18, 3) NOT NULL,
PaymentDays INT NOT NULL
)

INSERT INTO #CustomerPayment SELECT StandardDiscountPercentage, PaymentDays
FROM CustomerRates
WHERE CustomerRegion = @CustomerRegion

SELECT @StandardDiscountPercentage = StandardDiscountPercentage, 
@PaymentDays = PaymentDays FROM #CustomerPayment

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
VALUES (@CustomerID, 'WeLoveSQLOnLinuxToo', @CustomerID, 1, @PrimaryContactID, @AlternateContactID, 1, 1, 1, getdate(), @StandardDiscountPercentage, 0, 0, @PaymentDays, 
'817-111-1111', '817-222-2222', 'www.welovesqlonlinux.com', 'Texas', '76182', 'Texas', '76182', @EditedBy)
GO