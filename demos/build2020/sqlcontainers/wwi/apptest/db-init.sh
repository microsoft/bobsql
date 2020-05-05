echo "Perform application testing...."

# run a T-SQL script to perform sanity checks
/opt/mssql-tools/bin/sqlcmd -S mssql -U sa -P Sql2019isfast -d master -i apptest.sql
