SERVERIP=$(kubectl get service | grep mssql-service | awk {'print $4'})
PORT=31433
sqlcmd -Usa -P<REDACTED> -S$SERVERIP,$PORT -Q"SELECT @@version"