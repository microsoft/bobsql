USE simplerecoverydb;
GO
CHECKPOINT
GO
CREATE INDEX asimpleclusteredtable_idx ON asimpleclusteredtable (col2);
GO