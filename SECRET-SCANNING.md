# Secret checks before publishing

This is a public repository. Review copied private-repository content before
staging it. Never commit real passwords, tokens, private keys, private datasets,
or confidential documentation, even when used in a demo.

## Enable local guards

Install Gitleaks 8.30.1 or later. On Windows:

```powershell
winget install --id Gitleaks.Gitleaks --exact
& .\scripts\install-secret-hooks.ps1
```

Run the installer in each clone. In Git Bash or on Linux/macOS, use
`sh scripts/install-secret-hooks.sh`. The PowerShell installer locates Git's
shell even when `sh` is not on PowerShell's PATH. The installer
sets this checkout's `core.hooksPath` to `.githooks`; it does not change global
Git configuration or replace a different configured hooks directory.

* **Before commit:** scan staged additions, including partially staged files.
* **Before push:** scan every commit being sent for each pushed ref, including
  secrets added and removed in separate commits. New remote branches and tags
  scan all reachable history. Deleted refs need no scan.
* Missing Gitleaks, scan errors, detected secrets, unavailable remote base
  commits, and refs that do not resolve to commits block the operation.
  Fetch the destination remote when the hook requests it.
* Findings are redacted. Default Gitleaks rules are extended with database
  password, SQL credential, password-variable, container-password, and attached
  or separated `sqlcmd -P` checks. Inline `gitleaks:allow`
  comments do not bypass these hooks.

To check staged changes without committing (Git Bash):

```powershell
sh scripts/check-secrets.sh staged
```

To test the guards in an isolated temporary Git repository (PowerShell):

```powershell
& .\scripts\test-secret-hooks.ps1
& .\scripts\test-demo-credentials.ps1
```

The second suite uses mocks, not live SQL, Docker, or Kubernetes services.

To inspect copied or untracked content before staging:

```powershell
gitleaks dir --config .gitleaks.toml --redact=100 --no-banner --ignore-gitleaks-allow --max-archive-depth 3 examples
```

Replace hard-coded demo credentials with environment variables, interactive
prompts, or unmistakable `<PLACEHOLDER>` values. Do not blanket-allowlist copied
folders or baseline findings merely to make a scan pass. If a real credential
was committed, revoke or rotate it; deleting it in a later commit is not enough.

## Supplying demo credentials

The remediated examples take credentials at runtime, not from saved literals.
Use disposable lab credentials and a private terminal; never paste values into
tracked scripts, notebook cells, command history, screenshots, or chat.

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

`-MaskInput` requires PowerShell 7. Runtime environment variables are plaintext
in process memory, not a secret vault. Limit access to the shell, containers,
and orchestration metadata. Docker launch scripts forward the value as
`MSSQL_SA_PASSWORD`; `docker exec` forwards `SQLCMDPASSWORD`. Kubernetes secret
creation streams the value through standard input; Kubernetes Secret base64
encoding is not encryption. Configure cluster access and encryption separately.
Replication Compose requires the same `SQLCMDPASSWORD` for both lab containers;
its publisher derives a separate SQL-escaped value for replication setup.

SQL scripts whose header names SQLCMD variables require SQLCMD mode. Populate
only the variables required by the selected script in its environment:
`MasterKeyPassword`, `CertificatePassword`, `SqlLoginPassword`, `ExternalSecret`,
or `StorageSasToken`. Prompt as above, but SQL-escape apostrophes by doubling
them before assigning these substitution variables:

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
textual: do not use untrusted input or multiline values. Do not pass secrets
with command-line `-P` or `-v`, print expanded SQL, or commit a `:setvar` value.
Missing or unresolved substitutions reject the protected setup; reconnect if
an interrupted script leaves `NOEXEC` enabled.

The affected PolyBase and SQL By Example notebooks have cleared outputs.
Run their companion setup SQL in SQLCMD mode with private inputs, then run
query cells; notebook SQL kernels may not expand SQLCMD variables.

Azure SQL AI and Ward General embedding setup generate a random master-key
password inside SQL to preserve their passwordless, non-SQLCMD workflows.
It is not printed or retained for recovery. These are disposable demos; for a
durable database, arrange approved key backup/recovery before using this setup.

The NIM hostname-switch helper reads `PFX_PASSWORD` and `MASTER_KEY_PASSWORD`
from the environment instead of providing bundled defaults. Supply the PFX
password privately before running it. Generated private keys and PFX files
must remain local.

The book samples use the same runtime-input conventions. Elastic Jobs
`createcreds.sql` additionally requires `MasterCredentialSecret` and
`JobCredentialSecret`, SQL-escaped to match the separately created `mastercred`
and `jobcred` login passwords. Set `SqlLoginPassword` to the appropriate private
login password when running each login-creation script.

The SQL on Linux book's `createwwi` launchers now accept only the server name as
an argument. Supply the administrator password through `SQLCMDPASSWORD`, and
the new `sqllinux` login's raw password through `SQLLINUXPASSWORD`. Bash derives
`SqlLoginPassword`; the Windows launcher requires that separate SQL-escaped
environment input to match `SQLLINUXPASSWORD`. Neither launcher accepts password
arguments. Book shell examples using `sudo docker run` preserve only the
`MSSQL_SA_PASSWORD` environment variable needed for startup; do not enable shell
tracing or log container environment metadata.

## Limits

Local hooks are not a server-side security boundary: they can be disabled or
bypassed, and Git does not automatically install them in new clones. Configure
GitHub secret scanning and push protection separately for server-side coverage
of supported secret types. Do not use `--no-verify` to bypass a failing check.

Automated secret detection cannot certify that content is safe to publish.
Git diff scanning does not inspect binary file contents (including BACPACs,
database backups, images, and archives). Directory mode can inspect supported
archives, but not every binary format or encrypted file. Independently review
database packages and all private, personal, licensed, or confidential material.
Existing history is not checked at commit time; a new remote ref may therefore
be blocked by historical findings requiring review. No automatic baseline or
secret allowlist is installed.
