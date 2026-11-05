USE simplerecoverydb;
GO
DROP TABLE IF EXISTS bigtab;
GO
CREATE TABLE bigtab (col1 INT, col2 CHAR(7000));
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 1000)
BEGIN
	INSERT INTO bigtab VALUES (@x, 'x');
	SET @x = @x + 1;
END
GO
CHECKPOINT;
GO
CREATE UNIQUE CLUSTERED INDEX bigtab_idx ON bigtab (col1);
GO