<#
.SYNOPSIS
    GitHub SSH Account Manager — manage multiple GitHub SSH identities on Windows.
.DESCRIPTION
    gh-accounts automates SSH key and config management for multiple GitHub accounts.
    Create, delete, update, list, test and switch between identities.
    Works natively on Windows 10/11 with OpenSSH Client.
.LINK
    https://github.com/noejunior299/gh-accounts
#>

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# Resolve library path and import module
# ---------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path (Join-Path (Join-Path $scriptDir "..") "lib") "GhAccounts.psm1"
$resolvedModule = Resolve-Path $modulePath -ErrorAction SilentlyContinue

if (-not $resolvedModule) {
    # Installed location: $env:ProgramFiles\gh-accounts\lib\GhAccounts.psm1
    $installedModule = "$env:ProgramFiles\gh-accounts\lib\GhAccounts.psm1"
    if (Test-Path $installedModule) {
        $resolvedModule = $installedModule
    } else {
        Write-Host "FATAL: Cannot locate GhAccounts.psm1 library module." -ForegroundColor Red
        exit 1
    }
}

try {
    Import-Module $resolvedModule -Force -DisableNameChecking -ErrorAction Stop
} catch {
    Write-Host "FATAL: Failed to import module: $_" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
function Show-Help {
    Show-Banner
    Write-Host @'
  USAGE
    gh-accounts.ps1 <command> [arguments] [options]

  COMMANDS
    create <name> <email>        Create a new GitHub SSH account
    list                         List all configured accounts
    delete <name>                Delete an account and its keys
    update <name> --email <addr> Update account email
    switch <name> [--global]     Set git user.name/email for current repo or globally
    set-default <name>           Set account as default for github.com (no prefix needed)
    test <name>                  Test SSH authentication
    agent-status                 Show agent key breakdown
    agent-load <name>            Load a key into ssh-agent on demand
    agent-clean                  Remove GitHub keys from ssh-agent
    agent-reset                  Clean agent + reconfigure
    harden                       Add IdentitiesOnly yes to SSH config
    backup                       Create a manual backup
    restore                      Restore from a backup
    doctor                       Run diagnostic checks
    split-mode enable            Enable per-account config files
    split-mode disable           Merge back into unified config
    merge-configs                Merge split configs into unified config
    export --json                Export accounts as JSON
    version                      Print version
    help                         Show this help message

  EXAMPLES
    gh-accounts.ps1 create work work@company.com
    gh-accounts.ps1 create personal me@gmail.com
    gh-accounts.ps1 list
    gh-accounts.ps1 test work
    gh-accounts.ps1 update work --email new@company.com
    gh-accounts.ps1 delete personal
    gh-accounts.ps1 switch work
    gh-accounts.ps1 switch work --global
    gh-accounts.ps1 set-default work
    gh-accounts.ps1 agent-status
    gh-accounts.ps1 agent-load work
    gh-accounts.ps1 agent-clean
    gh-accounts.ps1 harden
    gh-accounts.ps1 split-mode enable
    gh-accounts.ps1 export --json

  DOCUMENTATION
    https://github.com/noejunior299/gh-accounts

'@
}

# ---------------------------------------------------------------------------
# Command router
# ---------------------------------------------------------------------------
function Main {
    param([string[]]$ScriptArgs)

    $command = if ($ScriptArgs.Count -gt 0) { $ScriptArgs[0] } else { "help" }
    $remaining = @()
    if ($ScriptArgs.Count -gt 1) {
        $remaining = $ScriptArgs[1..($ScriptArgs.Count - 1)]
    }

    switch ($command) {
        "create" {
            Show-Banner
            if ($remaining.Count -lt 2) {
                Write-Error "Usage: gh-accounts.ps1 create <account_name> <email>"
                exit 1
            }
            New-GhAccount -Account $remaining[0] -Email $remaining[1]
        }

        { $_ -in "list", "ls" } {
            Show-Banner
            Get-GhAccounts
        }

        { $_ -in "delete", "rm" } {
            Show-Banner
            if ($remaining.Count -lt 1) {
                Write-Error "Usage: gh-accounts.ps1 delete <account_name>"
                exit 1
            }
            Remove-GhAccount -Account $remaining[0]
        }

        "update" {
            Show-Banner
            $name = $null
            $email = $null
            $i = 0
            while ($i -lt $remaining.Count) {
                switch ($remaining[$i]) {
                    "--email" {
                        $i++
                        if ($i -ge $remaining.Count) {
                            Write-Error "Missing value for --email"
                            exit 1
                        }
                        $email = $remaining[$i]
                    }
                    default {
                        if ($null -eq $name) { $name = $remaining[$i] }
                        else {
                            Write-Error "Unknown option: $($remaining[$i])"
                            exit 1
                        }
                    }
                }
                $i++
            }
            if (-not $name -or -not $email) {
                Write-Error "Usage: gh-accounts.ps1 update <account_name> --email <new_email>"
                exit 1
            }
            Update-GhAccount -Account $name -NewEmail $email
        }

        "switch" {
            Show-Banner
            $name = $null
            $scope = "local"
            foreach ($arg in $remaining) {
                switch ($arg) {
                    "--global" { $scope = "global" }
                    default {
                        if ($null -eq $name) { $name = $arg }
                        else {
                            Write-Error "Unknown option: $arg"
                            exit 1
                        }
                    }
                }
            }
            if (-not $name) {
                Write-Error "Usage: gh-accounts.ps1 switch <account_name> [--global]"
                exit 1
            }
            Switch-GhAccount -Account $name -Scope $scope
        }

        "set-default" {
            Show-Banner
            if ($remaining.Count -lt 1) {
                Write-Error "Usage: gh-accounts.ps1 set-default <account_name>"
                exit 1
            }
            if ($remaining.Count -gt 1) {
                Write-Error "Too many arguments. Usage: gh-accounts.ps1 set-default <account_name>"
                exit 1
            }
            Set-DefaultAccount -Account $remaining[0]
        }

        "test" {
            Show-Banner
            if ($remaining.Count -lt 1) {
                Write-Error "Usage: gh-accounts.ps1 test <account_name>"
                exit 1
            }
            Test-GhAccount -Account $remaining[0]
        }

        "agent-status" {
            Show-Banner
            Get-AgentStatus
        }

        "agent-load" {
            Show-Banner
            if ($remaining.Count -lt 1) {
                Write-Error "Usage: gh-accounts.ps1 agent-load <account_name>"
                exit 1
            }
            Add-AgentKey -Account $remaining[0]
        }

        "agent-clean" {
            Show-Banner
            Clear-Agent
        }

        "agent-reset" {
            Show-Banner
            Reset-Agent
        }

        "harden" {
            Show-Banner
            Set-HardenConfig
        }

        "backup" {
            Show-Banner
            Backup-Create
        }

        "restore" {
            Show-Banner
            Restore-Backup
        }

        "doctor" {
            Show-Banner
            Invoke-Doctor
        }

        "split-mode" {
            Show-Banner
            if ($remaining.Count -lt 1) {
                Write-Error "Usage: gh-accounts.ps1 split-mode <enable|disable>"
                exit 1
            }
            switch ($remaining[0]) {
                "enable" { Enable-SplitMode }
                "disable" { Disable-SplitMode }
                default {
                    Write-Error "Usage: gh-accounts.ps1 split-mode <enable|disable>"
                    exit 1
                }
            }
        }

        "merge-configs" {
            Show-Banner
            Merge-Configs
        }

        "export" {
            if ($remaining.Count -lt 1 -or $remaining[0] -ne "--json") {
                Write-Error "Usage: gh-accounts.ps1 export --json"
                exit 1
            }
            Export-GhAccountsJson
        }

        { $_ -in "version", "--version", "-v" } {
            $v = Get-GhVersion
            Write-Host "gh-accounts v$v"
        }

        { $_ -in "help", "--help", "-h" } {
            Show-Help
        }

        default {
            Write-Error "Unknown command: $command"
            Write-Host ""
            Show-Help
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
try {
    Main -ScriptArgs $args
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
