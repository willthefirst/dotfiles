#!/usr/bin/env bash
# tools/vscode/merge.sh
# Merge VS Code configuration from layers
#
# Strategy:
# - settings.json: Deep merge (later layers override earlier)
# - keybindings.json: Concatenate arrays (user manages conflicts)
# - snippets/*.code-snippets: Symlink (later layers override)

set -euo pipefail

# Source helpers
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

source "$DOTFILES_DIR/lib/helpers/log.sh"
source "$DOTFILES_DIR/lib/helpers/json-merge.sh"
source "$DOTFILES_DIR/lib/helpers/symlink-factory.sh"
source "$DOTFILES_DIR/lib/helpers/safe-write.sh"

# Parse layer paths from environment (colon-separated)
IFS=':' read -ra layer_paths <<< "$LAYER_PATHS"

log_section "Merging VS Code configuration"

# Ensure target directory exists
mkdir -p "$TARGET"

# 1. Deep merge settings.json from all layers
log_step "Merging settings.json"
settings_files=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -f "$layer_path/settings.json" ]]; then
        settings_files+=("$layer_path/settings.json")
        log_detail "Including: $layer_path/settings.json"
    fi
done

if [[ ${#settings_files[@]} -gt 0 ]]; then
    json_deep_merge "$TARGET/settings.json" "${settings_files[@]}"
    log_ok "Created $TARGET/settings.json"
else
    log_warn "No settings.json found in any layer"
fi

# 2. Merge keybindings.json from all layers
# Keybindings is an array - concatenate arrays (user can manage conflicts)
log_step "Merging keybindings.json"
keybindings_files=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -f "$layer_path/keybindings.json" ]]; then
        keybindings_files+=("$layer_path/keybindings.json")
        log_detail "Including: $layer_path/keybindings.json"
    fi
done

if [[ ${#keybindings_files[@]} -gt 0 ]]; then
    safe_jq_write "$TARGET/keybindings.json" -s 'add' "${keybindings_files[@]}"
    log_ok "Created $TARGET/keybindings.json"
else
    log_warn "No keybindings.json found in any layer"
fi

# 3. Symlink snippet files from layers (later layers override)
log_step "Symlinking snippets"
snippet_dirs=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -d "$layer_path/snippets" ]]; then
        snippet_dirs+=("$layer_path/snippets")
    fi
done

if [[ ${#snippet_dirs[@]} -gt 0 ]]; then
    # Use create_layer_symlinks helper
    create_layer_symlinks "$TARGET/snippets" "*.code-snippets" "${snippet_dirs[@]}"

    # Count symlinked files
    snippet_count=0
    if [[ -d "$TARGET/snippets" ]]; then
        snippet_count=$(find "$TARGET/snippets" -name "*.code-snippets" 2>/dev/null | wc -l | tr -d ' ')
    fi
    log_ok "Symlinked ${snippet_count} snippet file(s)"
else
    log_detail "No snippet directories found"
fi

log_ok "VS Code configuration merged"
