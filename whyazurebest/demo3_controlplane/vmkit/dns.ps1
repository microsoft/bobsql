<#
.SYNOPSIS
    Shows what the VM's DNS resolver believes about the database, and whether
    port 1433 is reachable.

.DESCRIPTION
    Runs INSIDE the demo VM. This is the beat that makes Private Link click for
    an audience.

    Before the private DNS zone is linked to the VNet, this resolves to a
    PUBLIC IP even though a private endpoint already exists. Microsoft Learn is
    blunt about why: "The private DNS zone exists and contains the correct A
    record, but it isn't linked to the VNet from which DNS queries originate.
    Without a VNet link, Azure DNS can't consult the private zone, and returns
    the public IP from the service's public DNS."

    After the link, it resolves to 10.42.1.x and the connection works.
#>

. "$PSScriptRoot\config.ps1"

Write-Host ''
Show-Command "Clear-DnsClientCache; Resolve-DnsName $ServerFqdn"

Clear-DnsClientCache

$answers = Resolve-DnsName -Name $ServerFqdn -Type A -ErrorAction Stop
$answers | Format-Table Name, Type, NameHost, IPAddress -AutoSize | Out-String | Write-Host

$ip = ($answers | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress

if (-not $ip) {
    Write-Host '  No A record resolved.' -ForegroundColor Red
}
elseif ($ip -like '10.42.*') {
    Write-Host "  $ip is INSIDE the VNet. DNS is going through the private zone." -ForegroundColor Green
}
else {
    Write-Host "  $ip is a PUBLIC address. The private DNS zone is not linked to this VNet." -ForegroundColor Yellow
}

Write-Host ''
Show-Command "Test-NetConnection $ServerFqdn -Port 1433"

$tcp = Test-NetConnection -ComputerName $ServerFqdn -Port 1433 -WarningAction SilentlyContinue
Write-Host "  RemoteAddress    : $($tcp.RemoteAddress)"
Write-Host "  TcpTestSucceeded : $($tcp.TcpTestSucceeded)" -ForegroundColor ($(if ($tcp.TcpTestSucceeded) { 'Green' } else { 'Yellow' }))
Write-Host ''
