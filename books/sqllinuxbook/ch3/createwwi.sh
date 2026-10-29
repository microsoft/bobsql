# Parameters are sa password, sqllinux password
SERVER=$1
SAPWD=$2
sqlcmd -S$SERVER -Usa -P$SAPWD -icleanup.sql
sqlcmd -S$SERVER -Usa -P$SAPWD -icreatelogin.sql
sqlcmd -Usqllinux -P<REDACTED> -idropandcreatedb.sql
sqlcmd -Usqllinux -P<REDACTED> -icreateschemas.sql
sqlcmd -Usqllinux -P<REDACTED> -icreatesequences.sql
sqlcmd -Usqllinux -P<REDACTED> -icreatepeople.sql
sqlcmd -Usqllinux -P<REDACTED> -icreatecustomers.sql

