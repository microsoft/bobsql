USE WideWorldImporters;
GO
SELECT v.Vehicle_Registration, v.Vehicle_City, count(*) AS cargo
FROM Warehouse.Vehicles v
JOIN Warehouse.Vehicle_StockItems vs
ON v.Vehicle_Registration = vs.Vehicle_Registration
GROUP BY v.Vehicle_Registration, v.Vehicle_City;
GO