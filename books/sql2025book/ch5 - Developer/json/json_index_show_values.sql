USE contactsdb;
GO

-- Show names and tags
SELECT TOP 5 JSON_VALUE(jdoc, '$.name') AS name, JSON_QUERY(jdoc, '$.tags') AS tags
FROM contacts;
GO
