#!/usr/bin/env bash
# tools/claude/merge.sh
# Merge Claude Code settings into ~/.claude
# Only symlinks settings.json, preserves other Claude data (history, cache, etc.)

set -euo pipefail

source "${DOTFILES_DIR}/lib/helpers/log.sh"
source "${DOTFILES_DIR}/lib/helpers/symlink-factory.sh"

IFS=':' read -ra layer_paths <<< "$LAYER_PATHS"

# Create target directory if needed
mkdir -p "$TARGET"

# Find the last layer with settings.json (last wins)
settings_source=""
for layer_path in "${layer_paths[@]}"; do
    [[ -f "$layer_path/settings.json" ]] && settings_source="$layer_path/settings.json"
done

if [[ -n "$settings_source" ]]; then
    log_step "Symlinking settings.json"
    symlink_with_backup "$settings_source" "$TARGET/settings.json"
fi

# Find the last layer with commands directory (last wins)
commands_source=""
for layer_path in "${layer_paths[@]}"; do
    [[ -d "$layer_path/commands" ]] && commands_source="$layer_path/commands"
done

if [[ -n "$commands_source" ]]; then
    log_step "Symlinking commands directory"
    symlink_with_backup "$commands_source" "$TARGET/commands"
fi

log_ok "Claude settings configured"
