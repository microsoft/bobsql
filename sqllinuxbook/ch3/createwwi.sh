# Parameters are sa password, sqllinux password
SERVER=$1
SAPWD=$2
sqlcmd -S$SERVER -Usa -P$SAPWD -icleanup.sql
sqlcmd -S$SERVER -Usa -P$SAPWD -icreatelogin.sql
sqlcmd -Usqllinux -PSql2017isfast -idropandcreatedb.sql
sqlcmd -Usqllinux -PSql2017isfast -icreateschemas.sql
sqlcmd -Usqllinux -PSql2017isfast -icreatesequences.sql
sqlcmd -Usqllinux -PSql2017isfast -icreatepeople.sql
sqlcmd -Usqllinux -PSql2017isfast -icreatecustomers.sql

