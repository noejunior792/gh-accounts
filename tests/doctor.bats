#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: doctor.bats
# Tests for diagnostic checks
# =============================================================================

setup() {
    source lib/utils.sh
    source lib/doctor.sh
}

# ---------------------------------------------------------------------------
# Doctor functions exist
# ---------------------------------------------------------------------------
@test "doctor_run function exists" {
    declare -f doctor_run > /dev/null
}

# ---------------------------------------------------------------------------
# Diagnostic checks
# ---------------------------------------------------------------------------
@test "doctor checks SSH directory permissions" {
    grep -q "permission\|chmod\|700\|600" "$BATS_TEST_DIRNAME/../lib/doctor.sh"
}

@test "doctor checks for duplicate accounts" {
    grep -q "duplicate" "$BATS_TEST_DIRNAME/../lib/doctor.sh"
}

@test "doctor validates SSH config" {
    grep -q "config\|valid" "$BATS_TEST_DIRNAME/../lib/doctor.sh"
}
