USE ContosoHR;
GO
EXECUTE sp_verify_database_ledger 
N'{"database_name":"ContosoHR","block_id":0,"hash":"0xC8125753E3CFE79A1B396BC257364B27698151A3A41A86F8FDF64ABA39D1CCD1","last_transaction_commit_time":"2022-07-04T11:25:55.1966667","digest_time":"2022-07-04T18:27:32.9950501"}'
GO