REM Parameters are server name and sa password
REM
sqlcmd -Usa -icleanup.sql -S%1 -P%2
sqlcmd -Usa -icreatelogin.sql -S%1 -P%2
sqlcmd -Usqllinux -idropandcreatedb.sql -S%1 -PSql2017isfast
sqlcmd -Usqllinux -icreateschemas.sql -S%1 -PSql2017isfast
sqlcmd -Usqllinux -icreatesequences.sql -S%1 -PSql2017isfast
sqlcmd -Usqllinux -icreatepeople.sql -S%1 -PSql2017isfast
sqlcmd -Usqllinux -icreatecustomers.sql -S%1 -PSql2017isfast
