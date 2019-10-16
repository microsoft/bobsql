sudo docker stop sql2019latest
sudo docker rm sql2019latest
sudo docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=Sql2019isfast" -p 1401:1433 --name sql2019latest --hostname sql2019latest -v sqlvolume:/var/opt/mssql -d mcr.microsoft.com/mssql/rhel/server:2019-latest
