docker stop sql2019latest
docker rm sql2019latest
docker volume rm sqlvolume
docker rmi mcr.microsoft.com/mssql/rhel/server:2019-latest