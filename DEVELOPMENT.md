# gh-accounts Development Guide

This document outlines the development setup, testing, and contribution workflow for **gh-accounts**.

## Project Structure

```
gh-accounts/
├── bin/
│   └── gh-accounts                # CLI entry point
├── lib/
│   ├── utils.sh                   # Shared utilities, logging, colors
│   ├── config.sh                  # SSH config read/write operations
│   ├── account.sh                 # Account CRUD operations
│   ├── agent.sh                   # SSH agent management
│   ├── agent-worktree.sh          # Per-agent Git worktree isolation
│   ├── backup.sh                  # Backup and restore functionality
│   └── doctor.sh                  # Diagnostic checks
├── tests/
│   ├── utils.bats                 # Tests for utils.sh
│   ├── config.bats                # Tests for config.sh
│   ├── account.bats               # Tests for account.sh
│   ├── agent.bats                 # Tests for agent.sh
│   ├── agent-worktree.bats        # Tests for agent-worktree.sh
│   ├── backup.bats                # Tests for backup.sh
│   └── doctor.bats                # Tests for doctor.sh
├── completions/
│   ├── gh-accounts.bash           # Bash completion script
│   └── gh-accounts.fish           # Fish shell completion script
├── man/
│   └── gh-accounts.1              # Man page (troff format)
├── install.sh                     # System-wide installer
├── uninstall.sh                   # System-wide uninstaller
├── VERSION                        # Semantic version (e.g., 1.0.0)
├── LICENSE                        # MIT license
├── README.md                       # User documentation
└── DEVELOPMENT.md                 # This file
```

## Setup for Development

### Prerequisites

- Bash 4.3+ or 5.x
- OpenSSH (ssh, ssh-keygen, ssh-agent, ssh-add)
- BATS (for testing): `sudo apt install bats` (Ubuntu/Debian)
- ShellCheck (for linting): `sudo apt install shellcheck` (Ubuntu/Debian)

### Install from source (development mode)

```bash
git clone https://github.com/noejunior299/gh-accounts.git
cd gh-accounts

# No installation needed for local testing. Run directly:
./bin/gh-accounts --help
```

### Running locally during development

```bash
# From the repository root:
bash bin/gh-accounts create test test@example.com
bash bin/gh-accounts list
bash bin/gh-accounts doctor
```

## Testing

### Run BATS test suite

```bash
# Install BATS if not already installed
sudo apt install bats

# Run all tests
cd /path/to/gh-accounts
bats tests/*.bats

# Run a single test file
bats tests/utils.bats

# Run tests matching a pattern
bats tests/utils.bats -f "version"
```

### Run ShellCheck linting

```bash
# Check all shell scripts
shellcheck -x bin/* lib/*.sh install.sh uninstall.sh

# With relaxed strictness (warning level)
shellcheck -S warning -x bin/* lib/*.sh install.sh uninstall.sh

# Check specific file
shellcheck lib/account.sh
```

### Verify library imports

```bash
# Test that all modules can be sourced without errors
bash -c 'source lib/utils.sh && source lib/config.sh && source lib/account.sh && source lib/agent.sh && source lib/agent-worktree.sh && source lib/backup.sh && source lib/doctor.sh && echo "✅ All libraries loaded successfully"'
```

### Test installation script

```bash
# Verify installation script syntax (doesn't execute)
bash -n install.sh
bash -n uninstall.sh

# Test on a clean system (optional, use Docker):
docker run -it ubuntu:latest bash -c "
  cd /tmp && \
  curl -fsSL https://raw.githubusercontent.com/noejunior299/gh-accounts/main/install.sh > install.sh && \
  sudo bash install.sh
"
```

## Continuous Integration

The GitHub Actions pipeline (`.github/workflows/ci.yml`) has been removed. Linting and tests are run locally during development:

### Jobs

1. **Lint** — ShellCheck validation
2. **Test** — BATS test suite (multiple bash versions)
3. **Install** — Verify installation script syntax and library loading
4. **Security** — Check for hardcoded secrets
5. **Coverage** — Code metrics and file listing

Run these locally with:

```bash
shellcheck -x bin/* lib/*.sh install.sh uninstall.sh
bats tests/*.bats
```

## Code Style Guidelines

### Shell Script Standards

- **Indentation**: 4 spaces (no tabs)
- **Shebang**: `#!/usr/bin/env bash`
- **Set options**: `set -euo pipefail` at the top of scripts
- **Comments**: Use `#` for comments; explain *why*, not *what*
- **Functions**: Group related functions; keep under 50 lines each
- **Variables**: Use UPPERCASE for constants, lowercase for locals
- **Quoting**: Always quote variables: `"${var}"`, not `$var`
- **Error handling**: Use explicit error messages and `die()` for fatal errors

### Example function

```bash
# Brief description of what the function does
# Arguments: $1 = account name, $2 = email
# Returns: 0 on success, 1 on error
my_function() {
    local name="${1:-}"
    local email="${2:-}"

    [[ -z "$name" ]] && die "Missing account name"
    [[ -z "$email" ]] && die "Missing email"

    log_info "Creating account: $name"
    # ... rest of function
}
```

## Adding New Features

1. **Create a new function** in the appropriate module (lib/*.sh)
2. **Add tests** in tests/ for your function
3. **Run ShellCheck** to validate syntax
4. **Run BATS tests** to verify functionality
5. **Update README.md** if the feature is user-facing
6. **Update this file** if it affects development workflow

### Example: Adding a new command

If adding a command `gh-accounts foo <name>`:

1. Create `foo_operation()` function in appropriate lib/module.sh
2. Add test file `tests/foo.bats` with relevant test cases
3. Add case statement in `bin/gh-accounts` main router:
   ```bash
   foo)
       print_banner
       local name="${1:-}"
       [[ -z "$name" ]] && die "Usage: gh-accounts foo <name>"
       foo_operation "${name}"
       ;;
   ```
4. Update README.md with usage example
5. Run full test suite and verify CI passes

## Shell Completions

### Bash

Install to system:

```bash
sudo cp completions/gh-accounts.bash /usr/share/bash-completion/completions/gh-accounts
```

For local testing:

```bash
source completions/gh-accounts.bash
# Then test with: gh-accounts <TAB>
```

### Fish

Install to system:

```bash
mkdir -p ~/.config/fish/completions
cp completions/gh-accounts.fish ~/.config/fish/completions/
```

## Man Page

### View locally

```bash
man -l man/gh-accounts.1
```

### Install system-wide

```bash
sudo cp man/gh-accounts.1 /usr/share/man/man1/
sudo mandb  # Update man page database
```

## Version Management

Version is stored in the `VERSION` file (semantic versioning):

```
1.0.0
```

To bump version:

```bash
echo "1.1.0" > VERSION
git add VERSION
git commit -m "chore: bump version to 1.1.0"
```

## Committing Changes

Follow conventional commit format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Adding/updating tests
- `chore:` Maintenance tasks

Example:

```bash
git add -A
git commit -m "feat: add import command to migrate existing SSH keys

This allows users to import existing SSH keys that are not yet
managed by gh-accounts.

Closes #15"
```

Always include the co-authored trailer:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

## Troubleshooting

### Test failures

If BATS tests fail, check:

1. That all functions are properly sourced
2. That temporary directories are created correctly
3. That permission modes match expectations (use `stat -c %a`)
4. That grep patterns don't have regex escaping issues

### ShellCheck warnings

If ShellCheck reports issues:

1. Read the warning carefully (SC#### codes are documented at https://www.shellcheck.net/)
2. Fix the issue if it's a genuine error
3. If it's a false positive, add `# shellcheck disable=SC####` above the line

### CI failures

CI is currently disabled (workflow removed). If re-added, check the GitHub Actions output at: https://github.com/noejunior299/gh-accounts/actions

Common issues:

- Bash version incompatibilities (test with both 4.4 and 5.x)
- Missing dependencies in the CI environment
- Path assumptions (always use relative paths or `$BASH_SOURCE`)

## Resources

- [BATS Testing Framework](https://github.com/bats-core/bats-core)
- [ShellCheck](https://www.shellcheck.net/)
- [Bash Best Practices](https://mywiki.wooledge.org/BashGuide)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [OpenSSH Man Pages](https://man.openbsd.org/ssh)

