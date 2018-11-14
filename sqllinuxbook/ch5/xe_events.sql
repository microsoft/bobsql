-- List the XEvent events, description, and columns for each event and description
--
SELECT xeo.name, xeo.description, xeoc.name, xeoc.description
FROM sys.dm_xe_objects xeo
INNER JOIN sys.dm_xe_object_columns xeoc
ON xeo.name = xeoc.object_name
WHERE xeo.object_type = 'event'
AND (xeo.capabilities IS NULL OR xeo.capabilities & 1 = 0) -- Filter out private events
ORDER BY xeo.name, xeoc.name
GO
