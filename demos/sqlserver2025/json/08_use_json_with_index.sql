USE contactsdb;
GO

SET STATISTICS TIME ON;

-- Show names and tags for certain tag values using a JSON index
SELECT JSON_VALUE(jdoc, '$.name') AS name, JSON_QUERY(jdoc, '$.tags') AS tags
FROM contacts
WHERE JSON_CONTAINS(jdoc, N'fitness', '$.tags[*]') = 1
GO

