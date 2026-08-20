#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: agent-worktree.sh
# Per-agent Git worktree isolation for AI coding agents.
#
# Each agent gets its own linked worktree (../<repo>--<agent>) with an
# isolated per-worktree git identity, so parallel agents never collide on the
# same branch or commit under the wrong identity.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
agent_worktree_path() {
    local repo="${1}"
    local agent="${2}"
    echo "$(dirname "${repo}")/$(basename "${repo}")--${agent}"
}

agent_worktree_resolve_repo() {
    local repo="${1:-}"
    if [[ -z "${repo}" ]]; then
        repo="$(pwd)"
    fi
    repo="$(cd "${repo}" && pwd)"
    if ! git -C "${repo}" rev-parse --is-inside-work-tree &>/dev/null; then
        die "Not a git repository: ${repo}"
    fi
    echo "${repo}"
}

agent_worktree_account_email() {
    local account="${1}"
    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true
    if [[ -z "${accounts}" ]]; then
        return 1
    fi
    while IFS='|' read -r acct email _ _ _ _; do
        if [[ "${acct}" == "${account}" ]]; then
            echo "${email}"
            return 0
        fi
    done <<< "${accounts}"
    return 1
}

# ---------------------------------------------------------------------------
# agent create <name> [repo] [--account <account>]
# ---------------------------------------------------------------------------
agent_worktree_create() {
    local agent="${1:-}"
    shift || die "Usage: gh-accounts agent create <agent> [repo] [--account <account>]"
    local repo_arg="" account=""
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --account)
                account="${2:-}"
                shift 2 || die "Missing value for --account"
                ;;
            *)
                if [[ -z "${repo_arg}" ]]; then
                    repo_arg="${1}"
                    shift
                else
                    die "Unexpected argument: ${1}"
                fi
                ;;
        esac
    done

    validate_account_name "${agent}"
    if [[ -n "${account}" ]]; then
        validate_account_name "${account}"
    fi

    local repo
    repo="$(agent_worktree_resolve_repo "${repo_arg}")"
    local wt
    wt="$(agent_worktree_path "${repo}" "${agent}")"

    if [[ -d "${wt}" ]]; then
        die "Worktree already exists for agent '${agent}': ${wt}"
    fi

    log_info "Creating worktree for agent '${agent}'..."
    git -C "${repo}" worktree add --detach "${wt}" >/dev/null
    log_success "Worktree created: ${wt}"

    # Enable per-worktree config so identity is isolated per agent
    git -C "${repo}" config extensions.worktreeConfig true

    if [[ -n "${account}" ]]; then
        local email
        if email="$(agent_worktree_account_email "${account}")"; then
            git -C "${wt}" config --worktree user.name "${account}"
            git -C "${wt}" config --worktree user.email "${email}"
            log_success "Identity set (per-worktree): user.name=${account}, user.email=${email}"
        else
            log_warn "Account '${account}' not found; worktree identity left unset."
        fi
    else
        log_info "No --account given; worktree inherits the repo's existing git identity."
    fi
}

# ---------------------------------------------------------------------------
# agent list [repo]
# ---------------------------------------------------------------------------
agent_worktree_list() {
    local repo_arg="${1:-}"
    local repo
    repo="$(agent_worktree_resolve_repo "${repo_arg}")"

    local wts
    wts="$(git -C "${repo}" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')" || true

    if [[ -z "${wts}" ]]; then
        log_info "No worktrees in ${repo}."
        return 0
    fi

    local header=0
    while IFS= read -r wt; do
        local base agent
        base="$(basename "${wt}")"
        [[ "${base}" != *"--"* ]] && continue
        agent="${base##*--}"
        if [[ ${header} -eq 0 ]]; then
            echo ""
            printf "  ${CLR_BOLD}%-18s %-46s %-16s %-32s${CLR_RESET}\n" "AGENT" "WORKTREE" "IDENTITY" "EMAIL"
            printf "  %-18s %-46s %-16s %-32s\n" "─────" "────────" "────────" "─────"
            header=1
        fi
        local name email
        name="$(git -C "${wt}" config --worktree user.name 2>/dev/null || echo "-")"
        email="$(git -C "${wt}" config --worktree user.email 2>/dev/null || echo "-")"
        printf "  %-18s %-46s %-16s %-32s\n" "${agent}" "${wt}" "${name}" "${email}"
    done <<< "${wts}"

    if [[ ${header} -eq 0 ]]; then
        log_info "No agent worktrees found in ${repo}."
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# agent run <name> [repo] [--rm] -- <command...>
# ---------------------------------------------------------------------------
agent_worktree_run() {
    local agent="${1:-}"
    shift || die "Usage: gh-accounts agent run <agent> [repo] [--rm] -- <command>"

    local repo_arg="" rm_after=0
    local cmd=()
    local parse=1
    while [[ $# -gt 0 ]]; do
        if [[ ${parse} -eq 1 ]] && [[ "${1}" == "--" ]]; then
            parse=0
            shift
            continue
        fi
        if [[ ${parse} -eq 1 ]]; then
            case "${1}" in
                --rm)
                    rm_after=1
                    shift
                    ;;
                *)
                    if [[ -z "${repo_arg}" ]]; then
                        repo_arg="${1}"
                        shift
                    else
                        die "Unexpected argument: ${1}"
                    fi
                    ;;
            esac
        else
            cmd+=("${1}")
            shift
        fi
    done

    if [[ -z "${agent}" ]] || [[ ${#cmd[@]} -eq 0 ]]; then
        die "Usage: gh-accounts agent run <agent> [repo] [--rm] -- <command>"
    fi
    validate_account_name "${agent}"

    local repo
    repo="$(agent_worktree_resolve_repo "${repo_arg}")"
    local wt
    wt="$(agent_worktree_path "${repo}" "${agent}")"

    if [[ ! -d "${wt}" ]]; then
        die "No worktree for agent '${agent}'. Create it first with 'gh-accounts agent create'."
    fi

    log_info "Running in agent worktree: ${wt}"
    ( cd "${wt}" && "${cmd[@]}" )
    local status=$?

    if [[ ${rm_after} -eq 1 ]]; then
        git -C "${repo}" worktree remove --force "${wt}"
        log_success "Removed worktree '${agent}' after run."
    fi
    return ${status}
}

# ---------------------------------------------------------------------------
# agent destroy <name> [repo]
# ---------------------------------------------------------------------------
agent_worktree_destroy() {
    local agent="${1:-}"
    shift || die "Usage: gh-accounts agent destroy <agent> [repo]"
    local repo_arg="${1:-}"

    if [[ -z "${agent}" ]]; then
        die "Usage: gh-accounts agent destroy <agent> [repo]"
    fi
    validate_account_name "${agent}"

    local repo
    repo="$(agent_worktree_resolve_repo "${repo_arg}")"
    local wt
    wt="$(agent_worktree_path "${repo}" "${agent}")"

    if [[ ! -d "${wt}" ]]; then
        die "No worktree for agent '${agent}': ${wt}"
    fi

    git -C "${repo}" worktree remove --force "${wt}"
    log_success "Removed worktree for agent '${agent}'."
}