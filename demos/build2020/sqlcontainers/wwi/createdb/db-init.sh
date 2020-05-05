# wait for the SQL Server to come up. We only need about 15 seconds. Azure Pipeline delay task appears to be 
sleep 15s

echo "Create the WideWorldImporters Database...."
# run the setup script to create the DB and the schema in the DB

/opt/mssql-tools/bin/sqlcmd -S mssql -U sa -P Sql2019isfast -d master -i wwi.sql
