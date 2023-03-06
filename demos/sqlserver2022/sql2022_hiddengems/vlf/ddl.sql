USE testvlf;
GO
DROP TABLE IF EXISTS growtable;
GO
CREATE TABLE growtable (COL1 int, COL2 char(7000) not null);
GO
SET NOCOUNT ON;
GO
BEGIN TRAN
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 150000)
BEGIN
	INSERT INTO growtable VALUES (@x, 'x');
	SET @x = @x + 1
END
GO
SET NOCOUNT OFF;
GO
COMMIT TRAN
GO