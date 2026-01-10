#!/usr/bin/env bash
# =============================================================================
# lib/helpers/log.sh - Logging utilities for dotfiles scripts
# =============================================================================

# Source guard - prevent multiple loading
[[ -n "${_DOTFILES_LOG_LOADED:-}" ]] && return 0
_DOTFILES_LOG_LOADED=1

# Colors for output
readonly LOG_COLOR_RESET='\033[0m'
readonly LOG_COLOR_BOLD='\033[1m'
readonly LOG_COLOR_DIM='\033[2m'
readonly LOG_COLOR_RED='\033[0;31m'
readonly LOG_COLOR_GREEN='\033[0;32m'
readonly LOG_COLOR_YELLOW='\033[1;33m'
readonly LOG_COLOR_CYAN='\033[0;36m'

# Log prefix icons
readonly LOG_ICON_SECTION='==>'
readonly LOG_ICON_STEP='->'
readonly LOG_ICON_OK='✓'
readonly LOG_ICON_WARN='!'
readonly LOG_ICON_ERROR='✗'
readonly LOG_ICON_SKIP='-'

# Log indentation
readonly LOG_INDENT_1='  '
readonly LOG_INDENT_2='     '

# Section header - major operation starting
log_section() {
    echo ""
    echo -e "${LOG_COLOR_BOLD}${LOG_COLOR_CYAN}${LOG_ICON_SECTION}${LOG_COLOR_RESET} ${LOG_COLOR_BOLD}$1${LOG_COLOR_RESET}"
}

# Step - action in progress
log_step() {
    echo -e "${LOG_INDENT_1}${LOG_COLOR_GREEN}${LOG_ICON_STEP}${LOG_COLOR_RESET} $1"
}

# Detail - subordinate information (dim)
log_detail() {
    echo -e "${LOG_INDENT_2}${LOG_COLOR_DIM}$1${LOG_COLOR_RESET}"
}

# Success result
log_ok() {
    echo -e "${LOG_INDENT_1}${LOG_COLOR_GREEN}${LOG_ICON_OK}${LOG_COLOR_RESET} $1"
}

# Warning
log_warn() {
    echo -e "${LOG_INDENT_1}${LOG_COLOR_YELLOW}${LOG_ICON_WARN}${LOG_COLOR_RESET} $1" >&2
}

# Error
log_error() {
    echo -e "${LOG_INDENT_1}${LOG_COLOR_RED}${LOG_ICON_ERROR}${LOG_COLOR_RESET} $1" >&2
}

# Skipped action
log_skip() {
    echo -e "${LOG_INDENT_1}${LOG_COLOR_DIM}${LOG_ICON_SKIP} $1${LOG_COLOR_RESET}"
}
