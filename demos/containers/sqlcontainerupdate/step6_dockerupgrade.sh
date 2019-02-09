sudo docker stop sql2017cu10
sudo docker run -e 'ACCEPT_EULA=Y' -e 'MSSQL_SA_PASSWORD=Sql2017isfast' -p 1401:1433 -v sqlvolume:/var/opt/mssql --hostname sql2019 --name sql2019 -d mcr.microsoft.com/mssql/rhel/server:vNext-CTP2.0

