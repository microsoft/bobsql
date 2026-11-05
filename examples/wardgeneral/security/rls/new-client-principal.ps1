function New-ClientPrincipalHeader {
    param(
        [Nullable[int]] $ProviderId,
        [ValidateSet('Admin', 'Attending')]
        [string] $Role = 'Admin'
    )

    $claims = @(
        @{ typ = 'ProviderId'; val = if ($null -eq $ProviderId) { '' } else { [string] $ProviderId } },
        @{ typ = 'Role'; val = $Role }
    )
    $principal = @{
        auth_typ = 'Area8Simulator'
        name_typ = 'ProviderId'
        role_typ = 'Role'
        claims = $claims
    }
    $json = $principal | ConvertTo-Json -Compress -Depth 4
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}
