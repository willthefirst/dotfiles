#!/usr/bin/env bash
# =============================================================================
# tools/ssh/install.sh - Set up SSH directories
# =============================================================================
# Creates required directories for SSH configuration
# =============================================================================

set -euo pipefail

# Find the helpers directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$DOTFILES_DIR/lib/helpers/log.sh"

# Create sockets directory for SSH ControlMaster on Stripe devbox
#
# This directory is critical on Stripe devboxes because the SSH config uses
# ControlMaster for connection multiplexing, which requires a writable sockets
# directory. Without this directory, SSH connections will fail when ControlMaster
# attempts to create socket files.
setup_sockets_dir() {
    if [[ "$MACHINE" != "stripe-devbox" ]]; then
        return 0
    fi

    local sockets_dir="${HOME}/.ssh/sockets"

    if [[ -d "$sockets_dir" ]]; then
        log_ok "SSH sockets directory already exists: $sockets_dir"
    else
        log_step "Creating SSH sockets directory: $sockets_dir"
        mkdir -p "$sockets_dir"
        log_ok "Created SSH sockets directory"
    fi

    # Ensure proper permissions (owner read/write/execute only)
    chmod 700 "$sockets_dir"
}

setup_sockets_dir
