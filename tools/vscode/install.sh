#!/usr/bin/env bash
# tools/vscode/install.sh
# Install VS Code extensions from layers

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

source "$DOTFILES_DIR/lib/helpers/log.sh"
source "$DOTFILES_DIR/lib/helpers/extension-installer.sh"

log_section "Installing VS Code extensions"

# Check if VS Code is available
if ! vscode_available; then
    log_warn "VS Code CLI not found, skipping extension installation"
    log_detail "Install VS Code and ensure 'code' is in PATH"
    exit 0
fi

# Install extensions from all layers
vscode_install_extensions_from_layers "$LAYER_PATHS" "extensions.txt"

log_ok "VS Code extensions installed"
