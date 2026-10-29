sqlcmd -Usa -Q"DROP DATABASE IF EXISTS WideWorldImportersDW" -Sbwsql2019
sqlcmd -Usa -irestorewwidw.sql -Sbwsql2019
