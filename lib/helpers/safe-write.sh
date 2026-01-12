#!/usr/bin/env bash
# Safe file writing utilities that always create backups

[[ -n "${_DOTFILES_SAFE_WRITE_LOADED:-}" ]] && return 0
_DOTFILES_SAFE_WRITE_LOADED=1

source "${BASH_SOURCE%/*}/log.sh"
source "${DOTFILES_DIR:-$HOME/.dotfiles}/lib/dotfiles-system/lib/utils.sh"

# Write content to file with automatic backup
# Returns: 0 on success, 1 on backup failure (aborts write)
safe_write_file() {
    local target="$1"
    local content="${2:-}"

    # Read from stdin if no content provided
    if [[ -z "$content" && ! -t 0 ]]; then
        content=$(cat)
    fi

    mkdir -p "$(dirname "$target")"

    if [[ -e "$target" || -L "$target" ]]; then
        if ! safe_remove "$target"; then
            log_error "Backup failed, aborting write to: $target"
            return 1
        fi
    fi

    printf '%s' "$content" > "$target"
}

# Write heredoc content with backup
# Usage: safe_write_heredoc "$target" <<'EOF'
safe_write_heredoc() {
    local target="$1"
    local content
    content=$(cat; echo x)  # Preserve trailing newlines
    content=${content%x}    # Remove the 'x' we added

    mkdir -p "$(dirname "$target")"

    if [[ -e "$target" || -L "$target" ]]; then
        if ! safe_remove "$target"; then
            log_error "Backup failed, aborting write to: $target"
            return 1
        fi
    fi

    printf '%s' "$content" > "$target"
}

# Append to file (backup on first append per session)
declare -A _SAFE_APPEND_BACKED_UP
safe_append_file() {
    local target="$1"
    local content="$2"

    if [[ -z "${_SAFE_APPEND_BACKED_UP[$target]:-}" && (-e "$target" || -L "$target") ]]; then
        local backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
        mkdir -p "$backup_dir"
        cp -a "$target" "$backup_dir/$(basename "$target")_$(date +%Y%m%d_%H%M%S)" || return 1
        _SAFE_APPEND_BACKED_UP[$target]=1
    fi

    printf '%s' "$content" >> "$target"
}

# Run jq and write output safely
# Usage: safe_jq_write output.json [jq flags] 'filter' [input files...]
# Example: safe_jq_write out.json -s 'add' file1.json file2.json
safe_jq_write() {
    local output="$1"
    shift

    if [[ -e "$output" || -L "$output" ]]; then
        if ! safe_remove "$output"; then
            log_error "Backup failed, aborting jq write to: $output"
            return 1
        fi
    fi

    mkdir -p "$(dirname "$output")"
    jq "$@" > "$output"
}

# Install binary with backup
safe_install_binary() {
    local source="$1"
    local name="$2"
    local dest_dir="${3:-${DOTFILES_BIN_DIR:-/usr/local/bin}}"
    local target="$dest_dir/$name"

    chmod +x "$source"

    if [[ -e "$target" || -L "$target" ]]; then
        if ! safe_remove "$target"; then
            log_error "Backup failed, aborting binary install: $target"
            return 1
        fi
    fi

    if [[ -w "$dest_dir" ]]; then
        mv "$source" "$target"
    else
        sudo mv "$source" "$target"
    fi
}
