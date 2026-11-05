# Secret scanning and demo credentials

Never commit real passwords, tokens, private keys, private datasets, or
confidential documentation. Supply demo credentials at runtime.

## Enable local guards

Install Gitleaks 8.30.1 or later. On Windows:

```powershell
winget install --id Gitleaks.Gitleaks --exact
& .\scripts\install-secret-hooks.ps1
```

Run the installer in each clone. In Git Bash or on Linux/macOS, use
`sh scripts/install-secret-hooks.sh`. It sets this checkout's `core.hooksPath`
to `.githooks`, without changing global Git configuration or replacing a
different configured hooks directory.

* **Before commit:** scan staged additions, including partially staged files.
* **Before push:** scan every commit being sent for each pushed ref, including
  secrets added and removed in separate commits. New remote branches and tags
  scan all reachable history. Deleted refs need no scan.
* Missing Gitleaks, scan errors, or detected secrets block the operation.
  Pushes also require available base commits and refs that resolve to commits;
  fetch the destination remote when requested.
* Findings are redacted. Rules include SQL and container credentials.
  Inline `gitleaks:allow` comments do not bypass the hooks.

To check staged changes without committing (Git Bash):

```powershell
sh scripts/check-secrets.sh staged
```

To run the guard and credential-handling tests (PowerShell):

```powershell
& .\scripts\test-secret-hooks.ps1
& .\scripts\test-demo-credentials.ps1
```

Tests use temporary fixtures; credential tests mock SQL, Docker, and Kubernetes.

To scan the examples directory, including untracked files:

```powershell
gitleaks dir --config .gitleaks.toml --redact=100 --no-banner --ignore-gitleaks-allow --max-archive-depth 3 examples
```

Review findings rather than blanket-allowlisting folders or baselining them to
make a scan pass. If a real credential was committed, revoke or rotate it;
deleting it in a later commit is not enough.

## Supplying demo credentials

Use disposable lab credentials. Keep them out of tracked scripts, notebook
cells, command history, screenshots, and chat.

For SQL authentication, populate `SQLCMDPASSWORD` in the same shell that runs
the demo. In PowerShell, prompt without echoing the value:

```powershell
$env:SQLCMDPASSWORD = Read-Host 'Private lab SQL password' -MaskInput
try {
    # Run the selected demo here, in this shell.
}
finally {
    Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:\MSSQL_SA_PASSWORD -ErrorAction SilentlyContinue
}
```

`-MaskInput` requires PowerShell 7. Environment variables are not a secret vault;
limit access to processes and container metadata. Kubernetes Secret base64
encoding is not encryption. Replication Compose requires the same
`SQLCMDPASSWORD` for both lab containers.

For scripts that name SQLCMD variables in their headers, enable SQLCMD mode and
set the required environment variables. SQL-escape apostrophes in substitution
values by doubling them:

```powershell
$env:MasterKeyPassword = (Read-Host 'Private master-key password' -MaskInput).Replace("'", "''")
try {
    # Invoke sqlcmd with -b and the selected script's -i path; do not use -e.
}
finally {
    Remove-Item Env:\MasterKeyPassword -ErrorAction SilentlyContinue
}
```

Keep the authentication `SQLCMDPASSWORD` **unescaped**. SQLCMD substitution is
textual: do not use untrusted or multiline values. Do not pass secrets with
command-line `-P` or `-v`, print expanded SQL, or save secret `:setvar` values.
Reconnect if an interrupted setup script leaves `NOEXEC` enabled.

### Demo-specific inputs

* **PolyBase and SQL By Example notebooks:** run companion setup SQL in SQLCMD
  mode first; notebook kernels may not expand SQLCMD variables.
* **Azure SQL AI and Ward General:** embedding setup generates a master-key
  password that is not retained for recovery. Arrange key backup/recovery before
  using this disposable-demo setup for a durable database.
* **NIM hostname-switch helper:** set `PFX_PASSWORD` and `MASTER_KEY_PASSWORD`.
  Keep generated private keys and PFX files local.
* **Elastic Jobs:** SQL-escape `MasterCredentialSecret` and `JobCredentialSecret`
  to match the separately created `mastercred` and `jobcred` login passwords.
  Use the appropriate `SqlLoginPassword` for each login-creation script.
* **SQL on Linux book:** `createwwi` accepts only the server name. Set raw
  `SQLCMDPASSWORD` and `SQLLINUXPASSWORD`; Windows also requires the matching
  SQL-escaped `SqlLoginPassword` (Bash derives it).
* **Container demos:** do not enable shell tracing or log container environment
  metadata. Book examples using `sudo docker run` preserve only
  `MSSQL_SA_PASSWORD`.

## Limits

Local hooks can be bypassed and must be installed per clone. Configure GitHub
secret scanning and push protection separately for supported secret types.
Do not bypass failing checks with `--no-verify`.

Passing a scan does not certify that content is safe to publish. Git diff scans
do not inspect binary contents; directory scans support some archives, but not
all binary or encrypted formats. Review database packages and sensitive or
licensed material independently. Commit checks do not scan existing history;
new remote refs may be blocked by historical findings.
