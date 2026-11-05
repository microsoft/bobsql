USE simplerecoverydb;
GO
CHECKPOINT;
GO
BEGIN TRAN
UPDATE asimpleclusteredtable SET col1 = 10;
COMMIT TRAN;
GO
