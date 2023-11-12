USE texasrangerswschamps;
GO
DROP TABLE IF EXISTS wearethechampions;
GO
CREATE TABLE wearethechampions (col1 int, col2 char(5000) not null);
GO
DECLARE @x int;
SET @x = 0;
WHILE (@x < 100000)
BEGIN
	INSERT INTO wearethechampions VALUES (1, '...of the world');
	SET @x = @x + 1;
END
GO
