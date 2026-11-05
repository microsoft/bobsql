USE letsgostars;
GO
DROP TABLE IF EXISTS fillthelog;
GO
CREATE TABLE fillthelog (col1 INT, col2 CHAR(7000) NOT NULL);
GO
SET NOCOUNT ON;
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 100000)
BEGIN
    INSERT INTO fillthelog VALUES (@x, '1');
    SET @x = @x + 1;
END;
GO
SET NOCOUNT OFF;
GO