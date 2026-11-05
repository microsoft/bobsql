docker stop sql2017CU10
docker stop sql2017latest
docker rm sql2017CU10
docker rm sql2017latest
docker volume rm sqlvolume
docker rmi mcr.microsoft.com/mssql/server:2017-CU10-ubuntu
docker rmi mcr.microsoft.com/mssql/server:2017-latest-ubuntu