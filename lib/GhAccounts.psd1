@{
    RootModule        = 'GhAccounts.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '2a8f4c6e-9b3d-4a1e-8c7f-5d2b9e1a3c6f'
    Author            = 'noejunior299'
    CompanyName       = 'gh-accounts'
    Copyright         = '(c) noejunior299. MIT license.'
    Description       = 'Manage multiple GitHub SSH identities on Windows — securely, scalably, and without external dependencies.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Write-Info', 'Write-Success', 'Write-Warn', 'Write-Error',
        'Show-Banner', 'Get-GhVersion',
        'Get-KeyPath', 'Get-HostAlias',
        'Test-KeyExists', 'Test-HostExists',
        'Ensure-SshDir', 'Ensure-SshConfig', 'Ensure-SshAgent',
        'Test-SplitModeEnabled',
        'Get-ConfigAccounts', 'Get-AllAliases',
        'Enable-SplitMode', 'Disable-SplitMode',
        'Merge-Configs', 'Split-AllConfigs',
        'Set-DefaultAccount',
        'New-GhAccount', 'Remove-GhAccount',
        'Update-GhAccount', 'Test-GhAccount',
        'Get-GhAccounts', 'Export-GhAccountsJson',
        'Switch-GhAccount',
        'Get-AgentStatus', 'Get-GitHubKeyCount',
        'Add-AgentKey', 'Clear-Agent', 'Reset-Agent',
        'Set-HardenConfig',
        'Backup-Create', 'Backup-CreateAuto',
        'Get-BackupList', 'Restore-Backup',
        'Invoke-Doctor'
    )
    PrivateData = @{
        PSData = @{
            Tags         = @('github', 'ssh', 'identity', 'accounts', 'windows')
            ProjectUri   = 'https://github.com/noejunior299/gh-accounts'
            LicenseUri   = 'https://github.com/noejunior299/gh-accounts/blob/main/LICENSE'
        }
    }
}
