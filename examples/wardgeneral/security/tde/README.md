# Security — TDE with a Customer-Managed Key

This optional example changes the existing Ward General logical server from the
default Azure SQL service-managed TDE protector to a versionless
customer-managed key stored in Azure Key Vault. The protector is configured at
the logical-server level, so every database that inherits the server setting,
including `wardgeneral`, uses the same protector.

The database remains encrypted throughout the change. Azure SQL rewraps the
database encryption key; it does not decrypt and re-encrypt every database
page.

## File

| File | Purpose |
| --- | --- |
| `provision-tde-cmk.ps1` | Creates the vault and RSA key, grants the logical server identity access, registers the versionless key, and makes it the server-level TDE protector with automatic rotation. |

## Prerequisites

- Complete the Getting Started Ward General deployment.
- Fill in `first-app/wardgeneral.env`. The script reads the logical
  server and database from `WardGeneral__Server` and `WardGeneral__Database`.
- Sign in with `az login` and select the subscription containing the logical
  server.
- Use Azure CLI 2.83 or later. Older versions reject a versionless key URI.
- The signed-in identity must be able to create a Key Vault, manage vault access
  policies and keys, register an Azure SQL server key, and change the server's
  TDE protector.
- The script reads the logical server's region from Azure unless `-Loc` is
  passed explicitly.
- Choose a globally unique Key Vault name and pass it with `-Vault`.

## Run

Pass a globally unique Key Vault name:

```powershell
./security/tde/provision-tde-cmk.ps1 `
  -Vault '<globally-unique-vault-name>'
```

To use different resource names, pass them explicitly:

```powershell
./security/tde/provision-tde-cmk.ps1 `
    -Rg '<resource-group>' `
    -Server '<logical-server>' `
    -Database 'wardgeneral' `
    -Vault '<globally-unique-vault-name>' `
    -KeyName 'wardgeneral-tde-key'
```

This script is **not preview-only**. Running it immediately performs these
Azure changes:

1. Ensures the logical server has a system-assigned managed identity.
2. Creates an access-policy-based Key Vault with purge protection enabled.
3. Grants the server identity `Get`, `WrapKey`, and `UnwrapKey` permissions.
4. Creates a 2048-bit RSA key.
5. Registers the versionless key URI on the logical server.
6. Sets that key as the server-level TDE protector and enables automatic
   rotation.
7. Explicitly enables TDE for `wardgeneral`.

The registered URI has no version:

```text
https://<vault>.vault.azure.net/keys/<key-name>
```

Azure SQL resolves that URI to the current enabled key version, so the portal
and `az sql server tde-key show` can display a versioned URI. Automatic rotation
still follows newer enabled versions.

## Verify

The script prints the resulting protector and database TDE status. The same
state can be checked separately:

```powershell
az sql server tde-key show `
    --resource-group '<resource-group>' `
    --server '<logical-server>' `
    --query '{type:serverKeyType,uri:uri,autoRotation:autoRotationEnabled}'

az sql db tde show `
    --resource-group '<resource-group>' `
    --server '<logical-server>' `
    --database 'wardgeneral'
```

The expected protector type is `AzureKeyVault`, automatic rotation is enabled,
and database TDE remains enabled.

## Return to the Service-Managed Protector

Switching protectors is an online key operation. It rewraps the database
encryption key rather than re-encrypting all database pages:

```powershell
az sql server tde-key set `
    --resource-group '<resource-group>' `
    --server '<logical-server>' `
    --server-key-type ServiceManaged
```

Verify that `serverKeyType` is `ServiceManaged` before removing any registered
server key, Key Vault access policy, vault key, or vault. Retain old key
material while any backup might still require it. Purge protection prevents
immediate permanent deletion of the vault or key.

## Geo-Replication

A geo-secondary of a CMK-protected database must be able to use every required
source key. Before creating the geo-secondary:

- Grant the target logical server identity `Get`, `WrapKey`, and `UnwrapKey` on
  the source protector's Key Vault.
- Register the source protector key on the target logical server.

Without those prerequisites, geo-secondary creation fails with
`AzureKeyVaultMissingPermissions`.

## Boundaries

- This is a server-level CMK example, not a database-level CMK example.
- All inheriting databases on the logical server are affected.
- The script uses a Key Vault access policy rather than Azure RBAC.
- The script does not provide an automated teardown.
- Do not delete key material merely because the active protector has changed.

References:

- [Microsoft Learn — Azure SQL TDE with customer-managed keys](https://learn.microsoft.com/azure/azure-sql/database/transparent-data-encryption-byok-overview), accessed 2026-09-08.
- [Microsoft Learn — Rotate the TDE protector](https://learn.microsoft.com/azure/azure-sql/database/transparent-data-encryption-byok-key-rotation), accessed 2026-09-08.
