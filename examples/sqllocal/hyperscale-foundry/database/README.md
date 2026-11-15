# Hyperscale-specific model configuration and checks

Small cloud-only additions to the [shared database scripts](../../database/README.md).
Use the [deployment wrapper](../README.md) rather than deploying these files
against the local SQL instance.

| File | Purpose |
| --- | --- |
| [05-configure-foundry-model.sql](05-configure-foundry-model.sql) | Configure managed-identity credential and the active `MicrosoftFoundry` model endpoint |
| [Verify.sql](Verify.sql) | Require Hyperscale, exactly one active endpoint with a credential, and the invocation procedure |

The configuration SQL uses SQLCMD variables `$(FoundryResourceName)` and
`$(ModelDeployment)`, supplied by `Deploy.ps1` from its validated parameters.
For manual execution, enable SQLCMD mode and supply the same nonsecret values.
Do not replace them with a real credential or commit private environment
configuration.

The credential's `SECRET` JSON contains the public token audience
`https://cognitiveservices.azure.com`, **not** a password or API key. The SQL
logical server's managed identity must have Foundry access, and its user
database master key must already exist.

This script replaces the credential for the chosen resource and deactivates
other endpoint rows. Verification checks configuration only: use the
wrapper's `-TestFoundry` switch for an intentional live invocation.
