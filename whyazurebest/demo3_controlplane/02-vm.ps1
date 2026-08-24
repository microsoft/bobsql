<#
.SYNOPSIS
    Step 2 of 6. Creates the Windows client VM with a system-assigned identity.

.DESCRIPTION
    Runs from the presenter's laptop. Control plane only - no SQL connection.

    The VM is created BEFORE the logical server, because its managed identity
    becomes the server's Microsoft Entra admin in step 3.

    Prompts for the local admin password. The password is never echoed, never
    written to disk, and never leaves this process.

.NOTES
    The VM gets a public IP for two reasons: guaranteed outbound reachability
    to ARM, and RDP so the presenter can load the demo kit. Inbound is governed
    entirely by the subnet NSG, which denies the internet by default - only the
    single /32 added by allow-me.ps1 can reach port 3389.
#>

. "$PSScriptRoot\00-config.ps1"

Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Step "VM '$VmName'"
$existing = Invoke-Az @('vm', 'show', '-g', $ResourceGroup, '-n', $VmName) -AllowFailure
if ($existing) {
    Write-Skip 'Already exists - not recreating'
}
else {
    Write-Host ''
    Write-Host "  Local administrator for the VM will be '$VmAdminUser'." -ForegroundColor Yellow
    Write-Host '  Password must be 12-123 characters with three of: uppercase,' -ForegroundColor Yellow
    Write-Host '  lowercase, digit, special character.' -ForegroundColor Yellow
    Write-Host ''

    $secure = Read-Host -Prompt "  Password for $VmAdminUser" -AsSecureString
    $confirm = Read-Host -Prompt '  Confirm password' -AsSecureString

    $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirm)
    try {
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)

        if ($plain -cne $plain2) { throw 'Passwords did not match.' }
        if ($plain.Length -lt 12) { throw 'Password must be at least 12 characters.' }

        Write-Step "Creating VM (this takes a couple of minutes)"
        Invoke-Az @(
            'vm', 'create',
            '-g', $ResourceGroup,
            '-n', $VmName,
            # Must be explicit. az vm create defaults to the resource group's
            # location, while the VNet may live in a different region.
            '--location', $Location,
            '--image', $VmImage,
            '--size', $VmSize,
            '--vnet-name', $VNetName,
            '--subnet', $ClientSubnet,
            '--admin-username', $VmAdminUser,
            '--admin-password', $plain,
            '--assign-identity',
            '--public-ip-sku', 'Standard',
            # No NIC-level NSG - the subnet NSG governs. az wants "" for none,
            # which from PowerShell must be written as the literal '""'.
            '--nsg', '""',
            '--only-show-errors'
        ) | Out-Null
        Write-Ok 'Created'
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        Remove-Variable -Name plain, plain2 -ErrorAction SilentlyContinue
    }
}

Write-Step 'Resolving the VM system-assigned identity'
$identity = Get-VmIdentity
Write-Ok "Object (principal) ID : $($identity.PrincipalId)"
Write-Ok "Application (client) ID: $($identity.AppId)"

Write-Step 'Confirming no NIC-level NSG was created'
$nicId = & az vm show -g $ResourceGroup -n $VmName `
    --query 'networkProfile.networkInterfaces[0].id' -o tsv 2>&1
if ($LASTEXITCODE -ne 0) { throw "Could not read the VM NIC.`n$nicId" }
$nicNsg = & az network nic show --ids ($nicId | Out-String).Trim() `
    --query 'networkSecurityGroup.id' -o tsv 2>&1
if ([string]::IsNullOrWhiteSpace(($nicNsg | Out-String).Trim())) {
    Write-Ok "None. Inbound access is governed only by '$NsgName' on the subnet."
}
else {
    Write-Warn "A NIC-level NSG exists: $nicNsg"
    Write-Warn 'Inbound access is now governed by two NSGs. Expect confusion.'
}

Write-Host ''
Write-Ok 'Step 2 complete. Next: .\allow-me.ps1'
