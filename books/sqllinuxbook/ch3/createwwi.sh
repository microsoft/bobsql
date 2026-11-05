#!/bin/sh
set -eu
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
: "${SQLLINUXPASSWORD:?Set the private sqllinux login password}"
SERVER="${1:?Supply the server name; passwords come from the environment}"
SqlLoginPassword=$(printf '%s' "$SQLLINUXPASSWORD" | sed "s/'/''/g")
export SqlLoginPassword
sqlcmd -b -S"$SERVER" -Usa -icleanup.sql
sqlcmd -b -S"$SERVER" -Usa -icreatelogin.sql
SQLCMDPASSWORD="$SQLLINUXPASSWORD"
export SQLCMDPASSWORD
sqlcmd -b -S"$SERVER" -Usqllinux -idropandcreatedb.sql
sqlcmd -b -S"$SERVER" -Usqllinux -icreateschemas.sql
sqlcmd -b -S"$SERVER" -Usqllinux -icreatesequences.sql
sqlcmd -b -S"$SERVER" -Usqllinux -icreatepeople.sql
sqlcmd -b -S"$SERVER" -Usqllinux -icreatecustomers.sql
