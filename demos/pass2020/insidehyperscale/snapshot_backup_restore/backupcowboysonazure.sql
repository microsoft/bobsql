USE master;
GO
-- This takes ~3-4mins minutes to backup allocated pages within the 100Gb db
-- The bak file is about 7Gb
BACKUP DATABASE cowboysonazure
TO URL = N'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazure.bak';
GO
BACKUP DATABASE cowboysonazure
TO URL = N'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuresnap.bak'
WITH FILE_SNAPSHOT;
GO
EXEC sys.sp_delete_backup 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuresnap.bak', 'cowboysonazure' ;  
GO
USE cowboysonazure
GO
select * from sys.fn_db_backup_file_snapshots (null) ;  
GO  