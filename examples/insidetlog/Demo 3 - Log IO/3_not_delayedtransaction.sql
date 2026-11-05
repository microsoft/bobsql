USE annaisasqlnewbie;
GO
CREATE TABLE butshealwayswins (col1 int);
GO

-- Look at the trace of log I/O after this
BEGIN TRAN
INSERT INTO butshealwayswins VALUES (1);
GO

-- Now commit it
COMMIT TRANSACTION
GO