net start mssqlserver
sqlcmd -E -icleanup_setup_hang.sql
net stop mssqlserver
net start mssqlserver
