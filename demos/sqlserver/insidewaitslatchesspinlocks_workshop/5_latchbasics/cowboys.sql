USE master;
GO
DROP DATABASE IF EXISTS willthecowboysevermakeitbacktothesuperbowl;
GO
CREATE DATABASE willthecowboysevermakeitbacktothesuperbowl;
GO
USE willthecowboysevermakeitbacktothesuperbowl;
GO
DROP TABLE IF EXISTS arethecowboysmediocre;
GO
CREATE TABLE arethecowboysmediocre (col1 int, col2 char(7000) not null);
GO
SET NOCOUNT ON;
GO
BEGIN TRAN;
GO
DECLARE @x INT;
SET @x = 0;
WHILE (@x < 5000000)
BEGIN
	INSERT INTO arethecowboysmediocre VALUES (@x, 'howboutthemcowboys');
	SET @x = @x + 1;
END
GO
COMMIT TRAN;
GO
SET NOCOUNT OFF;
GO