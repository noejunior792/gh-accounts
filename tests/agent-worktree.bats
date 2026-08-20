#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: agent-worktree.bats
# Tests for per-agent Git worktree isolation
# =============================================================================

setup() {
    source lib/utils.sh
    source lib/config.sh
    source lib/account.sh
    source lib/agent-worktree.sh
}

# ---------------------------------------------------------------------------
# Worktree functions exist
# ---------------------------------------------------------------------------
@test "agent_worktree_create function exists" {
    declare -f agent_worktree_create > /dev/null
}

@test "agent_worktree_list function exists" {
    declare -f agent_worktree_list > /dev/null
}

@test "agent_worktree_run function exists" {
    declare -f agent_worktree_run > /dev/null
}

@test "agent_worktree_destroy function exists" {
    declare -f agent_worktree_destroy > /dev/null
}

# ---------------------------------------------------------------------------
# Naming convention & isolation primitives
# ---------------------------------------------------------------------------
@test "worktree path uses ../<repo>--<agent> convention" {
    local p
    p="$(agent_worktree_path /tmp/opencode/repo agentX)"
    [[ "${p}" == "/tmp/opencode/repo--agentX" ]]
}

@test "resolve_repo fails outside a git repository" {
    run agent_worktree_resolve_repo /tmp
    [[ "${status}" -ne 0 ]]
}

@test "per-worktree identity isolation uses --worktree config" {
    grep -q "config --worktree user.name" "$BATS_TEST_DIRNAME/../lib/agent-worktree.sh"
    grep -q "config --worktree user.email" "$BATS_TEST_DIRNAME/../lib/agent-worktree.sh"
}

@test "create enables per-worktree config extension" {
    grep -q "extensions.worktreeConfig true" "$BATS_TEST_DIRNAME/../lib/agent-worktree.sh"
}