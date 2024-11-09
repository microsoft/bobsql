USE simplerecoverydb;
GO
CHECKPOINT;
GO
BEGIN TRAN
UPDATE asimpleclusteredtable SET col2 = 10;
ROLLBACK TRAN;
GO
