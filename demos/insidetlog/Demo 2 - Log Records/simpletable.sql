USE simplerecoverydb;
GO
DROP TABLE IF EXISTS asimpletable;
GO
CREATE TABLE asimpletable (col1 INT);
GO
CHECKPOINT
GO
