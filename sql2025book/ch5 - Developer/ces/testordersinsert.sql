USE [ContosoOrders];
GO

-- Insert a test record
INSERT INTO Orders (CustomerFirstName, CustomerLastName, Company, SalesDate, EstimatedShipDate, ShippingID, ShippingLocation, Product, Quantity, Price)
VALUES 
('Test', 'User', 'Test Company', '2025-04-20', '2025-04-25', 1, 'Test Location', 'Test Product', 1, 100.00);

-- Check our changes
SELECT * FROM sys.dm_change_feed_log_scan_sessions
ORDER by start_time DESC;
GO

-- Delete test from Orders
DELETE FROM Orders WHERE Company = 'Test Company';
GO

