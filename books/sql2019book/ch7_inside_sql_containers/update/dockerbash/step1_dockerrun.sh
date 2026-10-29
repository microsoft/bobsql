sudo docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=Sql2017isfast" -p 1401:1433 --name sql2017CU10 --hostname sql2017CU10 -v sqlvolume:/var/opt/mssql -d mcr.microsoft.com/mssql/server:2017-CU10-ubuntu
