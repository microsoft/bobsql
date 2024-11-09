USE [master];
GO
ALTER DATABASE [annaisasqlnewbie] SET DELAYED_DURABILITY = FORCED;
GO

CREATE TABLE bigtab (col1 int, col2 char(7000) not null);
GO
INSERT INTO bigtab VALUES (1, '1');
GO

DECLARE @x int;
SET @x = 0;


COMMIT TRAN

SELECT * FROM sys.dm_exec_requests
WHERE COMMAND = 'LOG WRITER';
GO