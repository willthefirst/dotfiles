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

# Re-exec with homebrew bash if current bash is too old (macOS ships with 3.2)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    if [[ -x /opt/homebrew/bin/bash ]]; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif [[ -x /usr/local/bin/bash ]]; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4+ required (found ${BASH_VERSION})" >&2
        echo "On macOS, install via: brew install bash" >&2
        exit 1
    fi
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Framework location - bundled as submodule, or override with FRAMEWORK env var
FRAMEWORK="${FRAMEWORK:-${SCRIPT_DIR}/lib/dotfiles-system}"

if [[ ! -d "$FRAMEWORK" ]]; then
    echo "Error: Framework not found at: $FRAMEWORK" >&2
    echo "Run: git submodule update --init" >&2
    exit 1
fi

# Use $BASH to preserve the current interpreter (homebrew bash after re-exec)
# rather than letting the framework's shebang resolve to system bash
exec "$BASH" "$FRAMEWORK/install.sh" "$@" --dotfiles "$SCRIPT_DIR"
