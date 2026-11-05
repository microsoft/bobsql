USE AdventureWorksLT;
GO
INSERT INTO SalesLT.Address (
    AddressLine1,
    AddressLine2,
    City,
    StateProvince,
    CountryRegion,
    PostalCode
)
VALUES (
    '129 W 81st St, Apt 5A',         -- Jerry's apartment
    'Newman!',            -- Classic Newman moment
    'New York',
    'NY',
    'US',
    '10024'
);
GO
