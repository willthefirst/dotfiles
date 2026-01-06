#!/usr/bin/env bash
# =============================================================================
# tools/nvim/install.sh - Install Neovim
# =============================================================================
# Uses brew on macOS, appimage on Linux for latest version
# =============================================================================

set -euo pipefail

# Find the helpers directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$DOTFILES_DIR/lib/helpers/install-helpers.sh"

install_nvim() {
    if command -v nvim &>/dev/null; then
        log_ok "Neovim already installed: $(nvim --version | head -1)"
        return 0
    fi

    if is_macos; then
        log_step "Installing Neovim via Homebrew..."
        pkg_install neovim
    elif is_linux; then
        local arch tmp_file asset_name
        arch=$(get_arch_string)
        tmp_file="/tmp/nvim.appimage"
        asset_name="nvim-linux-${arch}.appimage"

        log_step "Downloading Neovim appimage..."
        if ! download_github_latest "neovim/neovim" "$asset_name" "$tmp_file"; then
            log_error "Failed to download Neovim"
            return 1
        fi

        log_step "Installing to ${DOTFILES_BIN_DIR:-/usr/local/bin}/nvim..."
        install_binary "$tmp_file" "nvim"
    fi

    log_ok "Neovim installed: $(nvim --version | head -1)"
}

# Run the install function
install_nvim
