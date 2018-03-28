docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Sql2017isfast" -p 1401:1433 --name sql1 -d microsoft/mssql-server-linux:2017-latest
