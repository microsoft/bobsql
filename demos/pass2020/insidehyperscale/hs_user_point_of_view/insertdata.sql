DROP TABLE IF EXISTS howboutthemcowboys;
GO
CREATE TABLE howboutthemcowboys (col1 INT primary key clustered, col2 CHAR(7000) NOT NULL);
GO
SET NOCOUNT ON;
GO
BEGIN TRAN;
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 2000000)
BEGIN
	INSERT INTO howboutthemcowboys VALUES (@x, 'x');
	SET @x = @x + 1;
END
GO
COMMIT TRAN;
GO
SET NOCOUNT OFF;
GO