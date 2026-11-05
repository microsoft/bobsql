if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$secret = @{
    apiVersion = 'v1'
    kind = 'Secret'
    metadata = @{ name = 'mssql-secret' }
    type = 'Opaque'
    data = @{ SA_PASSWORD = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($env:SQLCMDPASSWORD)) }
}
$secret | ConvertTo-Json -Depth 5 | kubectl create -f -
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes secret creation failed.' }
