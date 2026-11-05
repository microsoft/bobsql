#!/bin/sh
set -eu
MSSQL_SA_PASSWORD="$SQLCMDPASSWORD"
export MSSQL_SA_PASSWORD
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
sudo --preserve-env=MSSQL_SA_PASSWORD docker run -e "ACCEPT_EULA=Y" -e MSSQL_SA_PASSWORD -p 1401:1433 --name sql2019latest --hostname sql2019latest -v sqlvolume:/var/opt/mssql -d mcr.microsoft.com/mssql/rhel/server:2019-latest
