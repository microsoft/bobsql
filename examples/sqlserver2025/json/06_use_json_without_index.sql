USE contactsdb;
GO

-- Show names and tags for certain tag values using a JSON index
-- Allowing MAXDOP to get higher will result in a similar speed to the json index seek
SELECT JSON_VALUE(jdoc, '$.name') AS name, JSON_QUERY(jdoc, '$.tags') AS tags
FROM contacts
WHERE JSON_CONTAINS(jdoc, N'fitness', '$.tags[*]') = 1
GO