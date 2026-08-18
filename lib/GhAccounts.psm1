# =============================================================================
# gh-accounts :: GhAccounts.psm1
# PowerShell module for managing multiple GitHub SSH identities on Windows.
# Mirror of the Bash lib/*.sh modules.
# =============================================================================

#Requires -Version 5.1

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:GH_SSH_DIR = Join-Path $HOME ".ssh"
$script:GH_SSH_CONFIG = Join-Path $script:GH_SSH_DIR "config"
$script:GH_SPLIT_DIR = Join-Path $script:GH_SSH_DIR "gh-accounts"
$script:GH_BACKUP_DIR = Join-Path $script:GH_SSH_DIR "gh-accounts-backups"
$script:GH_KEY_PREFIX = "github"

# ---------------------------------------------------------------------------
# ANSI color helpers (safe for redirected output)
# ---------------------------------------------------------------------------
$script:UseAnsi = $host.UI.RawUI.ForegroundColor -ne $null -and [Console]::IsOutputRedirected -eq $false
if ($script:UseAnsi) {
    $script:CLR_RED = "$([char]0x1b)[0;31m"
    $script:CLR_GREEN = "$([char]0x1b)[0;32m"
    $script:CLR_YELLOW = "$([char]0x1b)[0;33m"
    $script:CLR_BLUE = "$([char]0x1b)[0;34m"
    $script:CLR_CYAN = "$([char]0x1b)[0;36m"
    $script:CLR_BOLD = "$([char]0x1b)[1m"
    $script:CLR_RESET = "$([char]0x1b)[0m"
} else {
    $script:CLR_RED = $script:CLR_GREEN = $script:CLR_YELLOW = ""
    $script:CLR_BLUE = $script:CLR_CYAN = $script:CLR_BOLD = $script:CLR_RESET = ""
}

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------
function Write-Info {
    Write-Host "$($script:CLR_BLUE)[info]$($script:CLR_RESET)    $args"
}
function Write-Success {
    Write-Host "$($script:CLR_GREEN)[success]$($script:CLR_RESET) $args"
}
function Write-Warn {
    Write-Host "$($script:CLR_YELLOW)[warn]$($script:CLR_RESET)    $args"
}
function Write-Error {
    Write-Host "$($script:CLR_RED)[error]$($script:CLR_RESET)   $args" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
function Show-Banner {
    if ($script:UseAnsi) {
        Write-Host "$($script:CLR_CYAN)"
    }
    Write-Host @'
        __                               __
  ___ _/ /  ___ _______ ___  __ _____   / /____
 / _ `/ _ \/ _ `/ __/ __/ _ \/ // / _ \/ __(_-<
 \_, /_//_/\_,_/\__/\__/\___/\_,_/_//_/\__/___/
/___/
'@
    if ($script:UseAnsi) {
        Write-Host "$($script:CLR_RESET)"
    }
    $v = Get-GhVersion
    Write-Host "  $($script:CLR_BOLD)GitHub SSH Account Manager$($script:CLR_RESET)  ·  v$v"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
function Get-GhVersion {
    $versionFile = Join-Path (Join-Path $PSScriptRoot "..") "VERSION"
    $resolved = Resolve-Path $versionFile -ErrorAction SilentlyContinue
    if (-not $resolved) {
        $resolved = "$env:ProgramFiles\gh-accounts\VERSION"
    }
    if (Test-Path $resolved) {
        return (Get-Content $resolved -Raw).Trim()
    }
    return "unknown"
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
function Test-AccountName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Account name is required."
    }
    if ($Name -notmatch '^[a-zA-Z0-9._-]+$') {
        throw "Invalid account name '$Name'. Use only alphanumerics, dots, hyphens, and underscores."
    }
}

function Test-Email {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) {
        throw "Email address is required."
    }
    if ($Email -notmatch '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
        throw "Invalid email address '$Email'."
    }
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
function Get-KeyPath {
    param([string]$Account)
    return Join-Path $script:GH_SSH_DIR "$($script:GH_KEY_PREFIX)-$Account"
}

function Get-HostAlias {
    param([string]$Account)
    return "github-$Account"
}

# ---------------------------------------------------------------------------
# Account existence checks
# ---------------------------------------------------------------------------
function Test-KeyExists {
    param([string]$Account)
    $kp = Get-KeyPath $Account
    return (Test-Path $kp)
}

function Test-HostExists {
    param([string]$Account)
    $alias = Get-HostAlias $Account
    if (Test-Path $script:GH_SSH_CONFIG) {
        $content = Get-Content $script:GH_SSH_CONFIG -Raw -ErrorAction SilentlyContinue
        if ($content -match "^Host $alias`$" -or $content -match "^Host $alias ") {
            return $true
        }
    }
    $splitFile = Join-Path $script:GH_SPLIT_DIR $alias
    if (Test-Path $splitFile) {
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# SSH directory & permissions helpers (Windows ACL)
# ---------------------------------------------------------------------------
function Ensure-SshDir {
    if (-not (Test-Path $script:GH_SSH_DIR)) {
        New-Item -ItemType Directory -Path $script:GH_SSH_DIR -Force | Out-Null
        Write-Info "Created $($script:GH_SSH_DIR)"
    }
}

function Ensure-SplitDir {
    if (-not (Test-Path $script:GH_SPLIT_DIR)) {
        New-Item -ItemType Directory -Path $script:GH_SPLIT_DIR -Force | Out-Null
        Write-Info "Created $($script:GH_SPLIT_DIR)"
    }
}

function Ensure-BackupDir {
    if (-not (Test-Path $script:GH_BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $script:GH_BACKUP_DIR -Force | Out-Null
        Write-Info "Created $($script:GH_BACKUP_DIR)"
    }
}

function Set-KeyPermissions {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $acl = Get-Acl $Path -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $existingRules = @($acl.Access)
        foreach ($rule in $existingRules) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $user, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
    } catch {
        Write-Warn "Could not set permissions on '$Path': $_"
    }
}

function Set-SshConfigPermissions {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    try {
        $acl = Get-Acl $Path -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $existingRules = @($acl.Access)
        foreach ($rule in $existingRules) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $user, "FullControl", "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
    } catch {
        Write-Warn "Could not set permissions on '$Path': $_"
    }
}

function Ensure-SshConfig {
    Ensure-SshDir
    if (-not (Test-Path $script:GH_SSH_CONFIG)) {
        New-Item -ItemType File -Path $script:GH_SSH_CONFIG -Force | Out-Null
        Set-SshConfigPermissions $script:GH_SSH_CONFIG
        Write-Info "Created $($script:GH_SSH_CONFIG)"
    }
}

# ---------------------------------------------------------------------------
# SSH agent helpers (Windows OpenSSH service)
# ---------------------------------------------------------------------------
function Ensure-SshAgent {
    $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warn "ssh-agent service not found. Ensure OpenSSH Client is installed."
        Write-Warn "Run: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        return $false
    }
    if ($svc.Status -ne 'Running') {
        try {
            Set-Service ssh-agent -StartupType Manual -ErrorAction Stop
            Start-Service ssh-agent -ErrorAction Stop
        } catch {
            Write-Warn "Could not start ssh-agent. Try running PowerShell as Administrator."
            return $false
        }
    }
    return $true
}

function Test-SshAgentRunning {
    try {
        $null = ssh-add -l 2>$null
        return $true
    } catch {
        if ($env:SSH_AUTH_SOCK) { return $true }
        return $false
    }
}

# ---------------------------------------------------------------------------
# Split-mode detection
# ---------------------------------------------------------------------------
function Test-SplitModeEnabled {
    if (Test-Path $script:GH_SSH_CONFIG) {
        $content = Get-Content $script:GH_SSH_CONFIG -Raw -ErrorAction SilentlyContinue
        if ($content -match [regex]::Escape("Include $($script:GH_SPLIT_DIR)/*")) {
            return $true
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Extract email from a public key file comment (last field)
# ---------------------------------------------------------------------------
function Get-EmailFromPubkey {
    param([string]$KeyPath)
    $pubFile = "$KeyPath.pub"
    if (Test-Path $pubFile) {
        $line = Get-Content $pubFile -Raw -ErrorAction SilentlyContinue
        if ($line) {
            $parts = $line.Trim().Split(' ')
            if ($parts.Count -ge 3) {
                return $parts[-1]
            }
        }
    }
    return "unknown"
}

# ---------------------------------------------------------------------------
# Confirm prompt
# ---------------------------------------------------------------------------
function Confirm-Action {
    param([string]$Prompt = "Are you sure?")
    Write-Host "$($script:CLR_YELLOW)$Prompt [y/N]: $($script:CLR_RESET)" -NoNewline
    $answer = Read-Host
    return $answer -match '^[Yy]'
}

# ===========================================================================
# CONFIG MANAGEMENT
# ===========================================================================

function Build-HostBlock {
    param([string]$Account, [string]$Email)
    $alias = Get-HostAlias $Account
    $kp = Get-KeyPath $Account
    return @"
# gh-accounts :: $Account <$Email>
Host $alias
    HostName github.com
    User git
    IdentityFile $kp
    IdentitiesOnly yes
"@
}

function Add-ConfigUnified {
    param([string]$Account, [string]$Email)
    Ensure-SshConfig
    $block = Build-HostBlock $Account $Email
    Add-Content -Path $script:GH_SSH_CONFIG -Value "`r`n$block"
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Info "Added host block for '$Account' to $($script:GH_SSH_CONFIG)."
}

function Add-ConfigSplit {
    param([string]$Account, [string]$Email)
    Ensure-SplitDir
    $alias = Get-HostAlias $Account
    $splitFile = Join-Path $script:GH_SPLIT_DIR $alias
    if (Test-Path $splitFile) {
        throw "Split config already exists: $splitFile"
    }
    $block = Build-HostBlock $Account $Email
    Set-Content -Path $splitFile -Value $block
    Set-KeyPermissions $splitFile
    Write-Info "Created split config $splitFile."
}

function Remove-ConfigUnified {
    param([string]$Account)
    if (-not (Test-Path $script:GH_SSH_CONFIG)) { return }
    $escaped = [regex]::Escape($Account)
    $content = Get-Content $script:GH_SSH_CONFIG
    $newContent = @()
    $skip = $false
    foreach ($line in $content) {
        if ($line -match "^# gh-accounts :: $escaped ") {
            $skip = $true
            continue
        }
        if ($skip) {
            if ($line.Trim() -eq '') {
                $skip = $false
            }
            continue
        }
        $newContent += $line
    }
    $clean = @()
    $prevEmpty = $false
    foreach ($line in $newContent) {
        if ($line.Trim() -eq '') {
            if (-not $prevEmpty) { $clean += $line; $prevEmpty = $true }
        } else {
            $clean += $line; $prevEmpty = $false
        }
    }
    Set-Content -Path $script:GH_SSH_CONFIG -Value ($clean -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Info "Removed host block for '$Account' from $($script:GH_SSH_CONFIG)."
}

function Remove-ConfigSplit {
    param([string]$Account)
    $alias = Get-HostAlias $Account
    $splitFile = Join-Path $script:GH_SPLIT_DIR $alias
    if (Test-Path $splitFile) {
        Remove-Item $splitFile -Force
        Write-Info "Removed split config $splitFile."
    }
}

function Update-ConfigEmailUnified {
    param([string]$Account, [string]$NewEmail)
    if (-not (Test-Path $script:GH_SSH_CONFIG)) { return $false }
    $content = Get-Content $script:GH_SSH_CONFIG -Raw
    $escaped = [regex]::Escape($Account)
    if ($content -notmatch "^# gh-accounts :: $escaped ") { return $false }
    $content = $content -replace "(# gh-accounts :: $escaped )<[^>]*>", "`$1<$NewEmail>"
    Set-Content -Path $script:GH_SSH_CONFIG -Value $content
    Write-Info "Updated email for '$Account' in unified config."
    return $true
}

function Update-ConfigEmailSplit {
    param([string]$Account, [string]$NewEmail)
    $alias = Get-HostAlias $Account
    $splitFile = Join-Path $script:GH_SPLIT_DIR $alias
    if (-not (Test-Path $splitFile)) { return $false }
    $content = Get-Content $splitFile -Raw
    $escaped = [regex]::Escape($Account)
    $content = $content -replace "(# gh-accounts :: $escaped )<[^>]*>", "`$1<$NewEmail>"
    Set-Content -Path $splitFile -Value $content
    Write-Info "Updated email for '$Account' in split config."
    return $true
}

# Parse Host blocks from a config file content array.
function Parse-ConfigFile {
    param([string[]]$Lines, [string]$Mode)
    $result = @()
    $currentAlias = $null
    $currentIdentity = $null
    $currentHostname = $null
    $isManaged = $false
    $managedEmail = $null

    foreach ($line in $Lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^# gh-accounts :: (.+) <(.+)>") {
            $managedEmail = $matches[2]
            $isManaged = $true
            continue
        }
        if ($trimmed -match "^Host (.+)$") {
            if ($currentAlias -and $currentHostname -eq "github.com") {
                $result += Flush-ParsedBlock `
                    -Alias $currentAlias `
                    -Identity $currentIdentity `
                    -Hostname $currentHostname `
                    -Mode $Mode `
                    -IsManaged $isManaged `
                    -ManagedEmail $managedEmail
            }
            $currentAlias = $matches[1]
            $currentIdentity = $null
            $currentHostname = $null
            $isManaged = $false
            $managedEmail = $null
            continue
        }
        if ($currentAlias) {
            if ($trimmed -match "^HostName (.+)$") { $currentHostname = $matches[1] }
            if ($trimmed -match "^IdentityFile (.+)$") { $currentIdentity = $matches[1] }
        }
    }
    if ($currentAlias -and $currentHostname -eq "github.com") {
        $result += Flush-ParsedBlock `
            -Alias $currentAlias `
            -Identity $currentIdentity `
            -Hostname $currentHostname `
            -Mode $Mode `
            -IsManaged $isManaged `
            -ManagedEmail $managedEmail
    }
    return $result
}

function Flush-ParsedBlock {
    param($Alias, $Identity, $Hostname, $Mode, $IsManaged, $ManagedEmail)
    if ($Alias -eq "github.com") { $acct = "default" }
    elseif ($Alias -match "^github-(.+)$") { $acct = $matches[1] }
    else { $acct = $Alias }

    $keyPath = $Identity -replace '^~', $HOME
    if ($IsManaged -and $ManagedEmail) { $email = $ManagedEmail }
    else { $email = Get-EmailFromPubkey $keyPath }

    return [PSCustomObject]@{
        Account   = $acct
        Email     = $email
        Alias     = $Alias
        KeyPath   = $keyPath
        Mode      = $Mode
        Managed   = if ($IsManaged) { "yes" } else { "no" }
    }
}

# List all GitHub SSH accounts
function Get-ConfigAccounts {
    $seenAliases = @{}
    $allAccounts = @()

    if (Test-Path $script:GH_SSH_CONFIG) {
        $lines = Get-Content $script:GH_SSH_CONFIG -ErrorAction SilentlyContinue
        $accounts = Parse-ConfigFile -Lines $lines -Mode "unified"
        foreach ($a in $accounts) {
            $seenAliases[$a.Alias] = $true
            $allAccounts += $a
        }
    }

    if (Test-Path $script:GH_SPLIT_DIR) {
        Get-ChildItem "$($script:GH_SPLIT_DIR)\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
            $lines = Get-Content $_.FullName -ErrorAction SilentlyContinue
            $accounts = Parse-ConfigFile -Lines $lines -Mode "split"
            foreach ($a in $accounts) {
                if (-not $seenAliases.ContainsKey($a.Alias)) {
                    $seenAliases[$a.Alias] = $true
                    $allAccounts += $a
                }
            }
        }
    }

    return $allAccounts
}

function Enable-SplitMode {
    Ensure-SshConfig
    Ensure-SplitDir
    $includeLine = "Include $($script:GH_SPLIT_DIR)/*"
    if (Test-Path $script:GH_SSH_CONFIG) {
        $content = Get-Content $script:GH_SSH_CONFIG -Raw -ErrorAction SilentlyContinue
        if ($content -match [regex]::Escape($includeLine)) {
            Write-Warn "Split mode is already enabled."
            return
        }
    }
    $existing = Get-Content $script:GH_SSH_CONFIG -ErrorAction SilentlyContinue
    $newConfig = @($includeLine, "") + $existing
    Set-Content -Path $script:GH_SSH_CONFIG -Value ($newConfig -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Success "Split mode enabled. Include directive added to $($script:GH_SSH_CONFIG)."
}

function Disable-SplitMode {
    if (-not (Test-Path $script:GH_SSH_CONFIG)) {
        Write-Warn "No SSH config found."
        return
    }
    $includeLine = "Include $($script:GH_SPLIT_DIR)/*"
    $content = Get-Content $script:GH_SSH_CONFIG -ErrorAction SilentlyContinue
    $found = $false
    $newContent = @()
    foreach ($line in $content) {
        if ($line.Trim() -eq $includeLine) {
            $found = $true
            continue
        }
        if ($line.Trim() -eq "") { continue }
        $newContent += $line
    }
    if (-not $found) {
        Write-Warn "Split mode is not enabled."
        return
    }
    Set-Content -Path $script:GH_SSH_CONFIG -Value ($newContent -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Success "Split mode disabled. Include directive removed from $($script:GH_SSH_CONFIG)."
}

function Merge-Configs {
    if (-not (Test-Path $script:GH_SPLIT_DIR)) {
        Write-Warn "No split config directory found."
        return
    }
    $count = 0
    Get-ChildItem "$($script:GH_SPLIT_DIR)\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Content -Path $script:GH_SSH_CONFIG -Value "`r`n"
        $block = Get-Content $_.FullName -Raw
        Add-Content -Path $script:GH_SSH_CONFIG -Value $block
        Remove-Item $_.FullName -Force
        $count++
    }
    if ($count -eq 0) {
        Write-Warn "No split config files found to merge."
        return
    }
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Success "Merged $count split config(s) into $($script:GH_SSH_CONFIG)."
    Disable-SplitMode
}

function Split-AllConfigs {
    if (-not (Test-Path $script:GH_SSH_CONFIG)) {
        throw "No SSH config found: $($script:GH_SSH_CONFIG)"
    }
    Ensure-SplitDir
    $count = 0
    $currentAccount = $null
    $currentBlock = @()
    $inBlock = $false

    Get-Content $script:GH_SSH_CONFIG | ForEach-Object {
        $line = $_
        if ($line -match "^# gh-accounts :: (.+) ") {
            if ($currentAccount) {
                Write-SplitBlock $currentAccount $currentBlock
                $count++
            }
            $currentAccount = $matches[1]
            $currentBlock = @($line)
            $inBlock = $true
        } elseif ($inBlock) {
            if ($line.Trim() -eq '') {
                Write-SplitBlock $currentAccount $currentBlock
                $count++
                $currentAccount = $null
                $currentBlock = @()
                $inBlock = $false
            } else {
                $currentBlock += $line
            }
        }
    }
    if ($currentAccount) {
        Write-SplitBlock $currentAccount $currentBlock
        $count++
    }

    if ($count -eq 0) {
        Write-Warn "No gh-accounts blocks found in unified config."
        return
    }

    $newContent = @()
    $skip = $false
    Get-Content $script:GH_SSH_CONFIG | ForEach-Object {
        $line = $_
        if ($line -match "^# gh-accounts ::") { $skip = $true; return }
        if ($skip) {
            if ($line.Trim() -eq '') { $skip = $false }
            return
        }
        $newContent += $line
    }
    Set-Content -Path $script:GH_SSH_CONFIG -Value ($newContent -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Enable-SplitMode
    Write-Success "Split $count account(s) into $($script:GH_SPLIT_DIR)."
}

function Write-SplitBlock {
    param([string]$Account, [string[]]$Block)
    $alias = Get-HostAlias $Account
    $splitFile = Join-Path $script:GH_SPLIT_DIR $alias
    Set-Content -Path $splitFile -Value ($Block -join "`r`n")
    Set-KeyPermissions $splitFile
}

function Get-AllAliases {
    $aliases = New-Object System.Collections.ArrayList
    if (Test-Path $script:GH_SSH_CONFIG) {
        Get-Content $script:GH_SSH_CONFIG -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match "^Host (github-[a-zA-Z0-9._-]+)$") {
                [void]$aliases.Add($matches[1])
            }
        }
    }
    if (Test-Path $script:GH_SPLIT_DIR) {
        Get-ChildItem "$($script:GH_SPLIT_DIR)\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$aliases.Add($_.Name)
        }
    }
    return $aliases | Sort-Object -Unique
}

function Get-KeyPathForAccount {
    param([string]$Account)
    $accts = Get-ConfigAccounts
    $found = $accts | Where-Object { $_.Account -eq $Account }
    if ($found) {
        return $found[0].KeyPath
    }
    return Get-KeyPath $Account
}

function Set-DefaultAccount {
    param([string]$Account)
    $accts = Get-ConfigAccounts
    $found = $accts | Where-Object { $_.Account -eq $Account }
    if (-not $found) {
        throw "Account '$Account' not found. Run 'gh-accounts list' to see available accounts."
    }

    $kp = Get-KeyPath $Account
    if (-not (Test-Path $kp)) {
        throw "Key not found for account '$Account': $kp"
    }

    if (Test-SplitModeEnabled) {
        throw "Cannot set default account in split mode. Run 'gh-accounts merge-configs' first."
    }

    Ensure-SshConfig

    # Remove any existing Host github.com block managed by gh-accounts
    $content = Get-Content $script:GH_SSH_CONFIG
    $newContent = @()
    $skip = $false
    foreach ($line in $content) {
        if ($line -match "^# gh-accounts :: default" -or $line.Trim() -eq "Host github.com") {
            $skip = $true; continue
        }
        if ($skip) {
            if ($line.Trim() -eq '') { $skip = $false }
            continue
        }
        $newContent += $line
    }

    $email = Get-EmailFromPubkey $kp
    $block = @"
# gh-accounts :: default <$email>
Host github.com
    HostName github.com
    User git
    IdentityFile $kp
    IdentitiesOnly yes
"@
    $newContent += ""
    $newContent += $block
    Set-Content -Path $script:GH_SSH_CONFIG -Value ($newContent -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG
    Write-Success "Set '$Account' as the default SSH account for github.com."
}

# ===========================================================================
# ACCOUNT CRUD
# ===========================================================================

function New-GhAccount {
    param([string]$Account, [string]$Email)
    Test-AccountName $Account
    Test-Email $Email
    $kp = Get-KeyPath $Account

    if (Test-KeyExists $Account) {
        throw "SSH key already exists for account '$Account': $kp"
    }
    if (Test-HostExists $Account) {
        throw "Host alias already exists for account '$Account'."
    }

    Ensure-SshDir
    Backup-CreateAuto

    Write-Info "Generating SSH key pair for '$Account'..."
    $null = ssh-keygen -t ed25519 -C $Email -f $kp -N "" -q 2>&1
    if (-not (Test-Path $kp)) {
        throw "Failed to generate SSH key pair."
    }
    Set-KeyPermissions $kp
    if (Test-Path "$kp.pub") {
        Set-KeyPermissions "$kp.pub"
    }
    Write-Success "Key pair created: $kp"

    if (Test-SplitModeEnabled) {
        Add-ConfigSplit $Account $Email
    } else {
        Add-ConfigUnified $Account $Email
    }

    Write-Success "Account '$Account' created successfully."
    Write-Host ""
    Write-Info "Public key (add this to GitHub -> Settings -> SSH keys):"
    Write-Host ""
    Get-Content "$kp.pub" | Write-Host
    Write-Host ""
    $alias = Get-HostAlias $Account
    Write-Info "Git clone usage:"
    Write-Host "  git clone git@${alias}:username/repo.git"
}

function Remove-GhAccount {
    param([string]$Account)
    Test-AccountName $Account

    if (-not (Test-KeyExists $Account) -and -not (Test-HostExists $Account)) {
        throw "Account '$Account' does not exist."
    }

    if (-not (Confirm-Action "Delete account '$Account' and its SSH keys? This cannot be undone.")) {
        Write-Info "Aborted."
        return
    }

    Backup-CreateAuto

    $kp = Get-KeyPath $Account

    if (Test-Path $kp) {
        $null = ssh-add -d $kp 2>$null
    }

    Remove-Item "$kp" -Force -ErrorAction SilentlyContinue
    Remove-Item "$kp.pub" -Force -ErrorAction SilentlyContinue
    Write-Info "Removed key files."

    Remove-ConfigUnified $Account
    Remove-ConfigSplit $Account

    Write-Success "Account '$Account' deleted."
}

function Update-GhAccount {
    param([string]$Account, [string]$NewEmail)
    Test-AccountName $Account
    Test-Email $NewEmail

    if (-not (Test-KeyExists $Account) -and -not (Test-HostExists $Account)) {
        throw "Account '$Account' does not exist."
    }

    Backup-CreateAuto

    $updated = $false
    try { $r = Update-ConfigEmailUnified $Account $NewEmail; if ($r) { $updated = $true } } catch {}
    try { $r = Update-ConfigEmailSplit $Account $NewEmail; if ($r) { $updated = $true } } catch {}

    if (-not $updated) {
        throw "Could not find config entry for account '$Account'."
    }

    $kp = Get-KeyPath $Account
    if (Test-Path $kp) {
        $null = ssh-keygen -c -C $NewEmail -f $kp -q -N "" 2>$null
    }

    Write-Success "Account '$Account' updated with email '$NewEmail'."
}

function Test-GhAccount {
    param([string]$Account)
    Test-AccountName $Account

    if (-not (Test-KeyExists $Account) -and -not (Test-HostExists $Account)) {
        throw "Account '$Account' does not exist."
    }

    $alias = Get-HostAlias $Account
    Write-Info "Testing SSH connection for '$Account' ($alias)..."
    Write-Host ""

    $output = ssh -T "git@${alias}" 2>&1
    $exitCode = $LASTEXITCODE

    if ($output -match "successfully authenticated") {
        Write-Success "Authentication successful!"
        Write-Host "  $output"
    } elseif ($output -match "permission denied") {
        Write-Error "Authentication failed. Ensure the public key is added to GitHub."
        Write-Host "  $output"
    } else {
        Write-Warn "Unexpected response:"
        Write-Host "  $output"
    }
}

function Get-GhAccounts {
    $accounts = Get-ConfigAccounts
    if (-not $accounts) {
        Write-Info "No GitHub SSH accounts found."
        return
    }

    Write-Host ""
    Write-Host ("  {0,-20} {1,-30} {2,-22} {3,-8} {4,-8}" -f "$($script:CLR_BOLD)ACCOUNT$($script:CLR_RESET)", "$($script:CLR_BOLD)EMAIL$($script:CLR_RESET)", "$($script:CLR_BOLD)HOST ALIAS$($script:CLR_RESET)", "$($script:CLR_BOLD)MODE$($script:CLR_RESET)", "$($script:CLR_BOLD)SOURCE$($script:CLR_RESET)")
    Write-Host ("  {0,-20} {1,-30} {2,-22} {3,-8} {4,-8}" -f "-------", "-----", "----------", "----", "------")

    foreach ($a in $accounts) {
        $keyStatus = if (Test-Path $a.KeyPath) { "$($script:CLR_GREEN)o$($script:CLR_RESET)" } else { "$($script:CLR_RED)x$($script:CLR_RESET)" }
        $sourceLabel = if ($a.Managed -eq "yes") { "managed" } else { "manual" }
        Write-Host ("  {0} {1,-18} {2,-30} {3,-22} {4,-8} {5,-8}" -f $keyStatus, $a.Account, $a.Email, $a.Alias, $a.Mode, $sourceLabel)
    }
    Write-Host ""
}

function Export-GhAccountsJson {
    $accounts = Get-ConfigAccounts
    if (-not $accounts) {
        Write-Host "[]"
        return
    }

    $entries = @()
    foreach ($a in $accounts) {
        $keyExists = (Test-Path $a.KeyPath)
        $pubKey = ""
        $pubFile = "$($a.KeyPath).pub"
        if (Test-Path $pubFile) {
            $pubKey = (Get-Content $pubFile -Raw -ErrorAction SilentlyContinue).Trim()
            $pubKey = $pubKey -replace '"', '\"'
        }
        $managedBool = ($a.Managed -eq "yes")
        $entries += [PSCustomObject]@{
            account    = $a.Account
            email      = $a.Email
            host_alias = $a.Alias
            key_path   = $a.KeyPath
            key_exists = $keyExists
            public_key = $pubKey
            mode       = $a.Mode
            managed    = $managedBool
        }
    }
    ConvertTo-Json $entries -Depth 3
}

function Switch-GhAccount {
    param([string]$Account, [string]$Scope = "local")
    Test-AccountName $Account

    $accounts = Get-ConfigAccounts
    if (-not $accounts) {
        throw "No GitHub SSH accounts found."
    }

    $found = $accounts | Where-Object { $_.Account -eq $Account }
    if (-not $found) {
        throw "Account '$Account' not found. Run 'gh-accounts list' to see available accounts."
    }

    $foundEmail = $found[0].Email
    $foundAlias = $found[0].Alias
    $gitName = $Account

    if ($Scope -eq "global") {
        $null = git config --global user.name $gitName
        $null = git config --global user.email $foundEmail
        $scopeLabel = "global config"
    } else {
        $inRepo = git rev-parse --is-inside-work-tree 2>$null
        if (-not $inRepo) {
            throw "Not inside a git repository. Use --global or navigate to a repo first."
        }
        $null = git config --local user.name $gitName
        $null = git config --local user.email $foundEmail
        $scopeLabel = "this repository"
    }

    Write-Success "Switched git identity for ${scopeLabel}:"
    Write-Host ""
    Write-Host "  user.name  = $gitName"
    Write-Host "  user.email = $foundEmail"
    Write-Host ""

    if ($Scope -ne "global") {
        Write-Info "Clone/push via: git@${foundAlias}:<org>/<repo>.git"
    }
}

# ===========================================================================
# AGENT MANAGEMENT
# ===========================================================================

function Get-AgentGitHubKeys {
    $agentKeys = ssh-add -l 2>$null
    if (-not $agentKeys -or $agentKeys -match "no identities") { return @() }

    $accounts = Get-ConfigAccounts
    if (-not $accounts) { return @() }

    $ghKeys = @()
    foreach ($a in $accounts) {
        $kp = Get-KeyPath $a.Account
        if (Test-Path "$kp.pub") {
            $fpLine = ssh-keygen -lf "$kp.pub" 2>$null
            if ($fpLine) {
                $fp = ($fpLine.Trim() -split '\s+')[1]
                if ($agentKeys -match [regex]::Escape($fp)) {
                    $ghKeys += $a
                }
            }
        }
    }
    return $ghKeys
}

function Get-GitHubKeyCount {
    return (Get-AgentGitHubKeys).Count
}

function Clear-Agent {
    if (-not (Ensure-SshAgent)) { return }

    $keys = Get-AgentGitHubKeys
    if (-not $keys) {
        Write-Info "No GitHub identities found in ssh-agent. Nothing to clean."
        return
    }

    $removed = 0
    $failed = 0
    foreach ($a in $keys) {
        $kp = Get-KeyPath $a.Account
        $success = $false
        foreach ($f in @("$kp.pub", $kp)) {
            if (Test-Path $f) {
                $null = ssh-add -d $f 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Info "Removed: $($a.Account) ($kp)"
                    $removed++
                    $success = $true
                    break
                }
            }
        }
        if (-not $success) { $failed++ }
    }

    if ($removed -gt 0) {
        Write-Success "Cleaned $removed GitHub identity(ies) from ssh-agent."
    }
    if ($failed -gt 0) {
        Write-Host ""
        Write-Warn "$failed key(s) could not be removed (system agent may re-inject them)."
        Write-Warn "For a permanent fix, run: gh-accounts harden"
    }

    $remaining = ssh-add -l 2>$null
    if ($remaining -and $remaining -notmatch "no identities") {
        Write-Host ""
        Write-Info "Remaining keys in agent:"
        $remaining -split "`n" | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Info "Agent is now empty."
    }
}

function Reset-Agent {
    Write-Info "Resetting agent state for GitHub identities..."
    Write-Host ""
    Clear-Agent
    Write-Host ""
    Write-Success "Agent reset complete. GitHub keys removed, non-GitHub keys preserved."
    Write-Info "Use 'gh-accounts agent-load <name>' to selectively load a key when needed."
}

function Add-AgentKey {
    param([string]$Account)
    Test-AccountName $Account

    $kp = Get-KeyPath $Account
    if (-not (Test-Path $kp)) {
        throw "Private key not found: $kp"
    }

    if (-not (Ensure-SshAgent)) { return }

    if (Test-Path "$kp.pub") {
        $fpLine = ssh-keygen -lf "$kp.pub" 2>$null
        if ($fpLine) {
            $fp = ($fpLine.Trim() -split '\s+')[1]
            $loaded = ssh-add -l 2>$null
            if ($loaded -match [regex]::Escape($fp)) {
                Write-Info "Key for '$Account' is already loaded in ssh-agent."
                return
            }
        }
    }

    $null = ssh-add $kp 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add key to ssh-agent: $kp"
    }
    Write-Success "Loaded key for '$Account' into ssh-agent."
}

function Get-AgentStatus {
    if (-not (Ensure-SshAgent)) {
        Write-Info "ssh-agent is not running. Use 'gh-accounts agent-load <name>' to start it."
        return
    }

    $allKeys = ssh-add -l 2>$null
    if (-not $allKeys -or $allKeys -match "no identities") {
        Write-Info "No identities loaded in ssh-agent."
        return
    }

    $total = ($allKeys -split "`n" | Measure-Object).Count
    $ghCount = (Get-AgentGitHubKeys).Count
    $otherCount = $total - $ghCount

    Write-Host ""
    Write-Info "Agent status:"
    Write-Host "  Total keys:    $total"
    Write-Host "  GitHub keys:   $ghCount"
    Write-Host "  Other keys:    $otherCount"
    Write-Host ""

    if ($ghCount -gt 0) {
        Write-Info "GitHub identities loaded:"
        foreach ($a in (Get-AgentGitHubKeys)) {
            Write-Host "  o $($a.Account)  ($($a.Email))"
        }
        Write-Host ""
    }

    if ($ghCount -gt 1) {
        Write-Warn "Multiple GitHub keys loaded. This may cause 'Too many authentication failures'"
        Write-Warn "on non-GitHub SSH connections. Run 'gh-accounts agent-clean' to fix."
    }
}

function Set-HardenConfig {
    Ensure-SshConfig

    $content = Get-Content $script:GH_SSH_CONFIG -ErrorAction SilentlyContinue
    $alreadyHardened = $false
    $inWildcard = $false
    foreach ($line in $content) {
        if ($line.Trim() -eq "Host *") { $inWildcard = $true; continue }
        if ($inWildcard) {
            if ($line.Trim() -match "^Host ") { break }
            if ($line.Trim() -match "^IdentitiesOnly\s+yes") {
                $alreadyHardened = $true
                break
            }
        }
    }

    if ($alreadyHardened) {
        Write-Info "SSH config is already hardened (Host * / IdentitiesOnly yes)."
        return
    }

    Backup-CreateAuto

    $newContent = New-Object System.Collections.ArrayList
    $headerDone = $false
    foreach ($line in $content) {
        if (-not $headerDone) {
            if ($line.Trim() -match "^Include") {
                [void]$newContent.Add($line)
                continue
            }
            if ($line.Trim() -eq '') {
                [void]$newContent.Add($line)
                continue
            }
            $headerDone = $true
            [void]$newContent.Add("Host *")
            [void]$newContent.Add("    IdentitiesOnly yes")
            [void]$newContent.Add("")
        }
        [void]$newContent.Add($line)
    }
    if (-not $headerDone) {
        [void]$newContent.Add("Host *")
        [void]$newContent.Add("    IdentitiesOnly yes")
        [void]$newContent.Add("")
    }

    Set-Content -Path $script:GH_SSH_CONFIG -Value ($newContent -join "`r`n")
    Set-SshConfigPermissions $script:GH_SSH_CONFIG

    Write-Success "SSH config hardened. Added:"
    Write-Host ""
    Write-Host "  Host *"
    Write-Host "      IdentitiesOnly yes"
    Write-Host ""
    Write-Info "SSH will now only use keys explicitly specified per-host."
    Write-Info "This prevents agent key pollution on non-GitHub connections."
}

# ===========================================================================
# BACKUP & RESTORE
# ===========================================================================

function Backup-Create {
    Ensure-BackupDir

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $script:GH_BACKUP_DIR $timestamp
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

    $count = 0

    if (Test-Path $script:GH_SSH_CONFIG) {
        Copy-Item $script:GH_SSH_CONFIG (Join-Path $backupPath "config") -Force
        $count++
    }

    Get-ChildItem "$($script:GH_SSH_DIR)\$($script:GH_KEY_PREFIX)-*" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $backupPath -Force
        $count++
    }

    if (Test-Path $script:GH_SPLIT_DIR) {
        $splitBackup = Join-Path $backupPath "split"
        New-Item -ItemType Directory -Path $splitBackup -Force | Out-Null
        Get-ChildItem "$($script:GH_SPLIT_DIR)\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName $splitBackup -Force
            $count++
        }
    }

    if ($count -eq 0) {
        Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Warn "Nothing to back up."
        return
    }

    Write-Success "Backup created: $backupPath ($count file(s))."
}

function Backup-CreateAuto {
    Ensure-BackupDir

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $script:GH_BACKUP_DIR "auto_$timestamp"
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

    if (Test-Path $script:GH_SSH_CONFIG) {
        Copy-Item $script:GH_SSH_CONFIG (Join-Path $backupPath "config") -Force
    }

    Get-ChildItem "$($script:GH_SSH_DIR)\$($script:GH_KEY_PREFIX)-*" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $backupPath -Force
    }

    if (Test-Path $script:GH_SPLIT_DIR) {
        $splitBackup = Join-Path $backupPath "split"
        New-Item -ItemType Directory -Path $splitBackup -Force | Out-Null
        Get-ChildItem "$($script:GH_SPLIT_DIR)\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName $splitBackup -Force
        }
    }
}

function Get-BackupList {
    Ensure-BackupDir

    $backups = Get-ChildItem $script:GH_BACKUP_DIR -Directory -ErrorAction SilentlyContinue
    if (-not $backups) {
        Write-Info "No backups found."
        return
    }

    Write-Host ""
    Write-Info "Available backups:"
    Write-Host ""
    foreach ($b in $backups) {
        $fileCount = (Get-ChildItem $b.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        $prefix = ""
        if ($b.Name -match "^auto_") { $prefix = " $($script:CLR_YELLOW)(auto)$($script:CLR_RESET)" }
        Write-Host "  $($script:CLR_BOLD)$($b.Name)$($script:CLR_RESET)  -  ${fileCount} file(s)${prefix}"
    }
    Write-Host ""
}

function Restore-Backup {
    Ensure-BackupDir

    $backups = Get-ChildItem $script:GH_BACKUP_DIR -Directory -ErrorAction SilentlyContinue
    if (-not $backups) {
        throw "No backups available to restore."
    }

    Write-Host ""
    Write-Info "Available backups:"
    Write-Host ""
    $i = 1
    foreach ($b in $backups) {
        $fileCount = (Get-ChildItem $b.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "  [$i] $($b.Name)  ($fileCount files)"
        $i++
    }
    Write-Host ""

    $choice = Read-Host "  Select backup number to restore"
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $backups.Count) {
        throw "Invalid selection."
    }

    $selected = $backups[$idx]
    $restorePath = $selected.FullName

    if (-not (Confirm-Action "Restore from '$($selected.Name)'? Current config and keys will be overwritten.")) {
        Write-Info "Aborted."
        return
    }

    Backup-CreateAuto

    $configFile = Join-Path $restorePath "config"
    if (Test-Path $configFile) {
        Copy-Item $configFile $script:GH_SSH_CONFIG -Force
        Set-SshConfigPermissions $script:GH_SSH_CONFIG
        Write-Info "Restored $($script:GH_SSH_CONFIG)."
    }

    Get-ChildItem "$restorePath\$($script:GH_KEY_PREFIX)-*" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = Join-Path $script:GH_SSH_DIR $_.Name
        Copy-Item $_.FullName $dest -Force
        Set-KeyPermissions $dest
        Write-Info "Restored $dest."
    }

    $splitRestore = Join-Path $restorePath "split"
    if (Test-Path $splitRestore) {
        Ensure-SplitDir
        Get-ChildItem "$splitRestore\github-*" -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $script:GH_SPLIT_DIR $_.Name
            Copy-Item $_.FullName $dest -Force
            Set-KeyPermissions $dest
            Write-Info "Restored $dest."
        }
    }

    Write-Success "Restore from '$($selected.Name)' completed."
}

# ===========================================================================
# DOCTOR
# ===========================================================================

$script:DoctorIssues = 0

function Invoke-Doctor {
    Write-Host ""
    Write-Info "$($script:CLR_BOLD)Running diagnostics...$($script:CLR_RESET)"
    Write-Host ""

    $script:DoctorIssues = 0

    DoctorCheck-Agent
    DoctorCheck-AgentPollution
    DoctorCheck-Permissions
    DoctorCheck-ConfigIntegrity
    DoctorCheck-Keys
    DoctorCheck-Duplicates
    DoctorCheck-SplitMode

    Write-Host ""
    if ($script:DoctorIssues -eq 0) {
        Write-Success "All checks passed. Your setup is healthy."
    } else {
        Write-Warn "$($script:DoctorIssues) issue(s) found. Review the warnings above."
    }
    Write-Host ""
}

function DoctorCheck-Agent {
    Write-Host -NoNewline "  Checking ssh-agent... "

    if (Test-SshAgentRunning) {
        Write-Host "$($script:CLR_GREEN)running$($script:CLR_RESET)"
    } elseif ($env:SSH_AUTH_SOCK) {
        Write-Host "$($script:CLR_YELLOW)socket exists but no keys loaded$($script:CLR_RESET)"
        $script:DoctorIssues++
    } else {
        Write-Host "$($script:CLR_RED)not running$($script:CLR_RESET)"
        Write-Host "    $($script:CLR_YELLOW)-> Start the ssh-agent Windows service: Start-Service ssh-agent$($script:CLR_RESET)"
        $script:DoctorIssues++
    }
}

function DoctorCheck-AgentPollution {
    Write-Host -NoNewline "  Checking agent pollution... "

    $ghCount = Get-GitHubKeyCount
    if ($ghCount -gt 1) {
        Write-Host "$($script:CLR_YELLOW)$ghCount GitHub keys loaded$($script:CLR_RESET)"
        Write-Host "    $($script:CLR_YELLOW)-> Risk: 'Too many authentication failures' on non-GitHub hosts$($script:CLR_RESET)"
        Write-Host "    $($script:CLR_YELLOW)-> Fix: gh-accounts agent-clean$($script:CLR_RESET)"
        $script:DoctorIssues++
    } elseif ($ghCount -eq 1) {
        Write-Host "$($script:CLR_GREEN)1 GitHub key (safe)$($script:CLR_RESET)"
    } else {
        Write-Host "$($script:CLR_GREEN)no GitHub keys in agent$($script:CLR_RESET)"
    }
}

function DoctorCheck-Permissions {
    Write-Host -NoNewline "  Checking ~/.ssh permissions... "

    if (-not (Test-Path $script:GH_SSH_DIR)) {
        Write-Host "$($script:CLR_RED)directory missing$($script:CLR_RESET)"
        $script:DoctorIssues++
        return
    }

    Write-Host "$($script:CLR_GREEN)N/A (Windows ACL)$($script:CLR_RESET)"

    if (Test-Path $script:GH_SSH_CONFIG) {
        Write-Host -NoNewline "  Checking config permissions... "
        Write-Host "$($script:CLR_GREEN)N/A (Windows ACL)$($script:CLR_RESET)"
    }
}

function DoctorCheck-ConfigIntegrity {
    Write-Host -NoNewline "  Checking config integrity... "

    if (-not (Test-Path $script:GH_SSH_CONFIG)) {
        Write-Host "$($script:CLR_YELLOW)no config file$($script:CLR_RESET)"
        return
    }

    $blockIssues = 0
    $currentAccount = $null
    $hasHostname = $false
    $hasIdentity = $false

    Get-Content $script:GH_SSH_CONFIG | ForEach-Object {
        $line = $_
        if ($line -match "^# gh-accounts :: (.+) ") {
            if ($currentAccount -and (-not $hasHostname -or -not $hasIdentity)) {
                Write-Host "$($script:CLR_RED)incomplete block for '$currentAccount'$($script:CLR_RESET)"
                $blockIssues++
            }
            $currentAccount = $matches[1]
            $hasHostname = $false
            $hasIdentity = $false
        }
        if ($line -match "^\s+HostName") { $hasHostname = $true }
        if ($line -match "^\s+IdentityFile") { $hasIdentity = $true }
    }

    if ($currentAccount -and (-not $hasHostname -or -not $hasIdentity)) {
        Write-Host "$($script:CLR_RED)incomplete block for '$currentAccount'$($script:CLR_RESET)"
        $blockIssues++
    }

    if ($blockIssues -eq 0) {
        Write-Host "$($script:CLR_GREEN)valid$($script:CLR_RESET)"
    }

    $script:DoctorIssues += $blockIssues
}

function DoctorCheck-Keys {
    Write-Host -NoNewline "  Checking SSH keys... "

    $accounts = Get-ConfigAccounts
    if (-not $accounts) {
        Write-Host "$($script:CLR_YELLOW)no accounts configured$($script:CLR_RESET)"
        return
    }

    $keyIssues = 0
    foreach ($a in $accounts) {
        if (-not (Test-Path $a.KeyPath)) {
            if ($keyIssues -eq 0) { Write-Host "" }
            Write-Host "    $($script:CLR_RED)x Missing private key for '$($a.Account)': $($a.KeyPath)$($script:CLR_RESET)"
            $keyIssues++
            continue
        }

        if (-not (Test-Path "$($a.KeyPath).pub")) {
            if ($keyIssues -eq 0) { Write-Host "" }
            Write-Host "    $($script:CLR_YELLOW)w Missing public key for '$($a.Account)': $($a.KeyPath).pub$($script:CLR_RESET)"
            $keyIssues++
        }
    }

    if ($keyIssues -eq 0) {
        Write-Host "$($script:CLR_GREEN)all keys valid$($script:CLR_RESET)"
    }

    $script:DoctorIssues += $keyIssues
}

function DoctorCheck-Duplicates {
    Write-Host -NoNewline "  Checking for duplicate aliases... "

    $aliases = Get-AllAliases
    if (-not $aliases) {
        Write-Host "$($script:CLR_GREEN)none$($script:CLR_RESET)"
        return
    }

    $dupes = $aliases | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        Write-Host "$($script:CLR_RED)found duplicates$($script:CLR_RESET)"
        $dupCount = 0
        foreach ($d in $dupes) {
            Write-Host "    $($script:CLR_RED)x Duplicate alias: $($d.Name)$($script:CLR_RESET)"
            $dupCount++
        }
        $script:DoctorIssues += $dupCount
    } else {
        Write-Host "$($script:CLR_GREEN)none$($script:CLR_RESET)"
    }
}

function DoctorCheck-SplitMode {
    Write-Host -NoNewline "  Checking split mode... "

    if (Test-SplitModeEnabled) {
        Write-Host "$($script:CLR_CYAN)enabled$($script:CLR_RESET)"

        if (-not (Test-Path $script:GH_SPLIT_DIR)) {
            Write-Host "    $($script:CLR_YELLOW)w Include directive exists but directory is missing: $($script:GH_SPLIT_DIR)$($script:CLR_RESET)"
            $script:DoctorIssues++
        }
    } else {
        Write-Host "$($script:CLR_CYAN)disabled (unified mode)$($script:CLR_RESET)"
    }
}

# Export functions for the module
Export-ModuleMember -Function @(
    # Utils
    "Write-Info", "Write-Success", "Write-Warn", "Write-Error",
    "Show-Banner", "Get-GhVersion",
    "Test-AccountName", "Test-Email",
    "Get-KeyPath", "Get-HostAlias",
    "Test-KeyExists", "Test-HostExists",
    "Ensure-SshDir", "Ensure-SshConfig", "Ensure-SshAgent",
    "Ensure-SplitDir", "Ensure-BackupDir",
    "Set-KeyPermissions", "Set-SshConfigPermissions",
    "Test-SplitModeEnabled",
    "Get-EmailFromPubkey", "Confirm-Action",
    # Config
    "Add-ConfigUnified", "Add-ConfigSplit",
    "Remove-ConfigUnified", "Remove-ConfigSplit",
    "Update-ConfigEmailUnified", "Update-ConfigEmailSplit",
    "Get-ConfigAccounts", "Get-AllAliases",
    "Enable-SplitMode", "Disable-SplitMode",
    "Merge-Configs", "Split-AllConfigs",
    "Set-DefaultAccount", "Get-KeyPathForAccount",
    # Account
    "New-GhAccount", "Remove-GhAccount",
    "Update-GhAccount", "Test-GhAccount",
    "Get-GhAccounts", "Export-GhAccountsJson",
    "Switch-GhAccount",
    # Agent
    "Get-AgentStatus", "Get-GitHubKeyCount", "Get-AgentGitHubKeys",
    "Add-AgentKey", "Clear-Agent", "Reset-Agent",
    "Set-HardenConfig",
    # Backup
    "Backup-Create", "Backup-CreateAuto",
    "Get-BackupList", "Restore-Backup",
    # Doctor
    "Invoke-Doctor"
)
