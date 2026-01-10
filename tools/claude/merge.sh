#!/usr/bin/env bash
# tools/claude/merge.sh
# Merge Claude Code settings into ~/.claude
# Only symlinks settings.json, preserves other Claude data (history, cache, etc.)

set -euo pipefail

source "${DOTFILES_DIR}/lib/helpers/log.sh"
source "${DOTFILES_DIR}/lib/dotfiles-system/lib/utils.sh"

# Disable unbound variable check for associative arrays
set +u

IFS=':' read -ra layer_paths <<< "$LAYER_PATHS"

# Create target directory if needed
mkdir -p "$TARGET"

# Process layers in order (last layer wins for conflicts)
for layer_path in "${layer_paths[@]}"; do
    if [[ -f "$layer_path/settings.json" ]]; then
        target_file="$TARGET/settings.json"

        # Backup existing file if it's not already a symlink to our config
        if [[ -e "$target_file" && ! -L "$target_file" ]]; then
            log_detail "Backing up existing settings.json"
            safe_remove "$target_file"
        elif [[ -L "$target_file" ]]; then
            # Remove existing symlink
            rm -f "$target_file"
        fi

        log_step "Symlinking settings.json"
        log_detail "From: $layer_path"
        ln -sf "$layer_path/settings.json" "$target_file"
    fi
done

log_ok "Claude settings configured"
