<#
.SYNOPSIS
    Install gh-accounts for Windows (PowerShell).
.DESCRIPTION
    Copies gh-accounts module and CLI to $env:ProgramFiles\gh-accounts\,
    adds a gh-accounts.cmd wrapper to the PATH, so you can run:
      gh-accounts help
    from any terminal.

    Supports both local execution (from a cloned repo) and remote
    installation via:
      iwr -UseBasicParsing https://.../install.ps1 | iex
#>

#Requires -Version 5.1

# Explicit admin check (works even when piped via iex)
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "FATAL: Administrator privileges required. Run PowerShell as Administrator and try again." -ForegroundColor Red
    exit 1
}

$CLR_GREEN = "$([char]0x1b)[0;32m"
$CLR_CYAN = "$([char]0x1b)[0;36m"
$CLR_RED = "$([char]0x1b)[0;31m"
$CLR_YELLOW = "$([char]0x1b)[0;33m"
$CLR_BOLD = "$([char]0x1b)[1m"
$CLR_RESET = "$([char]0x1b)[0m"

function info    { Write-Host "$CLR_CYAN[info]$CLR_RESET    $args" }
function success { Write-Host "$CLR_GREEN[success]$CLR_RESET $args" }
function warn    { Write-Host "$CLR_YELLOW[warn]$CLR_RESET    $args" }
function error   { Write-Host "$CLR_RED[error]$CLR_RESET   $args" -ForegroundColor Red }
function die     { error $args; exit 1 }

# ---------------------------------------------------------------------------
# Resolve source directory (local clone or download from GitHub)
# ---------------------------------------------------------------------------
$sourceDir = $null

# Try local — running from a cloned repo
if ($MyInvocation.MyCommand.Path) {
    $scriptParent = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (Test-Path (Join-Path $scriptParent "bin\gh-accounts.ps1")) {
        $sourceDir = $scriptParent
    }
}

if (-not $sourceDir) {
    # Remote install — download to a temp folder
    $tmpDir = Join-Path $env:TEMP "gh-accounts-install"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    $githubUrl = "https://raw.githubusercontent.com/noejunior299/gh-accounts/main"
    $filesToDownload = @(
        "bin/gh-accounts.ps1",
        "lib/GhAccounts.psm1",
        "lib/GhAccounts.psd1",
        "VERSION",
        "LICENSE"
    )

    info "Downloading gh-accounts from GitHub..."
    foreach ($relativePath in $filesToDownload) {
        $url = "$githubUrl/$relativePath"
        $dest = Join-Path $tmpDir $relativePath
        $parentDir = Split-Path -Parent $dest
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -ErrorAction Stop
            info "  Downloaded $relativePath"
        } catch {
            die "Failed to download $url`: $_"
        }
    }

    $sourceDir = $tmpDir
}

$installDir = "$env:ProgramFiles\gh-accounts"

Write-Host "$CLR_CYAN"
Write-Host @'
        __                               __
  ___ _/ /  ___ _______ ___  __ _____   / /____
 / _ `/ _ \/ _ `/ __/ __/ _ \/ // / _ \/ __(_-<
 \_, /_//_/\_,_/\__/\__/\___/\_,_/_//_/\__/___/
/___/
'@
Write-Host "$CLR_RESET"
Write-Host "  ${CLR_BOLD}Installer (PowerShell)${CLR_RESET}"
Write-Host ""

info "Installing gh-accounts to $installDir..."

# Remove previous installation
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
}

# Create directories
New-Item -ItemType Directory -Path "$installDir\bin" -Force | Out-Null
New-Item -ItemType Directory -Path "$installDir\lib" -Force | Out-Null

# Copy files
Copy-Item "$sourceDir\bin\gh-accounts.ps1" "$installDir\bin\gh-accounts.ps1" -Force
Copy-Item "$sourceDir\lib\GhAccounts.psm1" "$installDir\lib\GhAccounts.psm1" -Force
Copy-Item "$sourceDir\lib\GhAccounts.psd1" "$installDir\lib\GhAccounts.psd1" -Force
if (Test-Path "$sourceDir\VERSION") {
    Copy-Item "$sourceDir\VERSION" "$installDir\VERSION" -Force
}
if (Test-Path "$sourceDir\LICENSE") {
    Copy-Item "$sourceDir\LICENSE" "$installDir\LICENSE" -Force
}

# Create gh-accounts.cmd wrapper so users can run `gh-accounts`
$cmdWrapper = '@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0\gh-accounts.ps1" %*'
$cmdWrapper | Out-File -FilePath "$installDir\bin\gh-accounts.cmd" -Encoding ASCII -Force

# Remove legacy wrappers
Remove-Item "$installDir\bin\gh-accounts.bat" -ErrorAction SilentlyContinue

# Add to PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$binPath = "$installDir\bin"
if ($userPath -notlike "*$binPath*") {
    $newPath = if ($userPath) { "$userPath;$binPath" } else { $binPath }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    info "Added $binPath to user PATH."
} else {
    info "$binPath is already in PATH."
}

# Also add to current session
$env:Path = "$env:Path;$binPath"

Write-Host ""
success "gh-accounts installed successfully!"
Write-Host ""
$versionFile = "$installDir\VERSION"
if (Test-Path $versionFile) {
    $v = (Get-Content $versionFile -Raw).Trim()
    Write-Host "  Version: $v"
}
Write-Host ""
Write-Host "  Run:  gh-accounts help"
Write-Host ""
warn "You may need to restart your terminal for PATH changes to take effect."
warn "OpenSSH Client is required. Install with:"
Write-Host "    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
Write-Host ""

# Clean up temp download
if ($sourceDir -like "$env:TEMP\gh-accounts-install*") {
    Remove-Item $sourceDir -Recurse -Force -ErrorAction SilentlyContinue
}
