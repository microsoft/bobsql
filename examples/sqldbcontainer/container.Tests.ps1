[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'The fake Docker command shares test state across invoked script scopes; AfterEach removes it.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fixed non-secret test fixture, never passed to real Docker.')]
[CmdletBinding()]
param()

Describe 'Azure SQL container bootstrap' {
    BeforeAll {
        $script:project = $PSScriptRoot

# Substitute Docker at the command boundary; tests never contact a real engine.
function docker {
    $state = $global:SqlDbContainerTest
    $state.DockerCalls += ,@($args)
    $global:LASTEXITCODE = 0
    if ($args[0] -eq $state.FailCommand) {
        $global:LASTEXITCODE = 1
        return 'Simulated Docker failure'
    }
    switch ($args[0]) {
        'info' { $state.Engine | ConvertTo-Json -Compress }
        'context' { 'test-context' }
        'ps' { if ($state.Container -and -not $state.Renamed) { 'test-container-id' } }
        'image' { 'sha256:test-image' }
        'inspect' {
            if ($args -contains '--format') {
                if ($state.StoppedDuringProbe) { 'exited' } else { 'running' }
            } else {
                ConvertTo-Json -InputObject @($state.Container) -Depth 8 -Compress
            }
        }
        'run' {
            $state.PasswordDuringRun = $env:MSSQL_SA_PASSWORD
            'test-container-id'
        }
        'start' { 'sqldbcontainer' }
        'stop' { 'sqldbcontainer' }
        'rename' { $state.Renamed = -not $state.Renamed }
        'exec' {
            if ($args[4] -like 'if *') {
                '/opt/mssql-tools18/bin/sqlcmd'
            } elseif ($state.FailProbe) {
                $global:LASTEXITCODE = 1
                $state.StoppedDuringProbe = $true
                'Simulated SQL login failure'
            } else {
                '1'
            }
        }
        'login' { $input | Out-Null; 'Login Succeeded' }
        'pull' { 'Image pulled' }
        default { throw "Unexpected Docker command: $($args[0])" }
    }
}
    }

    BeforeEach {
        $global:SqlDbContainerTest = @{
            DockerCalls = @()
            Engine = @{
                OSType = 'linux'; Architecture = 'x86_64'; ServerVersion = 'test'
                NCPU = 4; MemTotal = 8GB
            }
            Container = $null
            FailCommand = ''
            FailProbe = $false
            StoppedDuringProbe = $false
            PasswordDuringRun = $null
            Renamed = $false
            OllamaUnavailable = $false
            Models = @(@{ name = 'nomic-embed-text:v1.5'; digest = 'test-digest' })
            Capabilities = @('embedding')
            Embeddings = ,@(0.1, 0.2, 0.3)
        }
        Mock Invoke-RestMethod {
            if ($global:SqlDbContainerTest.OllamaUnavailable) { throw 'Simulated Ollama connection failure' }
            switch -Wildcard ($Uri) {
                '*/api/tags' { @{ models = $global:SqlDbContainerTest.Models } }
                '*/api/show' { @{ capabilities = $global:SqlDbContainerTest.Capabilities } }
                '*/api/embed' { @{ embeddings = $global:SqlDbContainerTest.Embeddings } }
                default { throw "Unexpected Ollama endpoint: $Uri" }
            }
        }
        $script:TestPassword = ConvertTo-SecureString 'Unit-test-only-Password!42' -AsPlainText -Force
    }

    AfterEach {
        Remove-Variable SqlDbContainerTest -Scope Global
    }

    It 'passes a reachable Linux x64 engine without changing it' {
        & "$project\preflight.ps1"
        ($global:SqlDbContainerTest.DockerCalls | ForEach-Object { $_[0] }) -join ',' | Should -Be 'info,context'
    }

    It 'generates an embedding and keeps the model loaded instead of checking only its name' {
        & "$project\preflight.ps1"
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*/api/embed' -and
            ($Body | ConvertFrom-Json).model -eq 'nomic-embed-text:v1.5' -and
            ($Body | ConvertFrom-Json).keep_alive -eq '30m' -and
            ($Body | ConvertFrom-Json).truncate -eq $false
        }
    }

    It 'allows Docker-only setup without contacting Ollama' {
        & "$project\preflight.ps1" -DockerOnly
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'validates all vectors in a preparation batch and rejects wrong dimensions' {
        . "$project\embedding-helpers.ps1"
        $response = @{ embeddings = @(@(0.1, 0.2, 0.3), @(0.4, 0.5, 0.6)) }
        { Assert-OllamaEmbeddingBatch -Response $response -Count 2 -Dimensions 3 } | Should -Not -Throw
        { Assert-OllamaEmbeddingBatch -Response $response -Count 2 -Dimensions 768 } | Should -Throw '*dimension mismatch*'
        $response.embeddings[1] = @(0.0, 0.0, 0.0)
        { Assert-OllamaEmbeddingBatch -Response $response -Count 2 -Dimensions 3 } | Should -Throw '*zero or invalid*'
    }

    It 'reports an unreachable Ollama service' {
        $global:SqlDbContainerTest.OllamaUnavailable = $true
        { & "$project\preflight.ps1" } | Should -Throw '*Ollama is unreachable*'
    }

    It 'reports the missing model and its explicit setup command' {
        $global:SqlDbContainerTest.Models = @()
        { & "$project\preflight.ps1" } | Should -Throw '*ollama pull nomic-embed-text:v1.5*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Uri -like '*/api/embed' }
    }

    It 'rejects a chat-only model' {
        $global:SqlDbContainerTest.Capabilities = @('completion', 'tools')
        { & "$project\preflight.ps1" } | Should -Throw '*does not advertise embedding capability*'
    }

    It 'rejects malformed or unusable embedding output' -ForEach @(
        @{ Values = @() }
        @{ Values = ,@() }
        @{ Values = @(@(0.1, 0.2), @(0.3, 0.4)) }
        @{ Values = ,@(0.0, 0.0) }
        @{ Values = ,@(0.1, [double]::NaN) }
        @{ Values = ,@(0.1, 'not-a-number') }
    ) {
        $global:SqlDbContainerTest.Embeddings = $Values
        { & "$project\preflight.ps1" } | Should -Throw '*Ollama*'
    }

    It 'fails explicitly when the Docker engine is unavailable' {
        $global:SqlDbContainerTest.FailCommand = 'info'
        { & "$project\preflight.ps1" } | Should -Throw '*Docker engine is unreachable*'
        $global:SqlDbContainerTest.DockerCalls.Count | Should -Be 1
    }

    It 'rejects Windows container mode' {
        $global:SqlDbContainerTest.Engine.OSType = 'windows'
        { & "$project\preflight.ps1" } | Should -Throw '*Select Linux containers*'
    }

    It 'rejects an unsupported engine architecture' {
        $global:SqlDbContainerTest.Engine.Architecture = 'aarch64'
        { & "$project\preflight.ps1" } | Should -Throw '*Linux x64*'
    }

    It 'does not pull or create a new container without EULA acceptance' {
        { & "$project\start-container.ps1" -SkipPull } | Should -Throw '*-AcceptEula*'
        @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('run', 'pull') }).Count | Should -Be 0
    }

    It 'creates persistent storage with standard host port publishing and no password argument' {
        $previous = $env:MSSQL_SA_PASSWORD
        try {
            $env:MSSQL_SA_PASSWORD = 'caller-environment-placeholder'
            & "$project\start-container.ps1" -SkipPull -AcceptEula -SaPassword $script:TestPassword
            $run = @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'run' })[0]
            ($run -contains '14332:1433') | Should -Be $true
            @($run | Where-Object { $_ -eq '--publish' }).Count | Should -Be 1
            ($run -contains 'type=volume,source=sqldbcontainer-public-data,target=/var/opt/mssql') | Should -Be $true
            ($run -contains 'ACCEPT_EULA=Y') | Should -Be $true
            ($run -contains 'MSSQL_SA_PASSWORD') | Should -Be $true
            ($run -join ' ') | Should -Not -Match 'Unit-test-only'
            $global:SqlDbContainerTest.PasswordDuringRun | Should -Be 'Unit-test-only-Password!42'
            $env:MSSQL_SA_PASSWORD | Should -Be 'caller-environment-placeholder'
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'exec' }).Count | Should -Be 2
        } finally {
            [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $previous, 'Process')
        }
    }

    It 'restores the caller environment even when container creation fails' {
        $previous = $env:MSSQL_SA_PASSWORD
        try {
            $env:MSSQL_SA_PASSWORD = 'caller-environment-placeholder'
            $global:SqlDbContainerTest.FailCommand = 'run'
            { & "$project\start-container.ps1" -SkipPull -AcceptEula -SaPassword $script:TestPassword } |
                Should -Throw "*Docker 'run' failed*"
            $env:MSSQL_SA_PASSWORD | Should -Be 'caller-environment-placeholder'
        } finally {
            [Environment]::SetEnvironmentVariable('MSSQL_SA_PASSWORD', $previous, 'Process')
        }
    }

    It 'does not create a container when the requested local image is missing' {
        $global:SqlDbContainerTest.FailCommand = 'image'
        { & "$project\start-container.ps1" -SkipPull -AcceptEula -SaPassword $script:TestPassword } |
            Should -Throw "*Docker 'image' failed*"
        @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'run' }).Count | Should -Be 0
    }

    It 'reports container exit instead of claiming SQL readiness after a failed query' {
        $global:SqlDbContainerTest.FailProbe = $true
        Mock Start-Sleep {}
        { & "$project\start-container.ps1" -SkipPull -AcceptEula -SaPassword $script:TestPassword } |
            Should -Throw "*is 'exited'*"
    }

    Context 'with an existing managed container' {
        BeforeEach {
            $global:SqlDbContainerTest.Container = @{
                Image = 'sha256:test-image'
                Config = @{
                    Image = 'mcr.microsoft.com/mssql/azure-sql-db-server:latest'
                    Labels = @{ 'bwsql.project' = 'sqldbcontainer' }
                    Env = @('ACCEPT_EULA=Y', 'MSSQL_SA_PASSWORD=Unit-test-only-Password!42')
                }
                HostConfig = @{
                    PortBindings = @{ '1433/tcp' = @(@{ HostIp = ''; HostPort = '14332' }) }
                }
                Mounts = @(@{ Destination = '/var/opt/mssql'; Type = 'volume'; Name = 'sqldbcontainer-public-data' })
                State = @{ Status = 'running'; Running = $true }
            }
        }

        It 'reuses a matching running container without recreating it' {
            & "$project\start-container.ps1" -SkipPull
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('run', 'start', 'rm') }).Count | Should -Be 0
        }

        It 'starts a matching stopped container without deleting data' {
            $global:SqlDbContainerTest.Container.State = @{ Status = 'exited'; Running = $false }
            & "$project\start-container.ps1" -SkipPull
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'start' }).Count | Should -Be 1
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('run', 'rm', 'volume') }).Count | Should -Be 0
        }

        It 'warns about a changed image without upgrading an existing container' {
            $global:SqlDbContainerTest.Container.Image = 'sha256:older-image'
            $warnings = @()
            & "$project\start-container.ps1" -SkipPull -WarningVariable warnings -WarningAction SilentlyContinue
            "$warnings" | Should -Match 'no automatic upgrade'
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('run', 'start', 'rm') }).Count | Should -Be 0
        }

        It 'refuses a container with a conflicting host binding' {
            $global:SqlDbContainerTest.Container.HostConfig.PortBindings.'1433/tcp'[0].HostIp = '192.0.2.1'
            { & "$project\start-container.ps1" -SkipPull } | Should -Throw '*does not match*'
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('run', 'start', 'rm') }).Count | Should -Be 0
        }

        It 'refuses to adopt an unrelated container' {
            $global:SqlDbContainerTest.Container.Config.Labels = @{}
            { & "$project\start-container.ps1" -SkipPull } | Should -Throw '*does not match*'
        }

        It 'does not pretend a supplied password changes an existing SQL login' {
            { & "$project\start-container.ps1" -SkipPull -SaPassword $script:TestPassword } |
                Should -Throw '*cannot change an existing SQL login*'
        }

        It 'requires explicit repair before restarting an IPv4-only container' {
            $global:SqlDbContainerTest.Container.HostConfig.PortBindings.'1433/tcp' =
                @(@{ HostIp = '127.0.0.1'; HostPort = '14332' })
            { & "$project\start-container.ps1" -SkipPull } | Should -Throw '*-RepairLocalhost*'
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -in @('stop', 'rename', 'run') }).Count | Should -Be 0
        }

        It 'repairs port publishing while retaining the original container, password, and volume' {
            $global:SqlDbContainerTest.Container.HostConfig.PortBindings.'1433/tcp' =
                @(@{ HostIp = '127.0.0.1'; HostPort = '14332' })
            & "$project\start-container.ps1" -SkipPull -RepairLocalhost
            $calls = $global:SqlDbContainerTest.DockerCalls
            @($calls | Where-Object { $_[0] -eq 'stop' }).Count | Should -Be 1
            @($calls | Where-Object { $_[0] -eq 'rename' }).Count | Should -Be 1
            @($calls | Where-Object { $_[0] -in @('rm', 'volume', 'pull') }).Count | Should -Be 0
            $run = @($calls | Where-Object { $_[0] -eq 'run' })[0]
            ($run -contains '14332:1433') | Should -Be $true
            ($run -contains 'type=volume,source=sqldbcontainer-public-data,target=/var/opt/mssql') | Should -Be $true
            $global:SqlDbContainerTest.PasswordDuringRun | Should -Be 'Unit-test-only-Password!42'
        }

        It 'also repairs a container with both loopback bindings' {
            $global:SqlDbContainerTest.Container.HostConfig.PortBindings.'1433/tcp' = @(
                @{ HostIp = '127.0.0.1'; HostPort = '14332' },
                @{ HostIp = '::1'; HostPort = '14332' }
            )
            & "$project\start-container.ps1" -SkipPull -RepairLocalhost
            $run = @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'run' })[0]
            ($run -contains '14332:1433') | Should -Be $true
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'rename' }).Count | Should -Be 1
        }

        It 'restores the original container when replacement creation fails' {
            $global:SqlDbContainerTest.Container.HostConfig.PortBindings.'1433/tcp' =
                @(@{ HostIp = '127.0.0.1'; HostPort = '14332' })
            $global:SqlDbContainerTest.FailCommand = 'run'
            { & "$project\start-container.ps1" -SkipPull -RepairLocalhost } |
                Should -Throw "*Docker 'run' failed*"
            $calls = $global:SqlDbContainerTest.DockerCalls
            @($calls | Where-Object { $_[0] -eq 'rename' }).Count | Should -Be 2
            @($calls | Where-Object { $_[0] -eq 'start' }).Count | Should -Be 1
            @($calls | Where-Object { $_[0] -in @('rm', 'volume') }).Count | Should -Be 0
            $global:SqlDbContainerTest.Renamed | Should -Be $false
        }
    }

    Context 'registry pull' {
        It 'pulls the public image without registry credentials' {
            & "$project\pull-container.ps1"
            ($global:SqlDbContainerTest.DockerCalls | ForEach-Object { $_[0] }) -join ',' | Should -Be 'info,context,pull'
            $pull = @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'pull' })[0]
            $pull[1] | Should -Be 'mcr.microsoft.com/mssql/azure-sql-db-server:latest'
        }

        It 'rejects images outside the public Azure SQL repository' {
            { & "$project\pull-container.ps1" -Image 'mcr.microsoft.com/mssql/server:latest' } | Should -Throw '*Image must be a tag or digest*'
            @($global:SqlDbContainerTest.DockerCalls | Where-Object { $_[0] -eq 'pull' }).Count | Should -Be 0
        }

        It 'reports pull failures explicitly' {
            $global:SqlDbContainerTest.FailCommand = 'pull'
            { & "$project\pull-container.ps1" } | Should -Throw '*Docker pull failed*'
        }
    }
}
