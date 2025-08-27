USE [ContosoOrders];
GO

-- Insert a new Order
INSERT INTO Orders (CustomerFirstName, CustomerLastName, Company, SalesDate, EstimatedShipDate, ShippingID, ShippingLocation, Product, Quantity, Price)
VALUES 
('Art', 'Vandelay', 'Vandelay Industries', '2025-04-20', DATEADD(DAY, 75, '2025-04-20'), 1, 'Queens, NYC', 'Drake''s Coffee Cake', 1, 15.00);
GO


