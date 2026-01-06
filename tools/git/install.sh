#!/usr/bin/env bash
# =============================================================================
# tools/git/install.sh - Install git tools (lazygit)
# =============================================================================
# macOS uses Homebrew, Linux uses GitHub releases
# =============================================================================

set -euo pipefail

# Find the helpers directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$DOTFILES_DIR/lib/helpers/install-helpers.sh"

install_lazygit() {
    if command -v lazygit &>/dev/null; then
        log_ok "lazygit already installed: $(lazygit --version)"
        return 0
    fi

    if is_macos; then
        log_step "Installing lazygit via Homebrew..."
        pkg_install lazygit
    elif is_linux; then
        local arch os tmp_archive tmp_dir version asset_name
        arch=$(get_arch_string)
        os=$(get_os_string)
        tmp_dir="/tmp"
        tmp_archive="$tmp_dir/lazygit.tar.gz"

        log_step "Fetching latest lazygit version..."
        version=$(get_github_latest_version "jesseduffield/lazygit")
        if [[ -z "$version" ]]; then
            log_error "Failed to fetch latest version"
            return 1
        fi
        # Strip 'v' prefix for asset name
        version="${version#v}"

        asset_name="lazygit_${version}_${os}_${arch}.tar.gz"

        log_step "Downloading lazygit ${version}..."
        if ! download_github_release "jesseduffield/lazygit" "$asset_name" "$tmp_archive"; then
            cleanup_temp "$tmp_archive"
            return 1
        fi

        log_step "Extracting lazygit..."
        if ! extract_archive "$tmp_archive" "$tmp_dir" "lazygit"; then
            cleanup_temp "$tmp_archive"
            return 1
        fi

        log_step "Installing to ${DOTFILES_BIN_DIR:-/usr/local/bin}/lazygit..."
        install_binary "$tmp_dir/lazygit" "lazygit"
        cleanup_temp "$tmp_archive"
    fi

    log_ok "lazygit installed: $(lazygit --version)"
}

# Run the install function
install_lazygit
