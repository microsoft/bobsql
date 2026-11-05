#!/bin/sh
set -eu
: "${SQLCMDPASSWORD:?Set SQLCMDPASSWORD privately before running this demo}"
export SQLCMDPASSWORD
sqlcmd -b -Usa -Slocalhost,1401 -Q"SELECT @@VERSION"