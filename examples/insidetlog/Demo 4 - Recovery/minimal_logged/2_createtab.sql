USE bulklogdb;
GO
DROP TABLE IF EXISTS bigtab;
GO
CREATE TABLE bigtab (col1 INT, col2 char(7000) not null);
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 10)
BEGIN
	INSERT INTO bigtab VALUES (@x, 'x');
	SET @x = @x + 1;
END;
GO
