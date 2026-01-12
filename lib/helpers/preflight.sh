#!/usr/bin/env bash
# Pre-flight checks before installation

[[ -n "${_DOTFILES_PREFLIGHT_LOADED:-}" ]] && return 0
_DOTFILES_PREFLIGHT_LOADED=1

source "${BASH_SOURCE%/*}/log.sh"

run_preflight_checks() {
    local failed=0
    log_section "Running pre-flight checks"

    # Check backup directory writable
    local backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        log_error "Cannot create backup directory: $backup_dir"
        ((failed++))
    else
        local test_file="$backup_dir/.write_test_$$"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Backup directory not writable: $backup_dir"
            ((failed++))
        else
            rm -f "$test_file"
            log_ok "Backup directory: $backup_dir"
        fi
    fi

    # Check required commands
    local missing=()
    for cmd in jq git curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        ((failed++))
    else
        log_ok "Required commands available"
    fi

    # Check disk space (100MB minimum)
    local available_kb=$(df -k "$backup_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    if [[ $available_mb -lt 100 ]]; then
        log_error "Low disk space: ${available_mb}MB (need 100MB)"
        ((failed++))
    else
        log_ok "Disk space: ${available_mb}MB available"
    fi

    [[ $failed -eq 0 ]]
}
