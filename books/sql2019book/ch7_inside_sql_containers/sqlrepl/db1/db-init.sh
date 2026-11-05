#!/bin/sh
set -eu
SQLCMDPASSWORD="${MSSQL_SA_PASSWORD:?Set MSSQL_SA_PASSWORD before container startup}"
SqlLoginPassword=$(printf '%s' "$SQLCMDPASSWORD" | sed "s/'/''/g")
export SqlLoginPassword
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
#wait for the SQL Server to come up
sleep 45s

mkdir -p /var/opt/mssql/ReplData/

echo "running set up script"
#run the setup script to create the DB and the schema in the DB
/opt/mssql-tools/bin/sqlcmd -b -S localhost -U sa -d master -i db-init.sql
