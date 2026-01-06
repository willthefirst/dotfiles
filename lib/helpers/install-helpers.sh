#!/usr/bin/env bash
# =============================================================================
# lib/helpers/install-helpers.sh - Helper functions for installing from external sources
# =============================================================================

# Source guard - prevent multiple loading
[[ -n "${_DOTFILES_INSTALL_HELPERS_LOADED:-}" ]] && return 0
_DOTFILES_INSTALL_HELPERS_LOADED=1

source "${BASH_SOURCE%/*}/log.sh"
source "${BASH_SOURCE%/*}/platform.sh"
source "${BASH_SOURCE%/*}/pkg-manager.sh"

# Get architecture string for downloads
get_arch_string() {
    local arch
    arch=$(uname -m)

    case "$arch" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "$arch" ;;
    esac
}

# Get OS string for downloads
get_os_string() {
    uname -s
}

# Download a file from URL to destination
download_file() {
    local url="$1"
    local dest="$2"

    if ! curl -fsSL -o "$dest" "$url"; then
        log_error "Failed to download: $url"
        return 1
    fi
}

# Get latest release version from GitHub API
get_github_latest_version() {
    local repo="$1"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"

    curl -fsSL "$api_url" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Download file from GitHub release (specific version)
download_github_release() {
    local repo="$1"
    local asset_name="$2"
    local output="$3"

    local version
    version=$(get_github_latest_version "$repo") || return 1

    local download_url="https://github.com/${repo}/releases/download/${version}/${asset_name}"
    download_file "$download_url" "$output"
}

# Download file from GitHub releases/latest/download
download_github_latest() {
    local repo="$1"
    local asset_name="$2"
    local output="$3"

    local download_url="https://github.com/${repo}/releases/latest/download/${asset_name}"
    download_file "$download_url" "$output"
}

# Extract archive to directory
extract_archive() {
    local archive="$1"
    local dest="$2"
    shift 2
    local files=("$@")

    case "$archive" in
    *.tar.gz|*.tgz)
        tar -xzf "$archive" -C "$dest" "${files[@]}" 2>/dev/null
        ;;
    *.tar.bz2)
        tar -xjf "$archive" -C "$dest" "${files[@]}" 2>/dev/null
        ;;
    *.zip)
        unzip -q "$archive" -d "$dest" "${files[@]}" 2>/dev/null
        ;;
    *)
        log_error "Unknown archive format: $archive"
        return 1
        ;;
    esac
}

# Install binary to system path
install_binary() {
    local source="$1"
    local name="$2"
    local dest_dir="${3:-${DOTFILES_BIN_DIR:-/usr/local/bin}}"

    chmod +x "$source"

    if [[ -w "$dest_dir" ]]; then
        mv "$source" "$dest_dir/$name"
    else
        sudo mv "$source" "$dest_dir/$name"
    fi

    log_ok "Installed $name to $dest_dir"
}

# Cleanup temporary files
cleanup_temp() {
    for file in "$@"; do
        [[ -e "$file" ]] && rm -rf "$file"
    done
}
