DECLARE @x int;
DECLARE @y varchar(1000);
SET @x = 0;
WHILE (@x < 300)
BEGIN
	SET @y = 'BACKUP DATABASE db'+convert(varchar(5), @x)+' TO DISK = '+''''+'db'+convert(varchar(5), @x)+'.bak'+'''';
	SET @x = @x + 1;
	EXEC (@y);
	--PRINT @y;
END
GO