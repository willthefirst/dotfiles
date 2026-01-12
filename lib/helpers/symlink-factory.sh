#!/usr/bin/env bash
# lib/helpers/symlink-factory.sh
# Symlink creation utilities with backup support

# Source logging utilities if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# Ensure required functions are available
_require_utils() {
    if ! declare -f safe_remove &>/dev/null; then
        source "${DOTFILES_DIR:-$HOME/.dotfiles}/lib/dotfiles-system/lib/utils.sh"
    fi
}

# Create symlink with automatic backup of existing file
# Usage: symlink_with_backup source target
symlink_with_backup() {
    _require_utils
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
        log_warn "Source does not exist: $source"
        return 1
    fi

    # Create parent directory if needed
    local target_dir=$(dirname "$target")
    [[ -d "$target_dir" ]] || mkdir -p "$target_dir"

    # Remove existing (with backup)
    if [[ -e "$target" || -L "$target" ]]; then
        safe_remove "$target"
    fi

    ln -sf "$source" "$target"
    log_detail "Symlinked: $target -> $source"
}

# Create symlinks for all files matching pattern in a directory
# Later layers override earlier layers for same filename
# Usage: create_layer_symlinks target_dir pattern layer_paths_array
# Example: create_layer_symlinks "$HOME/.config/vscode/snippets" "*.code-snippets" layer_paths
create_layer_symlinks() {
    _require_utils
    local target_dir="$1"
    local pattern="$2"
    shift 2
    local -a layer_paths=("$@")

    # Track files across layers (later wins)
    declare -A file_map

    for layer_path in "${layer_paths[@]}"; do
        [[ -d "$layer_path" ]] || continue

        for file in "$layer_path"/$pattern; do
            [[ -f "$file" ]] || continue
            local filename=$(basename "$file")
            file_map["$filename"]="$file"
        done
    done

    # Create target directory
    mkdir -p "$target_dir"

    # Create symlinks
    for filename in "${!file_map[@]}"; do
        local source="${file_map[$filename]}"
        local target="$target_dir/$filename"
        symlink_with_backup "$source" "$target"
    done
}

# Symlink entire directory (for simple configs like ghostty)
# Usage: symlink_directory source target
symlink_directory() {
    _require_utils
    local source="$1"
    local target="$2"

    if [[ ! -d "$source" ]]; then
        log_warn "Source directory does not exist: $source"
        return 1
    fi

    local target_parent=$(dirname "$target")
    [[ -d "$target_parent" ]] || mkdir -p "$target_parent"

    if [[ -e "$target" || -L "$target" ]]; then
        safe_remove "$target"
    fi

    ln -sf "$source" "$target"
    log_detail "Symlinked directory: $target -> $source"
}
