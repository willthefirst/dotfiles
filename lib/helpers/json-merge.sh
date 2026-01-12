#!/usr/bin/env bash
# lib/helpers/json-merge.sh
# JSON merging utilities for layered configuration management

# Source logging utilities if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# Ensure jq is available
_require_jq() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required for JSON merging but not found"
        return 1
    fi
}

# Deep merge multiple JSON files
# Later files override earlier files at all nesting levels
# Usage: json_deep_merge output.json input1.json input2.json ...
json_deep_merge() {
    _require_jq || return 1
    local output="$1"; shift
    local inputs=("$@")

    if [[ ${#inputs[@]} -eq 0 ]]; then
        echo "{}" > "$output"
        return 0
    fi

    # jq's * operator does deep merge
    # reduce iterates through all files, merging each into accumulator
    jq -s 'reduce .[] as $item ({}; . * $item)' "${inputs[@]}" > "$output"
}

# Merge JSON arrays from multiple files (union, preserving order, no duplicates)
# Usage: json_merge_arrays output.json key input1.json input2.json ...
# Example: json_merge_arrays extensions.json "extensions" base.json work.json
json_merge_arrays() {
    _require_jq || return 1
    local output="$1"
    local key="$2"
    shift 2
    local inputs=("$@")

    # Extract arrays, flatten, unique
    jq -s --arg key "$key" '
        map(.[$key] // []) |
        add |
        unique
    ' "${inputs[@]}" > "$output"
}

# Validate JSON file syntax
# Returns 0 if valid, 1 if invalid
# Usage: json_validate file.json
json_validate() {
    _require_jq || return 1
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON in $file"
        return 1
    fi
    return 0
}

# Get a value from JSON file
# Usage: json_get file.json ".path.to.key"
json_get() {
    _require_jq || return 1
    local file="$1"
    local path="$2"
    jq -r "$path // empty" "$file"
}
