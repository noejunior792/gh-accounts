<#
.SYNOPSIS
    Uninstall gh-accounts for Windows (PowerShell).
.DESCRIPTION
    Removes gh-accounts from $env:ProgramFiles\gh-accounts\
    and cleans up the PATH.
#>

#Requires -Version 5.1 -RunAsAdministrator

$CLR_RED = "$([char]0x1b)[0;31m"
$CLR_CYAN = "$([char]0x1b)[0;36m"
$CLR_GREEN = "$([char]0x1b)[0;32m"
$CLR_BOLD = "$([char]0x1b)[1m"
$CLR_RESET = "$([char]0x1b)[0m"

function info    { Write-Host "$CLR_CYAN[info]$CLR_RESET    $args" }
function success { Write-Host "$CLR_GREEN[success]$CLR_RESET $args" }
function error   { Write-Host "$CLR_RED[error]$CLR_RESET   $args" -ForegroundColor Red }
function die     { error $args; exit 1 }

$installDir = "$env:ProgramFiles\gh-accounts"

if (-not (Test-Path $installDir)) {
    info "gh-accounts is not installed."
    exit 0
}

Write-Host "Uninstalling gh-accounts from $installDir..."

try {
    Remove-Item $installDir -Recurse -Force
    success "Removed $installDir."
} catch {
    die "Failed to remove $installDir`: $_"
}

# Clean PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$binPath = "$env:ProgramFiles\gh-accounts\bin"
if ($userPath -like "*$binPath*") {
    $newPath = ($userPath.Split(';') | Where-Object { $_ -ne $binPath }) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    info "Removed $binPath from PATH."
}

info "Uninstall complete."
