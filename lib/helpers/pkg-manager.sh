#!/usr/bin/env bash
# =============================================================================
# lib/helpers/pkg-manager.sh - Package manager abstraction
# =============================================================================

# Source guard - prevent multiple loading
[[ -n "${_DOTFILES_PKG_MANAGER_LOADED:-}" ]] && return 0
_DOTFILES_PKG_MANAGER_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/log.sh"
source "${BASH_SOURCE%/*}/platform.sh"

# Install packages using the system package manager
# Usage: pkg_install <packages...>
pkg_install() {
    local packages=("$@")
    [[ ${#packages[@]} -eq 0 ]] && return 0

    if is_macos; then
        brew install "${packages[@]}"
    elif is_linux; then
        sudo apt-get update -qq
        sudo apt-get install -y "${packages[@]}"
    else
        log_error "Unsupported platform: $(uname -s)"
        return 1
    fi
}

# Check if a package is installed via the system package manager
# Usage: pkg_installed <package>
pkg_installed() {
    local pkg="$1"

    if is_macos; then
        brew list "$pkg" &>/dev/null || brew list --cask "$pkg" &>/dev/null
    elif is_linux; then
        dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
    else
        return 1
    fi
}
