USE simplerecoverydb;
GO
DELETE FROM asimpletable;
GO
INSERT INTO asimpletable VALUES (1);
GO
CHECKPOINT
GO
BEGIN TRAN
UPDATE asimpletable SET col1 = 10;
ROLLBACK TRAN
GO

