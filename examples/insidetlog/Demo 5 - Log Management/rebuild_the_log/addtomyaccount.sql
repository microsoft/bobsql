USE showmethemoney;
GO
DROP TABLE IF EXISTS bankaccount;
GO
CREATE TABLE bankaccount (acctno INT, name nvarchar(30), balance decimal(10,2))
GO
BEGIN TRAN
INSERT INTO bankaccount VALUES (1, 'Bob Ward', 1000000);
GO
-- I forgot to roll back this back. Ooops...
-- No problem recovery will do this for me
CHECKPOINT;
Go
USE MASTER;
GO