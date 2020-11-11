-- Streaming restore: Takes around 1 minute
RESTORE DATABASE cowboysonazure2
FROM URL = N'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazure.bak'
WITH MOVE 'cowboysonazure_data' to 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazure2data.mdf',
MOVE 'cowboysonazure_log' TO 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazurelog2.ldf'
GO

-- Snapshot restore: Takes 1 second
RESTORE DATABASE cowboysonazuresnap2
FROM URL = N'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuresnap.bak'
WITH MOVE 'cowboysonazure_data' to 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuresnap2data.mdf',
MOVE 'cowboysonazure_log' TO 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuresnaplog2.ldf'
GO


