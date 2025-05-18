EXECUTE sp_executesql
    N'SELECT * FROM AdventureWorks.HumanResources.Employee
    WHERE BusinessEntityID = @level',
    N'@level TINYINT',
    @level = 2;
GO

