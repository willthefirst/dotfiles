#!/usr/bin/env bash
# install.sh
# Convenience wrapper that invokes the dotfiles framework with this repo
#
# Usage: ./install.sh <machine-profile> [options]
#
# Examples:
#   ./install.sh personal-mac
#   ./install.sh stripe-mac
#   ./install.sh stripe-mac --tool nvim

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Framework location - bundled as submodule, or override with FRAMEWORK env var
FRAMEWORK="${FRAMEWORK:-${SCRIPT_DIR}/lib/dotfiles-system}"

if [[ ! -d "$FRAMEWORK" ]]; then
    echo "Error: Framework not found at: $FRAMEWORK" >&2
    echo "Run: git submodule update --init" >&2
    exit 1
fi

exec "$FRAMEWORK/install.sh" "$@" --dotfiles "$SCRIPT_DIR"
