BeforeDiscovery {
    $scripts = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts'))
    Import-Module (Join-Path $scripts 'Studio.Engine.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $scripts 'Studio.Migration.psm1') -Force -DisableNameChecking
}

Describe 'Typed request and approval guards' {
    InModuleScope Studio.Engine {
        BeforeEach {
            $config = @{
                containerName='sqldbcontainer';sourceDatabase='CustomerServiceDesk'
                tenantId='11111111-1111-1111-1111-111111111111'
                subscriptionId='22222222-2222-2222-2222-222222222222'
                region='eastus';resourceGroup='migration-tests';createResourceGroup=$false
                serverName='migration-tests';createServer=$false;targetDatabase='migrated-desk'
                authentication='Entra';runDirectory='C:\protected\runs\test'
                confirmation='CREATE FREE DATABASE AND MIGRATE';writersStopped=$true
            }
        }
        It 'accepts a complete approved request without native operations' {
            Mock Invoke-StudioNative { throw 'must not execute' }
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Not -Throw
            Should -Invoke Invoke-StudioNative -Times 0
        }
        It 'requires exact case-sensitive confirmation' {
            $config.confirmation='create free database and migrate'
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Throw '*exact migration confirmation*'
        }
        It 'rejects truthy strings instead of JSON booleans' {
            $config.writersStopped='true'
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Throw '*JSON booleans*'
        }
        It 'refuses a credential field instead of accepting arbitrary SQL connection input' {
            $config.connectionString='Server=elsewhere;Password=secret'
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Throw '*unsupported field*'
        }
        It 'rejects a different source container before inspection' {
            $config.containerName='sqldbcontainer-other'
            { Assert-StudioConfiguration $config 'Databases' } | Should -Throw '*approved sqldbcontainer*'
        }
        It 'rejects SQL and command argument injection' {
            $config.sourceDatabase="CustomerServiceDesk]; DROP DATABASE x;--"
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Throw '*named user database*'
        }
        It 'rejects a system database' {
            $config.sourceDatabase='master'
            { Assert-StudioConfiguration $config 'Migrate' } | Should -Throw '*named user database*'
        }
        It 'rejects nonlocal and traversal evidence paths' {
            foreach ($path in @('\\remote\share\run','C:\protected\..\outside','C:\protected\run:stream')) {
                { Assert-StudioLocalPath $path } | Should -Throw '*absolute local Windows path*'
            }
        }
    }
}

Describe 'Quiescence and free protection are measured, not acknowledgments' {
    InModuleScope Studio.Engine {
        It 'blocks a writable source even when all other privileges are sufficient' {
            Mock Invoke-StudioQuery {
                $table=[Data.DataTable]::new()
                [void]$table.Columns.Add('ReadOnly',[bool])
                [void]$table.Columns.Add('CanUnmask',[int])
                [void]$table.Columns.Add('IsOwner',[int])
                [void]$table.Rows.Add($false,1,1)
                return ,$table
            }
            { Assert-StudioSourceReadOnly ([object]::new()) } | Should -Throw '*source must already be READ_ONLY*'
        }
        It 'refuses masked-privilege export even when source is read-only' {
            Mock Invoke-StudioQuery {
                $table=[Data.DataTable]::new()
                [void]$table.Columns.Add('ReadOnly',[bool])
                [void]$table.Columns.Add('CanUnmask',[int])
                [void]$table.Columns.Add('IsOwner',[int])
                [void]$table.Rows.Add($true,0,1)
                return ,$table
            }
            { Assert-StudioSourceReadOnly ([object]::new()) } | Should -Throw '*UNMASK*'
        }
        It 'rejects paid, overage, and oversized variants of an otherwise valid target' {
            foreach ($change in @(
                @{key='useFreeLimit';value=$false},
                @{key='freeLimitExhaustionBehavior';value='BillOverUsage'},
                @{key='maxSizeBytes';value=64GB}
            )) {
                $db=@{useFreeLimit=$true;freeLimitExhaustionBehavior='AutoPause';maxSizeBytes=32GB;
                    sku=@{tier='GeneralPurpose';name='GP_S_Gen5';capacity=2}}
                $db[$change.key]=$change.value
                { Assert-StudioFreeDatabase $db } | Should -Throw '*Paid fallback is forbidden*'
            }
        }
        It 'refuses a nonempty target rather than clearing it' {
            Mock Invoke-StudioQuery {
                $table=[Data.DataTable]::new()
                [void]$table.Columns.Add('ObjectCount',[long])
                [void]$table.Rows.Add(1)
                return ,$table
            }
            { Assert-StudioEmptyTarget ([object]::new()) } | Should -Throw '*will not be cleared*'
        }
    }
}

Describe 'Tenant and identity isolation' {
    InModuleScope Studio.Engine {
        It 'resolves a user with a subscription-scoped token without incompatible tenant arguments' {
            Mock Assert-StudioAzureContext {}
            Mock Invoke-StudioAz {
                param($Arguments)
                if ($Arguments -contains '--tenant') { throw 'Tenant and subscription cannot be combined.' }
                $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"tid":"selected","oid":"operator"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
                return @{accessToken="test.$payload.test"}
            }
            Mock Invoke-RestMethod { @{id='operator';displayName='Test operator';userPrincipalName='test@example.invalid'} }
            $identity = Get-StudioIdentity @{subscriptionId='sub';tenantId='selected'}
            $identity.id | Should -Be 'operator'
            Should -Invoke Assert-StudioAzureContext -Times 1
            Should -Invoke Invoke-StudioAz -Times 1 -ParameterFilter {
                $Arguments -contains '--subscription' -and $Arguments -contains 'sub' -and
                $Arguments -contains 'https://graph.microsoft.com/' -and $Arguments -notcontains '--tenant'
            }
        }
        It 'rejects a token from a different tenant before querying Graph' {
            Mock Assert-StudioAzureContext {}
            Mock Invoke-StudioAz {
                $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"tid":"wrong","oid":"operator"}')).TrimEnd('=').Replace('+','-').Replace('/','_')
                return @{accessToken="test.$payload.test"}
            }
            Mock Invoke-RestMethod { throw 'Graph must not be queried.' }
            { Get-StudioIdentity @{subscriptionId='sub';tenantId='selected'} } | Should -Throw '*wrong tenant*'
            Should -Invoke Invoke-RestMethod -Times 0
        }
        It 'blocks a subscription from a different selected tenant' {
            Mock Invoke-StudioAz { [pscustomobject]@{tenantId='wrong';id='sub';state='Enabled'} }
            { Assert-StudioAzureContext @{subscriptionId='sub';tenantId='selected'} } | Should -Throw '*selected tenant*'
        }
        It 'filters subscriptions by selected tenant and enabled state' {
            Mock Invoke-StudioAz {
                @([pscustomobject]@{id='a';name='a';tenantId='selected';state='Enabled'},
                  [pscustomobject]@{id='b';name='b';tenantId='other';state='Enabled'},
                  [pscustomobject]@{id='c';name='c';tenantId='selected';state='Disabled'})
            }
            $subscriptions=@(Get-StudioSubscriptions @{tenantId='selected'})
            $subscriptions.Count | Should -Be 1
            $subscriptions[0].id | Should -Be 'a'
        }
    }
}

Describe 'Credential and diagnostic isolation' {
    InModuleScope Studio.Engine {
        It 'never returns a password from container discovery' {
            Mock Invoke-StudioNative {
                param($File,$Arguments)
                if ($Arguments[0] -eq 'context') {
                    return @{output='[{"Endpoints":{"docker":{"Host":"npipe:////./pipe/docker_engine"}}}]';exitCode=0}
                }
                return @{output='[{"Name":"/sqldbcontainer","Config":{"Image":"approved-image","Env":["MSSQL_SA_PASSWORD=do-not-output"]},"State":{"Running":true,"Status":"running"},"NetworkSettings":{"Ports":{"1433/tcp":[{"HostIp":"0.0.0.0","HostPort":"14332"}]}}}]';exitCode=0}
            }
            $saved=$env:DOCKER_HOST
            try {
                $env:DOCKER_HOST=$null
                $source=Get-StudioSource
                ($source | ConvertTo-Json -Compress) | Should -Not -Match 'do-not-output|Config|Env|password'
                $source.endpoint | Should -Be '127.0.0.1,14332'
            } finally { $env:DOCKER_HOST=$saved }
        }
        It 'blocks remote Docker before inspecting container credentials' {
            Mock Invoke-StudioNative { @{output='[{"Endpoints":{"docker":{"Host":"tcp://remote:2376"}}}]';exitCode=0} }
            $saved=$env:DOCKER_HOST
            try {
                $env:DOCKER_HOST=$null
                { Get-StudioSource -Credential } | Should -Throw '*local Docker engine*'
                Should -Invoke Invoke-StudioNative -Times 1
            } finally { $env:DOCKER_HOST=$saved }
        }
        It 'withholds secrets, SQL text, and private rows from arbitrary exceptions' {
            try { throw 'Password=hidden; SELECT PrivateRow; bearer token' } catch { $safe=Get-StudioSafeError $_ }
            $safe.code | Should -Be 'OperationFailed'
            ($safe | ConvertTo-Json) | Should -Not -Match 'hidden|SELECT|PrivateRow|bearer token'
        }
    }
}

Describe 'Content verification' {
    InModuleScope Studio.Migration {
        BeforeAll {
            $provider=Get-Module -ListAvailable SqlServer | Select-Object -First 1
            [void][Reflection.Assembly]::LoadFrom((Join-Path $provider.ModuleBase 'coreclr\Microsoft.SqlServer.TransactSql.ScriptDom.dll'))
        }
        It 'normalizes harmless DacFx module scripting without discarding string values' {
            $source=Get-StudioModuleFingerprint "CREATE OR ALTER PROCEDURE dbo.p AS SELECT N'private value', 1;"
            $target=Get-StudioModuleFingerprint "CREATE PROCEDURE [dbo].[p] AS /* scripted */ SELECT N'private value',1;"
            $source | Should -Be $target
            $different=Get-StudioModuleFingerprint "CREATE PROCEDURE [dbo].[p] AS SELECT N'changed value',1;"
            $source | Should -Not -Be $different
            $numberChanged=Get-StudioModuleFingerprint "CREATE PROCEDURE [dbo].[p] AS SELECT N'private value',2;"
            $source | Should -Not -Be $numberChanged
            $alter=Get-StudioModuleFingerprint "ALTER PROCEDURE dbo.p AS SELECT N'private value',1;"
            $source | Should -Be $alter
        }
        It 'excludes regenerated rowversion but compares JSON, vectors, and full precision floats and money' {
            $query=Get-StudioTableHashQuery 'dbo' 'Cases' @(
                @{ColumnName='Version';TypeName='timestamp'},
                @{ColumnName='Details';TypeName='json'},
                @{ColumnName='Embedding';TypeName='vector'},
                @{ColumnName='Score';TypeName='float'},
                @{ColumnName='Cost';TypeName='money'})
            $query | Should -Not -Match '\[Version\]'
            $query | Should -Match '\[Details\]'
            $query | Should -Match '\[Embedding\]'
            $query | Should -Match '\[Score\],3'
            $query | Should -Match '\[Cost\],2'
            $query | Should -Match 'ORDER BY RowHash'
        }

        It 'blocks unsupported lossless comparison before exporting' {
            { Get-StudioTableHashQuery 'dbo' 'x' @(@{ColumnName='x';TypeName='sql_variant'}) } |
                Should -Throw '*no approved lossless comparison*'
        }
        It 'detects content drift even when row counts match' {
            $source=@{schemaHash='same';metadataHash='same';tables=@(@{name='dbo.Cases';rowCount=5;contentHash='before'})}
            $target=@{schemaHash='same';metadataHash='same';tables=@(@{name='dbo.Cases';rowCount=5;contentHash='after'})}
            { Compare-StudioEvidence $source $target } | Should -Throw '*content hashes differ*'
        }
        It 'accepts matching measured evidence independent of table ordering' {
            $a=@{name='dbo.A';rowCount=5;contentHash='a'}
            $b=@{name='dbo.B';rowCount=0;contentHash='b'}
            { Compare-StudioEvidence @{schemaHash='x';metadataHash='y';tables=@($a,$b)} `
                @{schemaHash='x';metadataHash='y';tables=@($b,$a)} } | Should -Not -Throw
        }
    }

    Describe 'Entrypoint failure protocol' {
        It 'emits only a safe final JSON error and nonzero exit for a non-allowlisted operation' {
            $entrypoint=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\Invoke-StudioOperation.ps1'))
            $output = & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -NonInteractive -File $entrypoint `
                -Operation 'ExecuteArbitrarySql' -InputFile 'C:\not-read-private-request.json'
            $exitCode=$LASTEXITCODE
            $exitCode | Should -Be 1
            @($output).Count | Should -Be 1
            $json=$output | ConvertFrom-Json
            $json.code | Should -Be 'InvalidOperation'
            $json.safeError | Should -Be 'The requested operation is not allowlisted.'
            $json.verified | Should -BeFalse
        }
    }
}
