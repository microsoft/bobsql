# switch-hostname.ps1
# Switches all NIM AKS scripts/config from the current hostname to a new one.
# Regenerates TLS cert, updates k8s secrets/ingress, hosts file, SQL Server cert/credential,
# and all script files.
#
# Usage: .\switch-hostname.ps1 -NewHostname nim-aks.local
#        .\switch-hostname.ps1 -NewHostname nim-aks.local -IngressIP <aks-ingress-ip>
param(
    [Parameter(Mandatory)]
    [string]$NewHostname,

    [string]$IngressIP,

    [string]$OldHostname = 'aks-nvidianim.westus2.cloudapp.azure.com',

    [string]$PfxPassword = 'NimCert123!',

    [string]$Database = 'FoundryLocalTest',

    [string]$MasterKeyPassword = 'N1mAks2025!SecureP@ss#99'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$k8sDir = Join-Path $scriptDir 'k8s'
$sqlDir = Join-Path $scriptDir 'sql'

# Ensure kubectl is on PATH
$env:PATH += ";$HOME\.azure-kubectl;$HOME\.azure-kubelogin"

# Auto-detect ingress IP from cluster if not provided
if (-not $IngressIP) {
    $IngressIP = kubectl get ingress nim-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if (-not $IngressIP) {
        Write-Error "Could not detect ingress IP. Provide -IngressIP parameter."
        return
    }
    Write-Host "Auto-detected ingress IP: $IngressIP" -ForegroundColor Yellow
}

Write-Host "=== Switching hostname: $OldHostname -> $NewHostname ===" -ForegroundColor Cyan
Write-Host "Ingress IP: $IngressIP" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# 1. Generate new TLS certificate
# ============================================================
Write-Host "[1/8] Generating TLS certificate for $NewHostname ..." -ForegroundColor Yellow

# Find openssl (Git ships one)
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    $openssl = Get-ChildItem "C:\Program Files\Git" -Recurse -Filter "openssl.exe" -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -like '*\usr\bin\*' } | Select-Object -First 1
    if ($openssl) { $openssl = $openssl.FullName } else {
        Write-Error "openssl not found. Install Git for Windows or add openssl to PATH."
        return
    }
} else {
    $openssl = $openssl.Source
}

# Find openssl config
$opensslConf = Get-ChildItem "C:\Program Files\Git" -Recurse -Filter "openssl.cnf" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($opensslConf) {
    $env:OPENSSL_CONF = $opensslConf.FullName
    Write-Host "  Using OpenSSL config: $($opensslConf.FullName)" -ForegroundColor DarkGray
}

$tlsKey  = Join-Path $k8sDir 'tls.key'
$tlsCrt  = Join-Path $k8sDir 'tls.crt'
$tlsPfx  = Join-Path $k8sDir 'tls.pfx'

& $openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
    -keyout $tlsKey -out $tlsCrt `
    -subj "/CN=$NewHostname" `
    -addext "subjectAltName=DNS:$NewHostname"

if ($LASTEXITCODE -ne 0) { Write-Error "Failed to generate certificate"; return }

# Export PFX for SQL Server
& $openssl pkcs12 -export -out $tlsPfx -inkey $tlsKey -in $tlsCrt -passout "pass:$PfxPassword"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to export PFX"; return }

# Get thumbprint for verification
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tlsCrt)
$thumbprint = $cert.Thumbprint
Write-Host "  Certificate generated: CN=$NewHostname, Thumbprint=$thumbprint" -ForegroundColor Green

# ============================================================
# 2. Update k8s TLS secrets
# ============================================================
Write-Host "[2/8] Updating k8s TLS secrets ..." -ForegroundColor Yellow

kubectl create secret tls nim-tls `
    --cert=$tlsCrt --key=$tlsKey `
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls nim-tls `
    --cert=$tlsCrt --key=$tlsKey `
    -n app-routing-system `
    --dry-run=client -o yaml | kubectl apply -n app-routing-system -f -

Write-Host "  TLS secrets updated in default + app-routing-system" -ForegroundColor Green

# ============================================================
# 3. Update ingress.yaml and apply
# ============================================================
Write-Host "[3/8] Updating ingress for $NewHostname ..." -ForegroundColor Yellow

$ingressFile = Join-Path $k8sDir 'ingress.yaml'
$ingressContent = Get-Content $ingressFile -Raw
$ingressContent = $ingressContent -replace [regex]::Escape($OldHostname), $NewHostname
Set-Content $ingressFile -Value $ingressContent -NoNewline

kubectl apply -f $ingressFile
Write-Host "  Ingress applied with host=$NewHostname" -ForegroundColor Green

# ============================================================
# 4. Add hosts file entry
# ============================================================
Write-Host "[4/8] Updating hosts file ..." -ForegroundColor Yellow

$entry = "$IngressIP  $NewHostname"

# Hosts file requires admin — use elevated PowerShell
$hostsCmd = @"
if (-not (Select-String -Path 'C:\Windows\System32\drivers\etc\hosts' -Pattern '$([regex]::Escape($NewHostname))' -Quiet)) {
    Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '$entry'
}
"@
Start-Process powershell -Verb RunAs -ArgumentList "-Command", $hostsCmd -Wait
Write-Host "  Added: $entry" -ForegroundColor Green

# ============================================================
# 5. Import cert to Windows Trusted Root
# ============================================================
Write-Host "[5/8] Importing certificate to Windows Trusted Root ..." -ForegroundColor Yellow

# Trusted Root store requires admin — use elevated PowerShell
Start-Process powershell -Verb RunAs -ArgumentList "-Command", "Import-Certificate -FilePath '$tlsCrt' -CertStoreLocation 'Cert:\LocalMachine\Root'" -Wait
Write-Host "  Certificate added to Trusted Root" -ForegroundColor Green

# ============================================================
# 6. Update SQL Server cert + credential
# ============================================================
Write-Host "[6/8] Updating SQL Server certificate and credential ..." -ForegroundColor Yellow

# Convert PEM to DER for SQL Server (it can't import PEM .crt directly)
$tlsCer = Join-Path $k8sDir 'tls.cer'
& $openssl x509 -in $tlsCrt -outform DER -out $tlsCer
if ($LASTEXITCODE -ne 0) { Write-Warning "DER conversion failed"; return }

$sqlSetup = @"
USE $Database;
GO

-- 1. Drop external model first (it references the credential)
IF EXISTS (SELECT * FROM sys.external_models WHERE name = 'NIMEmbeddingModel')
    DROP EXTERNAL MODEL NIMEmbeddingModel;
GO

-- 2. Drop old credentials
IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://$OldHostname')
    DROP DATABASE SCOPED CREDENTIAL [https://$OldHostname];
GO

IF EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'https://$NewHostname')
    DROP DATABASE SCOPED CREDENTIAL [https://$NewHostname];
GO

-- 3. Drop old cert
IF EXISTS (SELECT * FROM sys.certificates WHERE name = 'nimcert')
    DROP CERTIFICATE nimcert;
GO

-- 4. Create cert from DER file
CREATE CERTIFICATE nimcert
    FROM FILE = '$tlsCer';
GO

-- 5. Recreate external model with new hostname (no credential needed — NGINX handles Content-Type)
CREATE EXTERNAL MODEL NIMEmbeddingModel
WITH (
    LOCATION = 'https://$NewHostname/v1/embeddings',
    API_FORMAT = 'OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'nvidia/nv-embedqa-e5-v5-query'
);
GO

-- 6. Verify
SELECT name, thumbprint FROM sys.certificates WHERE name = 'nimcert';
SELECT name, model, location FROM sys.external_models WHERE name = 'NIMEmbeddingModel';
GO
"@

$sqlTempFile = Join-Path $env:TEMP "nim-switch-cred.sql"
Set-Content $sqlTempFile -Value $sqlSetup

$sqlsim = Join-Path $scriptDir '..\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe'
if (Test-Path $sqlsim) {
    & $sqlsim -S localhost -d $Database -E -i $sqlTempFile
    if ($LASTEXITCODE -ne 0) { Write-Warning "SQL credential update had errors — check output above" }
    else { Write-Host "  SQL cert + credential updated" -ForegroundColor Green }
} else {
    Write-Warning "sqlsim not found at $sqlsim — run the SQL manually:`n$sqlSetup"
}

Remove-Item $sqlTempFile -ErrorAction SilentlyContinue

# ============================================================
# 7. Update SQL script files
# ============================================================
Write-Host "[7/8] Updating SQL and PowerShell scripts ..." -ForegroundColor Yellow

$filesToUpdate = @(
    (Join-Path $sqlDir '01_create_external_model.sql'),
    (Join-Path $sqlDir '02_test_embedding.sql'),
    (Join-Path $sqlDir '04_test_chat_completion.sql'),
    (Join-Path $scriptDir 'deploy-nim.ps1'),
    (Join-Path $scriptDir 'test-embedding.ps1'),
    (Join-Path $scriptDir 'test-chat.ps1'),
    (Join-Path $scriptDir 'README.md')
)

foreach ($f in $filesToUpdate) {
    if (Test-Path $f) {
        $content = Get-Content $f -Raw
        if ($content -match [regex]::Escape($OldHostname)) {
            $content = $content -replace [regex]::Escape($OldHostname), $NewHostname
            Set-Content $f -Value $content -NoNewline
            Write-Host "  Updated: $(Split-Path $f -Leaf)" -ForegroundColor DarkGray
        }
    }
}

# ============================================================
# 8. Update PowerShell test scripts to use HTTPS + hostname
# ============================================================
Write-Host "[8/8] Updating test scripts for HTTPS ..." -ForegroundColor Yellow

# test-embedding.ps1 — switch from http://$IngressIP to https://$NewHostname
$testEmbed = Join-Path $scriptDir 'test-embedding.ps1'
if (Test-Path $testEmbed) {
    $content = Get-Content $testEmbed -Raw
    # Replace the URL pattern to use hostname with HTTPS and -SkipCertificateCheck
    $content = $content -replace 'http://\$IngressIP', "https://$NewHostname"
    $content = $content -replace 'http://\$\{IngressIP\}', "https://$NewHostname"
    Set-Content $testEmbed -Value $content -NoNewline
    Write-Host "  test-embedding.ps1 updated to HTTPS" -ForegroundColor DarkGray
}

# test-chat.ps1 — same
$testChat = Join-Path $scriptDir 'test-chat.ps1'
if (Test-Path $testChat) {
    $content = Get-Content $testChat -Raw
    $content = $content -replace 'http://\$IngressIP', "https://$NewHostname"
    $content = $content -replace 'http://\$\{IngressIP\}', "https://$NewHostname"
    Set-Content $testChat -Value $content -NoNewline
    Write-Host "  test-chat.ps1 updated to HTTPS" -ForegroundColor DarkGray
}

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "=== Hostname switch complete ===" -ForegroundColor Green
Write-Host "Old: $OldHostname"
Write-Host "New: $NewHostname -> $IngressIP"
Write-Host "Cert thumbprint: $thumbprint"
Write-Host ""
Write-Host "Test with:" -ForegroundColor Cyan
Write-Host "  sqlsim -S localhost -d $Database -E -i $sqlDir\02_test_embedding.sql"
Write-Host "  sqlsim -S localhost -d $Database -E -i $sqlDir\04_test_chat_completion.sql"
