#!/usr/bin/env bash
# lib/helpers/extension-installer.sh
# VS Code extension installation utilities

# Source logging utilities if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# Find the VS Code CLI
_find_code_cli() {
    # Check common locations
    if command -v code &>/dev/null; then
        echo "code"
        return 0
    fi

    # macOS: Check for VS Code in Applications
    if [[ -f "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
        echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        return 0
    fi

    # Linux: Check snap installation
    if [[ -f "/snap/bin/code" ]]; then
        echo "/snap/bin/code"
        return 0
    fi

    return 1
}

# Check if VS Code is available
vscode_available() {
    _find_code_cli &>/dev/null
}

# Get list of installed extensions
# Usage: vscode_list_extensions
vscode_list_extensions() {
    local code_cli
    code_cli=$(_find_code_cli) || { log_warn "VS Code CLI not found"; return 1; }
    "$code_cli" --list-extensions 2>/dev/null
}

# Install a single extension
# Usage: vscode_install_extension extension_id
vscode_install_extension() {
    local ext="$1"
    local code_cli
    code_cli=$(_find_code_cli) || { log_warn "VS Code CLI not found"; return 1; }

    log_detail "Installing extension: $ext"
    "$code_cli" --install-extension "$ext" --force 2>/dev/null
}

# Install extensions from a text file (one extension ID per line)
# Lines starting with # are comments, empty lines are ignored
# Usage: vscode_install_extensions_from_file extensions.txt
vscode_install_extensions_from_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_warn "Extensions file not found: $file"
        return 1
    fi

    local code_cli
    code_cli=$(_find_code_cli) || { log_warn "VS Code CLI not found"; return 1; }

    while IFS= read -r ext || [[ -n "$ext" ]]; do
        # Skip empty lines and comments
        [[ -z "$ext" || "$ext" == \#* ]] && continue
        # Trim whitespace
        ext=$(echo "$ext" | xargs)
        [[ -z "$ext" ]] && continue

        vscode_install_extension "$ext"
    done < "$file"
}

# Install extensions from multiple layer files
# Usage: vscode_install_extensions_from_layers layer_paths extensions_filename
# Example: vscode_install_extensions_from_layers "$LAYER_PATHS" "extensions.txt"
vscode_install_extensions_from_layers() {
    local layer_paths_str="$1"
    local filename="${2:-extensions.txt}"

    IFS=':' read -ra layer_paths <<< "$layer_paths_str"

    for layer_path in "${layer_paths[@]}"; do
        local ext_file="$layer_path/$filename"
        if [[ -f "$ext_file" ]]; then
            log_step "Installing extensions from $ext_file"
            vscode_install_extensions_from_file "$ext_file"
        fi
    done
}
