USE simplerecoverydb;
GO
DROP TABLE IF EXISTS asimpleclusteredtable;
GO
CREATE TABLE asimpleclusteredtable (col1 INT primary key clustered, col2 INT);
GO
INSERT into asimpleclusteredtable VALUES (1, 1);
GO