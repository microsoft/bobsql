sudo docker stop sql2019latest
sudo docker rm sql2019latest
sudo docker volume rm sqlvolume
sudo docker rmi mcr.microsoft.com/mssql/rhel/server:2019-latest