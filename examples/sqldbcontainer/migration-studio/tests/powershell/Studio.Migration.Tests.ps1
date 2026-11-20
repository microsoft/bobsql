BeforeDiscovery {
    $scripts = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts'))
    Import-Module (Join-Path $scripts 'Studio.Engine.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $scripts 'Studio.Migration.psm1') -Force -DisableNameChecking
}

Describe 'Migration orchestration fails closed without cloud changes' {
    BeforeAll {
        $script:work = Join-Path $PSScriptRoot ('.test-work-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:work)
    }
    AfterAll {
        Remove-Item -LiteralPath $script:work -Recurse -Force
    }
    It 'blocks writable sources before provisioning and retains safe failure evidence' {
        InModuleScope Studio.Migration -Parameters @{ Work=$script:work } {
            param($Work)
            $run = Join-Path $Work ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($run)
            $config=@{runDirectory=$run}
            Mock Assert-StudioConfiguration {}
            Mock Protect-StudioDirectory {}
            Mock Set-StudioRunContext {}
            Mock Assert-StudioNotCancelled {}
            Mock Write-StudioEvent {}
            Mock Get-StudioSqlPackage { @{version='170.5.96.0'} }
            Mock Get-StudioIdentity { @{id='operator'} }
            Mock Get-StudioSource { @{password=ConvertTo-SecureString 'never-logged' -AsPlainText -Force} }
            Mock Open-StudioSourceConnection { [IO.MemoryStream]::new() }
            Mock Assert-StudioSourceReadOnly { Stop-StudioOperation 'SourceNotReadOnly' 'Source must already be READ_ONLY.' }
            Mock New-StudioTarget { throw 'must not provision' }
            Mock Invoke-StudioTransfer { throw 'must not export' }
            $config.sourceDatabase='CustomerServiceDesk'
            { Invoke-StudioMigration $config 'unused' } | Should -Throw '*READ_ONLY*'
            Should -Invoke New-StudioTarget -Times 0
            Should -Invoke Invoke-StudioTransfer -Times 0
            $failure=Get-Content (Join-Path $run 'engine-failure.json') -Raw | ConvertFrom-Json
            $failure.sourceOperationalStateChanged | Should -BeFalse
            $failure.code | Should -Be 'SourceNotReadOnly'
            (Get-Content (Join-Path $run 'engine-failure.json') -Raw) | Should -Not -Match 'never-logged'
        }
    }
    It 'refuses a replay before performing another preflight or provisioning' {
        InModuleScope Studio.Migration -Parameters @{ Work=$script:work } {
            param($Work)
            $run = Join-Path $Work ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($run)
            [IO.File]::WriteAllText((Join-Path $run 'engine-execution.json'),'{}')
            Mock Assert-StudioConfiguration {}
            Mock Protect-StudioDirectory {}
            Mock Set-StudioRunContext {}
            Mock Get-StudioSqlPackage { throw 'must not rerun' }
            Mock New-StudioTarget { throw 'must not provision' }
            { Invoke-StudioMigration @{runDirectory=$run} 'unused' } | Should -Throw '*already started*'
            Should -Invoke Get-StudioSqlPackage -Times 0
            Should -Invoke New-StudioTarget -Times 0
        }
    }
    It 'does not export or import after the target emptiness check fails' {
        InModuleScope Studio.Migration -Parameters @{ Work=$script:work } {
            param($Work)
            $run = Join-Path $Work ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($run)
            Mock Assert-StudioConfiguration {}
            Mock Protect-StudioDirectory {}
            Mock Set-StudioRunContext {}
            Mock Assert-StudioNotCancelled {}
            Mock Write-StudioEvent {}
            Mock Get-StudioSqlPackage { @{version='170.5.96.0'} }
            Mock Get-StudioIdentity { @{id='operator'} }
            Mock Get-StudioSource { @{password=ConvertTo-SecureString 'not-output' -AsPlainText -Force} }
            Mock Open-StudioSourceConnection { [IO.MemoryStream]::new() }
            Mock Assert-StudioSourceReadOnly {}
            Mock Get-StudioDataEvidence { @{tables=@(@{name='dbo.Cases';rowCount=3})} }
            Mock New-StudioTarget {}
            Mock Open-StudioTargetConnection { [IO.MemoryStream]::new() }
            Mock Assert-StudioEmptyTarget { Stop-StudioOperation 'TargetNotEmpty' 'Target will not be cleared.' }
            Mock Invoke-StudioTransfer { throw 'must not transfer' }
            { Invoke-StudioMigration @{runDirectory=$run;sourceDatabase='CustomerServiceDesk'} 'unused' } |
                Should -Throw '*will not be cleared*'
            Should -Invoke Invoke-StudioTransfer -Times 0
            $failure=Get-Content (Join-Path $run 'engine-failure.json') -Raw | ConvertFrom-Json
            $failure.stage | Should -BeExactly 'provision'
            $failure.targetMayBePartial | Should -BeTrue
        }
    }
    It 'does not import if post-export content changed' {
        InModuleScope Studio.Migration -Parameters @{ Work=$script:work } {
            param($Work)
            $run = Join-Path $Work ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($run)
            Mock Assert-StudioConfiguration {}
            Mock Protect-StudioDirectory {}
            Mock Set-StudioRunContext {}
            Mock Assert-StudioNotCancelled {}
            Mock Write-StudioEvent {}
            Mock Get-StudioSqlPackage { @{version='170.5.96.0'} }
            Mock Get-StudioIdentity { @{id='operator'} }
            Mock Get-StudioSource { @{password=ConvertTo-SecureString 'not-output' -AsPlainText -Force} }
            Mock Open-StudioSourceConnection { [IO.MemoryStream]::new() }
            Mock Assert-StudioSourceReadOnly {}
            Mock Get-StudioDataEvidence { @{tables=@(@{name='dbo.Cases';rowCount=3})} }
            Mock New-StudioTarget {}
            Mock Open-StudioTargetConnection { [IO.MemoryStream]::new() }
            Mock Assert-StudioEmptyTarget {}
            Mock Invoke-StudioTransfer {}
            Mock Compare-StudioEvidence { Stop-StudioOperation 'ContentVerificationFailed' 'Source changed during export.' }
            { Invoke-StudioMigration @{runDirectory=$run;sourceDatabase='CustomerServiceDesk'} 'unused' } |
                Should -Throw '*changed during export*'
            Should -Invoke Invoke-StudioTransfer -Times 1 -ParameterFilter { $Action -eq 'Export' }
            Should -Invoke Invoke-StudioTransfer -Times 0 -ParameterFilter { $Action -eq 'Import' }
        }
    }
}
