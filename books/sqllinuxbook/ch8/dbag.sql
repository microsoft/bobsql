CREATE DATABASE [cowboysrule]
GO
ALTER DATABASE [cowboysrule] SET RECOVERY FULL
GO
BACKUP DATABASE [cowboysrule] TO DISK = N'/var/opt/mssql/data/cowboysrule.bak'
GO