if ([string]::IsNullOrWhiteSpace($env:SQLCMDPASSWORD)) {
    throw 'Set SQLCMDPASSWORD privately before running this demo. See SECRET-SCANNING.md.'
}
$Service = kubectl get services -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
if ($LASTEXITCODE -ne 0) { throw 'Kubernetes service lookup failed.' }
$Server+="-S"
$Server+=$Service
$Server+=",31433"
sqlcmd -b '-Usa' $Server '-Q"SELECT @@version"'
if ($LASTEXITCODE -ne 0) { throw 'Demo SQL command failed.' }
if ($LASTEXITCODE -ne 0) { throw 'Demo command failed.' }
