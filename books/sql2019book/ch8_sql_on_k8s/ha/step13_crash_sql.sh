#!/bin/sh
set -eu
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
SERVERIP=$(kubectl get service | grep mssql-service | awk {'print $4'})
PORT=31433
sqlcmd -b -Usa -S$SERVERIP,$PORT -Q"SHUTDOWN WITH NOWAIT"