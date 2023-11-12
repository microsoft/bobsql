USE texasrangerswschamps;
GO
DROP TABLE IF EXISTS wearethechampions;
GO
CREATE TABLE wearethechampions (col1 int, col2 varchar(5000));
GO

SELECT @@spid

INSERT INTO wearethechampions VALUES (1, '...of the world');
GO
