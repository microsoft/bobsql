USE annaisasqlnewbie;
GO
CREATE TABLE bigtab (col1 int, col2 char(7000) not null);
GO
BEGIN TRAN
-- Run about 10 times to see log flush
INSERT INTO bigtab VALUES (1, 'bob will win next time');
GO

COMMIT TRAN