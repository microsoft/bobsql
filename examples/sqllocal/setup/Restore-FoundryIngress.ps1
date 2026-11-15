[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$KubeconfigPath = 'C:\setup\caldova-admin.kubeconfig',
    [switch]$VerifyInference
)

$ErrorActionPreference = 'Stop'
$namespace = 'foundry-local-operator'
$gatewayName = 'caldova-external-gateway'
$externalIPAddress = '192.0.2.10'
$manifestPath = Join-Path $PSScriptRoot 'caldova-model-ingress.yaml'
$kubectl = Get-Command kubectl -ErrorAction Stop

if (-not (Test-Path -LiteralPath $KubeconfigPath -PathType Leaf)) {
    throw "Protected kubeconfig was not found at '$KubeconfigPath'."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Ingress manifest was not found at '$manifestPath'."
}

function Invoke-Kubectl {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & $kubectl.Source --kubeconfig $KubeconfigPath --request-timeout=15s @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl failed: $($Arguments -join ' ')"
    }
    return $output
}

function Get-KubernetesResource {
    param([Parameter(Mandatory)][string[]]$Arguments)

    return (Invoke-Kubectl -Arguments ($Arguments + @('--output', 'json'))) | ConvertFrom-Json
}

function Get-ModelPodSnapshot {
    $pods = Get-KubernetesResource -Arguments @(
        'get', 'pods', '--namespace', $namespace,
        '--selector', 'app.kubernetes.io/name in (gpt-oss-20b,nemotron-3-embed-1b-bf16)'
    )
    if (@($pods.items).Count -eq 0) {
        throw 'No model pods were found.'
    }
    return @($pods.items | ForEach-Object {
        '{0}|{1}|{2}' -f $_.metadata.name, $_.metadata.uid,
            (@($_.status.containerStatuses.restartCount) -join ',')
    } | Sort-Object)
}

Write-Host 'Checking existing cluster resources through the protected kubeconfig; no Azure sign-in is used.'

$gatewayClass = Get-KubernetesResource -Arguments @('get', 'gatewayclasses.gateway.networking.k8s.io', 'istio')
if ($gatewayClass.spec.controllerName -ne 'istio.io/gateway-controller' -or
    -not @($gatewayClass.status.conditions | Where-Object {
        $_.type -eq 'Accepted' -and $_.status -eq 'True'
    }).Count) {
    throw 'The istio GatewayClass is not accepted by the expected controller.'
}

$pool = Get-KubernetesResource -Arguments @(
    'get', 'ipaddresspools.metallb.io', 'caldova-model-lb', '--namespace', 'kube-system'
)
if ("$externalIPAddress/32" -notin @($pool.spec.addresses)) {
    throw "The expected MetalLB pool does not contain $externalIPAddress/32. No changes were made."
}
$advertisement = Get-KubernetesResource -Arguments @(
    'get', 'l2advertisements.metallb.io', 'caldova-model-lb', '--namespace', 'kube-system'
)
if (@($advertisement.spec.ipAddressPools).Count -gt 0 -and
    'caldova-model-lb' -notin @($advertisement.spec.ipAddressPools)) {
    throw 'The MetalLB L2 advertisement does not cover caldova-model-lb.'
}
$services = Get-KubernetesResource -Arguments @('get', 'services', '--all-namespaces')
foreach ($service in $services.items) {
    if ($externalIPAddress -in @($service.status.loadBalancer.ingress.ip) -and
        ($service.metadata.namespace -ne $namespace -or
            $service.metadata.name -ne "$gatewayName-istio")) {
        throw "$externalIPAddress is already assigned to $($service.metadata.namespace)/$($service.metadata.name). No changes were made."
    }
}

foreach ($modelName in @('gpt-oss-20b', 'nemotron-3-embed-1b-bf16')) {
    $model = Get-KubernetesResource -Arguments @(
        'get', 'modeldeployments.foundrylocal.azure.com', $modelName, '--namespace', $namespace
    )
    if ($model.status.state -ne 'Running' -or $model.status.deploymentReady -ne $true) {
        throw "ModelDeployment '$modelName' is not Running/Ready."
    }
    $service = Get-KubernetesResource -Arguments @('get', 'service', $modelName, '--namespace', $namespace)
    if (5000 -notin @($service.spec.ports.port)) {
        throw "Model Service '$modelName' does not expose the expected port 5000."
    }
    $policy = Get-KubernetesResource -Arguments @(
        'get', 'backendtlspolicies.gateway.networking.k8s.io', "$modelName-backend-tls",
        '--namespace', $namespace
    )
    if ($modelName -notin @($policy.spec.targetRefs.name) -or
        $policy.spec.validation.hostname -ne "$modelName.$namespace.svc.cluster.local" -or
        'foundry-local-operator-ca-bundle' -notin @($policy.spec.validation.caCertificateRefs.name)) {
        throw "Model '$modelName' does not have the expected backend TLS configuration."
    }
}

$encodedCertificate = Invoke-Kubectl -Arguments @(
    'get', 'secret', 'inference-external-gateway-ip-tls', '--namespace', $namespace,
    '--output', 'jsonpath={.data.tls\.crt}'
)
$pem = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedCertificate))
$match = [regex]::Match($pem, '(?s)-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----')
if (-not $match.Success) {
    throw 'The existing public Gateway certificate is not PEM encoded.'
}
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
)
try {
    $now = Get-Date
    if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now) {
        throw 'The existing Gateway certificate is not currently valid. Renew it before restoring ingress.'
    }
    $san = @($certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } |
        ForEach-Object { $_.Format($true) }) -join "`n"
    if ($san -notmatch ('(?<![0-9.])' + [regex]::Escape($externalIPAddress) + '(?![0-9.])')) {
        throw "The Gateway certificate does not cover $externalIPAddress."
    }
    Write-Host "Existing Gateway certificate expires: $($certificate.NotAfter.ToString('o'))"
}
finally {
    $certificate.Dispose()
}

$existing = Get-KubernetesResource -Arguments @('get', '--filename', $manifestPath, '--ignore-not-found')
foreach ($resource in @($existing.items)) {
    if ($resource.metadata.labels.'app.kubernetes.io/part-of' -ne 'caldova-regional-care') {
        throw "Refusing to overwrite non-demo resource '$($resource.metadata.name)'."
    }
}
$baseline = Get-ModelPodSnapshot
Invoke-Kubectl -Arguments @('apply', '--dry-run=server', '--filename', $manifestPath) | Write-Host

if (-not $PSCmdlet.ShouldProcess("$namespace/$gatewayName", 'Apply the demo-managed HTTPS Gateway and two model routes')) {
    Write-Host 'Preflight and server-side manifest validation completed; no resources were changed.'
    return
}

Invoke-Kubectl -Arguments @('apply', '--filename', $manifestPath) | Write-Host
& $kubectl.Source --kubeconfig $KubeconfigPath wait `
    --namespace $namespace `
    --for=condition=Programmed "gateways.gateway.networking.k8s.io/$gatewayName" `
    --timeout=120s
if ($LASTEXITCODE -ne 0) {
    throw 'The external Gateway was applied but did not become Programmed within 120 seconds.'
}

$service = Get-KubernetesResource -Arguments @(
    'get', 'service', "$gatewayName-istio", '--namespace', $namespace
)
if ($service.spec.type -ne 'LoadBalancer' -or
    $externalIPAddress -notin @($service.status.loadBalancer.ingress.ip)) {
    throw 'The Gateway was applied but does not have the expected LoadBalancer IP.'
}
foreach ($routeName in @('caldova-gpt-oss-20b', 'caldova-nemotron-3-embed-1b-bf16')) {
    $route = Get-KubernetesResource -Arguments @(
        'get', 'httproutes.gateway.networking.k8s.io', $routeName, '--namespace', $namespace
    )
    $parents = @($route.status.parents | Where-Object { $_.parentRef.name -eq $gatewayName })
    if ($parents.Count -ne 1) {
        throw "Route '$routeName' is not attached to the expected Gateway."
    }
    foreach ($conditionType in @('Accepted', 'ResolvedRefs')) {
        if (-not @($parents[0].conditions | Where-Object {
            $_.type -eq $conditionType -and $_.status -eq 'True' -and
            $_.observedGeneration -eq $route.metadata.generation
        }).Count) {
            throw "Route '$routeName' has not reached $conditionType for its current generation."
        }
    }
}
if (Compare-Object -ReferenceObject $baseline -DifferenceObject (Get-ModelPodSnapshot)) {
    throw 'Model pod identity or restart counts changed during the operation. Inspect the cluster before proceeding.'
}

& (Join-Path $PSScriptRoot 'Test-FoundryHttps.ps1') `
    -Endpoint "https://$externalIPAddress/gpt-oss-20b/v1/chat/completions"

if ($VerifyInference) {
    foreach ($mode in @('Chat', 'Embedding')) {
        & (Join-Path $PSScriptRoot 'Test-FoundryModel.ps1') `
            -Mode $mode -KubeconfigPath $KubeconfigPath
    }
}
Write-Host 'External ingress verified. Model pods were unchanged; SQL configuration was not modified.' -ForegroundColor Green
