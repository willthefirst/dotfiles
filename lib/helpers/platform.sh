#!/usr/bin/env bash
# =============================================================================
# lib/helpers/platform.sh - Platform detection utilities
# =============================================================================

# Source guard - prevent multiple loading
[[ -n "${_DOTFILES_PLATFORM_LOADED:-}" ]] && return 0
_DOTFILES_PLATFORM_LOADED=1

is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}
