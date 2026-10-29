sudo docker stop sql2017CU10
sudo docker stop sql2017latest
sudo docker rm sql2017CU10
sudo docker rm sql2017latest
sudo docker rmi mcr.microsoft.com/mssql/server:2017-CU10-ubuntu
sudo docker rmi mcr.microsoft.com/mssql/server:2017-latest-ubuntu