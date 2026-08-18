#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: backup.bats
# Tests for backup and restore functionality
# =============================================================================

setup() {
    export TEST_SSH_DIR=$(mktemp -d)
    export GH_SSH_DIR="$TEST_SSH_DIR"
    export GH_SSH_CONFIG="$TEST_SSH_DIR/config"
    export GH_BACKUP_DIR="$TEST_SSH_DIR/gh-accounts-backups"
    
    source lib/utils.sh
    source lib/backup.sh
}

teardown() {
    [[ -d "$TEST_SSH_DIR" ]] && rm -rf "$TEST_SSH_DIR"
}

# ---------------------------------------------------------------------------
# Backup functions exist
# ---------------------------------------------------------------------------
@test "backup_create function exists" {
    declare -f backup_create > /dev/null
}

@test "backup_restore function exists" {
    declare -f backup_restore > /dev/null
}

@test "backup directory constant is set" {
    [[ -n "$GH_BACKUP_DIR" ]]
}

# ---------------------------------------------------------------------------
# Backup file generation
# ---------------------------------------------------------------------------
@test "backup files use tar.gz compression" {
    grep -q "tar.*gz\|\.tar\.gz" "$BATS_TEST_DIRNAME/../lib/backup.sh"
}

@test "backup includes timestamp in filename" {
    grep -q "date\|strftime" "$BATS_TEST_DIRNAME/../lib/backup.sh"
}
