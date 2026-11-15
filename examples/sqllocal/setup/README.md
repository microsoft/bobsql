# Windows setup and existing Foundry Local gateway

These scripts connect a Windows SQL Server 2025 machine to **existing**
Foundry Local deployments on AKS on Azure Local. They do not provision the
Azure Local system, cluster, models, MetalLB, or certificates. Caddy is not
part of this path.

## Configure before running

Read the [collection README](../README.md). `192.0.2.10` is a reserved example
IP, not a real gateway. Replace it consistently in scripts, SQL, and YAML.
Use your own protected kubeconfig outside the repository and pass its path.
PowerShell scripts default to the example `C:\setup\caldova-admin.kubeconfig`
or a same-folder file of that name.

Expected contracts:

| Resource | Expected name / value |
| --- | --- |
| Namespace | `foundry-local-operator` |
| Current chat deployment | `gpt-oss-20b` |
| Embedding deployment | `nemotron-3-embed-1b-bf16` |
| API-key secrets | `<deployment>-api-keys`, field `primary-key` |
| Gateway TLS secret | `inference-external-gateway-ip-tls` |
| Gateway class | `istio` |
| Example MetalLB pool and L2 advertisement | `caldova-model-lb` in `kube-system` |
| Example external gateway | `https://192.0.2.10` |

Confirm model readiness, network access to the Kubernetes API and gateway,
appropriate namespace/secret permissions, and a valid certificate whose IP
SAN covers your actual gateway. The SQL account needs administrator privileges
for the setup/test operations. Do not display kubeconfigs or secret output.

## 1. Install tools and trust the gateway

In elevated PowerShell, from the collection root:

```powershell
.\setup\Setup.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig'
```

For a named SQL instance, also pass `-SqlServiceName 'MSSQL$InstanceName'`.

**Side effects:** installs/checks Azure CLI, kubectl, kubelogin, connectedk8s,
curl, and sqlcmd; updates user PATH; constructs a user-local certificate
bundle for Azure CLI; imports the gateway root into `LocalMachine\Root`;
and restarts a running SQL Server service and restores its running dependents.
This changes machine trust. Verify the root certificate through a trusted
channel before importing it. Setup does not invoke models or configure SQL
database objects.

To repair trust alone, review and run
[Import-GatewayRootCertificate.ps1](Import-GatewayRootCertificate.ps1).
It reads only the public certificate chain (`tls.crt`), not the private key,
and saves `lab-root-ca.crt` locally. Local certificates are ignored by Git.

## 2. Check HTTPS, then authenticated inference

```powershell
.\setup\Test-FoundryHttps.ps1 -Endpoint 'https://<your-gateway-ip>/gpt-oss-20b/v1/chat/completions'
.\setup\Test-FoundryModel.ps1 -Mode Chat `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' -ExternalIPAddress '<your-gateway-ip>'
.\setup\Test-FoundryModel.ps1 -Mode Embedding `
    -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' -ExternalIPAddress '<your-gateway-ip>'
```

The HTTPS probe is unauthenticated and reports raw diagnostics. A 401/403/405
can establish HTTPS reachability but not inference success. Its default
`.svc.cluster.local` endpoint is internal DNS; supply a reachable gateway
from Windows.

The model tester obtains keys in memory, supplies headers to curl over
standard input, discovers the served model ID, requires HTTP 200, and validates
chat text or numeric embeddings. It does not configure SQL.
`--ssl-revoke-best-effort` accommodates unavailable lab revocation information;
these scripts do not bypass certificate trust, expiry, or hostname validation.

## 3. Test SQL-to-chat explicitly

```powershell
.\setup\test.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' `
    -DeploymentName 'gpt-oss-20b' -ExternalIPAddress '<your-gateway-ip>'
```

The legacy default is `phi-35-mini`; select it only if you have that deployment.
The test enables `external rest endpoint enabled`, creates a master key,
credential, and helper procedures in `tempdb`, then invokes the model through
`sys.sp_invoke_external_rest_endpoint`. Objects in `tempdb` disappear on SQL
restart. With `-Database`, the chosen database must exist and objects persist.
Use `-ServerInstance 'localhost\InstanceName'` for a named instance.
This is not application database initialization.

## Optional ingress restoration

[caldova-model-ingress.yaml](caldova-model-ingress.yaml) defines a
demo-managed external HTTPS Gateway plus chat and embedding HTTPRoutes. It
does not expose the operator administration API or modify model deployments.
Update its documentation IP and MetalLB name **and** the matching constants
in [Restore-FoundryIngress.ps1](Restore-FoundryIngress.ps1) first.

```powershell
.\setup\Restore-FoundryIngress.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' -WhatIf
.\setup\Restore-FoundryIngress.ps1 -KubeconfigPath 'C:\secure\caldova-admin.kubeconfig' -VerifyInference
```

Even `-WhatIf` contacts the cluster and performs server-side manifest
validation. Preflight checks ready models, service ports, backend TLS, existing
certificate validity/IP SAN, pool membership, IP conflicts, and resource
ownership. Apply verifies programmed routes and unchanged pod IDs/restart
counts. It does not renew certificates or configure SQL.

To remove **only these demo-managed ingress objects**, after confirming the
manifest names belong to this lab:

```powershell
kubectl --kubeconfig C:\secure\caldova-admin.kubeconfig delete -f .\setup\caldova-model-ingress.yaml
```

Do not delete shared model/operator resources.

## Credential initialization and optional Arc proxy

[Initialize-FoundrySqlTests.ps1](Initialize-FoundrySqlTests.ps1) creates the
isolated `CaldovaFoundryModelTests` database and encrypted model credentials.
With `-ApplicationVectorSearch`, it instead prepares the embedding credential
and preview setting in the existing application database. Its gateway IP is a
constant: replace the example before running. See
[isolated tests](../database/model-tests/README.md) and
[database deployment](../database/README.md).

[Connect-AksArc.ps1](Connect-AksArc.ps1) is an optional Azure CLI proxy path;
normal setup uses the protected kubeconfig directly. All Azure target values
must be supplied explicitly:

```powershell
.\setup\Connect-AksArc.ps1 -ClusterName '<your-arc-cluster>' `
    -ResourceGroup '<your-resource-group>' -Subscription '<your-subscription-id>' `
    -Tenant '<your-tenant-id>' -ValidateOnly
```

It may install connectedk8s, signs in unless `-SkipLogin` is supplied, selects
the subscription, and checks access. Omit `-ValidateOnly` to start the
long-running proxy in a dedicated terminal.

## Troubleshooting

Stop on a nonzero exit code. First distinguish DNS/routing, certificate trust,
authenticated inference, and SQL invocation; success in one layer does not
prove the next. Inspect full errors privately. Never solve a TLS failure by
adding `--insecure` or publish a kubeconfig/API key in an issue.
