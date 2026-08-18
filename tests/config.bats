#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: config.bats
# Tests for SSH config read/write functionality
# =============================================================================

setup() {
    # Setup temporary SSH config for testing
    export TEST_SSH_DIR=$(mktemp -d)
    export GH_SSH_DIR="$TEST_SSH_DIR"
    export GH_SSH_CONFIG="$TEST_SSH_DIR/config"
    export GH_SPLIT_DIR="$TEST_SSH_DIR/gh-accounts"
    
    # Create empty config file
    touch "$GH_SSH_CONFIG"
    chmod 600 "$GH_SSH_CONFIG"
    
    # Source after setting up environment
    source lib/utils.sh
    source lib/config.sh
}

teardown() {
    # Clean up temporary directory
    [[ -d "$TEST_SSH_DIR" ]] && rm -rf "$TEST_SSH_DIR"
}

# ---------------------------------------------------------------------------
# Config file creation and existence
# ---------------------------------------------------------------------------
@test "config_init_ssh_dir creates ~/.ssh if missing" {
    local test_dir=$(mktemp -d)
    rm -rf "$test_dir/.ssh"
    
    GH_SSH_DIR="$test_dir/.ssh" config_init_ssh_dir
    
    [[ -d "$test_dir/.ssh" ]]
    [[ $(stat -c %a "$test_dir/.ssh") == "700" ]]
}

@test "config_init_ssh_dir sets correct permissions on ~/.ssh" {
    config_init_ssh_dir
    
    local perms=$(stat -c %a "$GH_SSH_DIR")
    [[ "$perms" == "700" ]]
}

# ---------------------------------------------------------------------------
# SSH config file operations
# ---------------------------------------------------------------------------
@test "config_read_entry returns empty for non-existent account" {
    local result=$(config_read_entry "nonexistent")
    [[ -z "$result" ]]
}

@test "config_file_exists returns false for missing config" {
    rm -f "$GH_SSH_CONFIG"
    ! config_file_exists
}

@test "config_file_exists returns true when config exists" {
    config_file_exists
}

# ---------------------------------------------------------------------------
# Split mode operations
# ---------------------------------------------------------------------------
@test "config_split_dir_exists returns false when split dir missing" {
    ! config_split_dir_exists
}

@test "split mode functions exist" {
    declare -f config_enable_split_mode > /dev/null
    declare -f config_disable_split_mode > /dev/null
    declare -f config_merge_all > /dev/null
}
