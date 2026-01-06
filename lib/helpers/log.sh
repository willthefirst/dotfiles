#!/usr/bin/env bash
# =============================================================================
# lib/helpers/log.sh - Logging utilities for dotfiles scripts
# =============================================================================

# Source guard - prevent multiple loading
[[ -n "${_DOTFILES_LOG_LOADED:-}" ]] && return 0
_DOTFILES_LOG_LOADED=1

# Colors for output
readonly LOG_COLOR_RED='\033[0;31m'
readonly LOG_COLOR_GREEN='\033[0;32m'
readonly LOG_COLOR_YELLOW='\033[1;33m'
readonly LOG_COLOR_NC='\033[0m' # No Color

# Log prefix icons
readonly LOG_ICON_STEP='→'
readonly LOG_ICON_OK='✓'
readonly LOG_ICON_WARN='!'
readonly LOG_ICON_ERROR='✗'

# Log indentation
readonly LOG_INDENT='  '

# Logging functions
log_info() { echo -e "${LOG_INDENT}$1"; }
log_step() { echo -e "${LOG_INDENT}${LOG_COLOR_GREEN}${LOG_ICON_STEP}${LOG_COLOR_NC} $1"; }
log_ok() { echo -e "${LOG_INDENT}${LOG_COLOR_GREEN}${LOG_ICON_OK}${LOG_COLOR_NC} $1"; }
log_warn() { echo -e "${LOG_INDENT}${LOG_COLOR_YELLOW}${LOG_ICON_WARN}${LOG_COLOR_NC} $1" >&2; }
log_error() { echo -e "${LOG_INDENT}${LOG_COLOR_RED}${LOG_ICON_ERROR}${LOG_COLOR_NC} $1" >&2; }
