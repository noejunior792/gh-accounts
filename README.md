# gh-accounts

> Manage multiple GitHub SSH identities on Linux, macOS & Windows — securely, scalably, and without external dependencies.

---

## Why This Tool Exists

When you work with multiple GitHub accounts (personal, work, freelance, open-source orgs), SSH key and config management becomes error-prone and tedious. Manually editing `~/.ssh/config`, juggling key files, and remembering host aliases is fragile at scale.

**gh-accounts** automates this entirely — creating keys, configuring SSH, testing auth, and maintaining backups — while enforcing correct permissions and providing clear diagnostics.

---

## Features

- **Create** SSH key pairs and config entries in one command
- **List** all managed accounts with status indicators
- **Delete** accounts and clean up keys + config
- **Update** account email addresses
- **Test** SSH authentication against GitHub
- **Backup** and **restore** your entire SSH configuration
- **Doctor** — diagnostics for permissions, agent, duplicates, integrity
- **Agent management** — clean, reset, load, and inspect SSH agent keys
- **Harden** — prevent agent pollution with `IdentitiesOnly yes`
- **Split mode** — optional per-account config files for team/org setups
- **Merge / split** configs between unified and split modes
- **Export** accounts as structured JSON
- Zero external dependencies — only native tools (Linux: coreutils, grep, sed; Windows: PowerShell + OpenSSH)

---

## Installation

### Linux & macOS

#### From source (recommended)

```bash
git clone https://github.com/noejunior299/gh-accounts.git
cd gh-accounts
sudo bash install.sh
```

#### One-liner (remote)

```bash
curl -fsSL https://raw.githubusercontent.com/noejunior299/gh-accounts/main/install.sh | sudo bash
```

### Windows

> Requires **PowerShell 5.1+** and **OpenSSH Client** (built-in on Windows 10 1809+).

#### From source (recommended)

```powershell
git clone https://github.com/noejunior299/gh-accounts.git
cd gh-accounts
PowerShell -ExecutionPolicy Bypass -File install.ps1
```

#### One-liner (remote, run as Administrator)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; $s=(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/noejunior299/gh-accounts/main/install.ps1'); iex $s
```

> **Note:** Run PowerShell as **Administrator** for the installer. The script copies files to `%ProgramFiles%\gh-accounts\` and adds the `bin\` folder to your user PATH.

#### Verify OpenSSH Client

```powershell
# Check if OpenSSH Client is installed
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'

# Install if missing (requires Administrator)
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

### Uninstall

#### Linux & macOS

```bash
sudo bash uninstall.sh
```

Or if installed remotely:

```bash
sudo rm -f /usr/local/bin/gh-accounts
sudo rm -rf /usr/local/share/gh-accounts
```

#### Windows

```powershell
PowerShell -ExecutionPolicy Bypass -File uninstall.ps1
```

---

## Usage

### Create an account

```bash
gh-accounts create work work@company.com
gh-accounts create personal me@gmail.com
```

This will:
1. Generate an `ed25519` SSH key pair at `~/.ssh/github-<name>`
2. Add a `Host github-<name>` block to `~/.ssh/config`
3. Print the public key for you to add to GitHub

> **Note:** Keys are no longer auto-loaded into the agent. Use `agent-load` to load a key on demand.

### List accounts

```bash
gh-accounts list
```

### Test authentication

```bash
gh-accounts test work
```

### Update email

```bash
gh-accounts update work --email new@company.com
```

### Delete an account

```bash
gh-accounts delete personal
```

### Backup & Restore

```bash
gh-accounts backup
gh-accounts restore
```

### Diagnostics

```bash
gh-accounts doctor
```

### Export as JSON

```bash
gh-accounts export --json
```

### Agent management

```bash
gh-accounts agent-status           # Show loaded keys and GitHub identity count
gh-accounts agent-load work        # Load a specific account key into the agent
gh-accounts agent-clean            # Remove all GitHub keys from the agent
gh-accounts agent-reset            # Same as clean — reset agent to a clean state
gh-accounts harden                 # Add 'IdentitiesOnly yes' to SSH config (persistent fix)
```

`agent-status` shows how many keys are loaded, which belong to GitHub accounts, and warns if more than one is active (which can cause auth failures on non-GitHub hosts).

`harden` writes a global `Host *` block with `IdentitiesOnly yes` so SSH only uses the key specified in each Host block — even if the agent has many keys loaded. This is the permanent fix for agent pollution.

### Split mode

```bash
gh-accounts split-mode enable     # Per-account files in ~/.ssh/gh-accounts/
gh-accounts split-mode disable    # Remove Include directive
gh-accounts merge-configs         # Merge split files back into unified config
```

### Switch git identity

```bash
gh-accounts switch work              # sets user.name + user.email in the current repo
gh-accounts switch personal --global  # sets them globally (~/.gitconfig)
```

This runs `git config user.name` and `git config user.email` so your commits are attributed to the correct account — no manual editing needed.

### Set default account

```bash
gh-accounts set-default work
```

This adds a `Host github.com` block to your SSH config, so you can clone repos without a prefix:

```bash
git clone git@github.com:user/repo.git  # uses the default account
```

Other accounts still work with their prefixes:

```bash
git clone git@github-work:org/repo.git
```

> **Note:** Only one account can be default at a time. Setting a new default replaces the previous one.

### Clone with a specific account

```bash
git clone git@github-work:org/repo.git
git clone git@github-personal:user/repo.git
```

---

## Architecture

```
gh-accounts/
├── bin/
│   ├── gh-accounts          # CLI entry point (Bash — Linux/macOS)
│   ├── gh-accounts.ps1      # CLI entry point (PowerShell — Windows)
│   └── gh-accounts.cmd      # Wrapper (Windows, created by install.ps1)
├── lib/
│   ├── utils.sh             # Colors, logging, validation, constants (Bash)
│   ├── config.sh            # SSH config read/write (Bash)
│   ├── account.sh           # Account CRUD, test, export (Bash)
│   ├── agent.sh             # SSH agent management (Bash)
│   ├── backup.sh            # Backup and restore (Bash)
│   ├── doctor.sh            # Diagnostic checks (Bash)
│   ├── GhAccounts.psm1      # PowerShell module (all functions)
│   └── GhAccounts.psd1      # PowerShell module manifest
├── install.sh               # System-wide installer (Linux/macOS)
├── uninstall.sh             # Clean uninstaller (Linux/macOS)
├── install.ps1              # System-wide installer (Windows)
├── uninstall.ps1            # Clean uninstaller (Windows)
├── VERSION                  # Semantic version
├── LICENSE                  # MIT
└── README.md
```

Each module is independently sourced by the CLI. The entry point (`bin/gh-accounts`) resolves the library directory whether run from source or from `/usr/local/`.

---

## Unified vs. Split Mode

### Unified (default)

All account host blocks live in a single file:

```
~/.ssh/config
```

```ssh-config
# gh-accounts :: work <work@company.com>
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-work
    IdentitiesOnly yes

# gh-accounts :: personal <me@gmail.com>
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-personal
    IdentitiesOnly yes
```

### Split mode

Each account gets its own file under `~/.ssh/gh-accounts/`:

```
~/.ssh/gh-accounts/github-work
~/.ssh/gh-accounts/github-personal
```

The main config includes them via:

```ssh-config
Include ~/.ssh/gh-accounts/*
```

Split mode is useful when:
- You share config snippets across machines via dotfiles
- You want per-account version control
- You manage a large number of identities

Switch freely between modes — `merge-configs` and `split-mode enable/disable` handle the migration.

---

## Security

- **Private keys** are generated with `ed25519` (modern, fast, secure)
- **Permissions** are enforced automatically:
  - `~/.ssh/` → `700`
  - Private keys → `600`
  - Public keys → `644`
  - Config files → `600`
- **Automatic backups** are created before any destructive operation
- **ssh-agent** is validated and started if needed
- **Duplicate detection** prevents alias collisions
- **No secrets** are ever printed or logged (only public keys)

### Agent isolation

Loading multiple SSH keys into `ssh-agent` globally causes **agent pollution** — OpenSSH offers all loaded keys to every host, which can trigger `Too many authentication failures` on non-GitHub servers.

**gh-accounts** prevents this by:

1. **Not auto-loading keys** — `create` no longer runs `ssh-add`. Load keys explicitly with `agent-load`.
2. **`harden` command** — adds `Host * / IdentitiesOnly yes` to your SSH config, ensuring each connection only uses the key specified in its `IdentityFile` directive.
3. **`agent-clean`** — removes GitHub keys from the agent when you need a clean slate.
4. **`doctor`** — detects agent pollution and suggests remediation.

> **Note:** Desktop environments using GNOME Keyring as the SSH agent may re-inject keys after removal. Running `gh-accounts harden` is the permanent fix in those environments.

---

## Compatibility

| Requirement | Supported |
|---|---|---|
| Linux (any distro) | ✅ |
| macOS | ✅ |
| Windows 10 1809+ | ✅ (native, via PowerShell + OpenSSH Client) |
| Bash 4.3+ / 5.x | ✅ |
| Fish shell | ✅ (CLI is bash, works from any shell) |
| PowerShell 5.1+ | ✅ |
| OpenSSH | ✅ (ssh, ssh-keygen, ssh-agent, ssh-add) |
| External deps | None — only OS-native tools (Linux: coreutils, grep, sed, awk / Windows: PowerShell + OpenSSH) |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit with clear messages
4. Open a Pull Request against `main`

### Guidelines

- Keep modules under 300 lines
- Use functions — no inline logic
- Add color-coded output for user-facing messages
- Validate all inputs
- Fail safely — never leave config in a broken state
- Test on Ubuntu 22.04+ with bash 5.x

---

## Roadmap

- [x] `gh-accounts switch <name> [--global]` — set `user.name` and `user.email` for the current repo (default) or globally, so commits are attributed to the correct identity
- [x] `gh-accounts set-default <name>` — set an account as the default for `github.com` (no prefix needed for clones)
- [x] `gh-accounts agent-*` / `harden` — SSH agent management and pollution prevention
- [ ] `gh-accounts import` — import existing SSH keys into management
- [ ] `gh-accounts config` — interactive setup wizard
- [ ] Shell completions for bash and fish
- [ ] Man page generation
- [ ] Optional GPG-signed key metadata
- [ ] CI/CD pipeline with ShellCheck and BATS tests
- [ ] AUR / PPA / Snap packaging

---

## License

[MIT](LICENSE)

---

**gh-accounts** — One machine. Many GitHub identities. Zero friction.
