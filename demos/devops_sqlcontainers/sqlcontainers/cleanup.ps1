docker-compose down
docker stop sql2022latest
docker stop bwsql
docker rm sql2022latest
docker rm bwsql
docker volume rm sql2022volume

