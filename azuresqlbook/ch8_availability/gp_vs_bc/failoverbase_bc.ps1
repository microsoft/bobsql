$resourceGroup = "<resource group>"
$server = "<server>"
$database = "<database>"
Invoke-AzSqlDatabaseFailover -ResourceGroupName $resourceGroup -ServerName $server -DatabaseName $database