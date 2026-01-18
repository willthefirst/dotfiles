#!/usr/bin/env bash
# scripts/migrate-to-json.sh
# Migrate configuration files from key=value/bash format to JSON
#
# Usage:
#   ./scripts/migrate-to-json.sh --dry-run    # Preview changes
#   ./scripts/migrate-to-json.sh              # Perform migration
#   ./scripts/migrate-to-json.sh --tool git   # Single tool only
#   ./scripts/migrate-to-json.sh --repos      # repos.conf only
#   ./scripts/migrate-to-json.sh --machines   # machines/*.sh only

# Require bash 4+ for associative arrays
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: Bash 4+ required (found ${BASH_VERSION})" >&2
    echo "Run with: /opt/homebrew/bin/bash $0" >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-${SCRIPT_DIR}/..}"
SCHEMAS_DIR="$DOTFILES_DIR/lib/dotfiles-system/schemas"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
MIGRATED=0
SKIPPED=0
FAILED=0

# ============================================================================
# Utility Functions
# ============================================================================

log_info() { echo -e "${BLUE}INFO${NC}: $*"; }
log_success() { echo -e "${GREEN}OK${NC}: $*"; }
log_warn() { echo -e "${YELLOW}WARN${NC}: $*"; }
log_error() { echo -e "${RED}ERROR${NC}: $*" >&2; }

# Convert ${HOME}/.path or $HOME/.path or /Users/user to ~/.path
normalize_target_path() {
    local path="$1"
    # Remove ${HOME} and $HOME references (literal strings)
    path="${path//\$\{HOME\}/~}"
    path="${path//\$HOME/~}"
    # Handle ${XDG_CONFIG_HOME:-$HOME/.config} pattern (literal)
    path="${path//\$\{XDG_CONFIG_HOME:-\$HOME\/.config\}/~/.config}"
    # Replace actual home directory path with ~
    path="${path//$HOME/\~}"
    # Handle XDG_CONFIG_HOME pattern with expanded HOME
    if [[ "$path" =~ ^\$\{XDG_CONFIG_HOME:-~/.config\}(.*) ]]; then
        path="~/.config${BASH_REMATCH[1]}"
    fi
    echo "$path"
}

# Validate JSON against schema using jq (basic validation)
validate_json() {
    local json_file="$1"
    local schema_file="$2"

    # Basic JSON validity check
    if ! jq . "$json_file" &>/dev/null; then
        log_error "Invalid JSON in $json_file"
        return 1
    fi

    # Schema validation would require a dedicated tool like ajv
    # For now, just check required fields based on schema type
    local schema_name
    schema_name=$(basename "$schema_file")

    case "$schema_name" in
        tool.schema.json)
            if ! jq -e '.target and .merge_hook and .layers' "$json_file" &>/dev/null; then
                log_error "Missing required fields (target, merge_hook, layers) in $json_file"
                return 1
            fi
            ;;
        repos.schema.json)
            if ! jq -e '.repositories' "$json_file" &>/dev/null; then
                log_error "Missing required field (repositories) in $json_file"
                return 1
            fi
            ;;
        machine.schema.json)
            if ! jq -e '.name and .tools' "$json_file" &>/dev/null; then
                log_error "Missing required fields (name, tools) in $json_file"
                return 1
            fi
            ;;
    esac

    return 0
}

# ============================================================================
# Migration: tool.conf -> tool.json
# ============================================================================

migrate_tool_conf() {
    local tool_dir="$1"
    local dry_run="${2:-false}"

    local tool_name
    tool_name=$(basename "$tool_dir")
    local conf_file="$tool_dir/tool.conf"
    local json_file="$tool_dir/tool.json"

    # Skip if no conf file
    if [[ ! -f "$conf_file" ]]; then
        log_warn "No tool.conf found for $tool_name"
        return 0
    fi

    # Skip if JSON already exists
    if [[ -f "$json_file" ]]; then
        log_info "tool.json already exists for $tool_name, skipping"
        ((SKIPPED++)) || true
        return 0
    fi

    log_info "Migrating $tool_name/tool.conf..."

    # Parse the conf file
    local target="" merge_hook="" install_hook=""
    declare -A layers

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse key=value
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Strip quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            # Strip inline comments
            value="${value%%#*}"
            value="${value%"${value##*[![:space:]]}"}"  # rtrim

            case "$key" in
                target)
                    target=$(normalize_target_path "$value")
                    ;;
                merge_hook)
                    merge_hook="$value"
                    ;;
                install_hook)
                    install_hook="$value"
                    ;;
                layers_*)
                    local layer_name="${key#layers_}"
                    layers["$layer_name"]="$value"
                    ;;
            esac
        fi
    done < "$conf_file"

    # Build layers JSON array (preserving order by sorting layer names)
    local layers_json="["
    local first=true
    for layer_name in $(echo "${!layers[@]}" | tr ' ' '\n' | sort); do
        local layer_value="${layers[$layer_name]}"
        local source="${layer_value%%:*}"
        local path="${layer_value#*:}"

        [[ "$first" == "true" ]] || layers_json+=","
        first=false

        layers_json+=$(printf '\n    { "name": "%s", "source": "%s", "path": "%s" }' \
            "$layer_name" "$source" "$path")
    done
    layers_json+=$'\n  ]'

    # Calculate relative schema path
    local schema_path="../../lib/dotfiles-system/schemas/tool.schema.json"

    # Build the JSON
    local json_content
    json_content=$(cat <<EOF
{
  "\$schema": "$schema_path",
  "target": "$target",
  "merge_hook": "$merge_hook",
EOF
)

    # Add optional install_hook
    if [[ -n "$install_hook" ]]; then
        json_content+=$(printf '\n  "install_hook": "%s",' "$install_hook")
    fi

    json_content+=$(printf '\n  "layers": %s\n}' "$layers_json")

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Would create:${NC} $json_file"
        echo "$json_content"
        echo ""
    else
        # Write the file
        echo "$json_content" > "$json_file"

        # Validate
        if validate_json "$json_file" "$SCHEMAS_DIR/tool.schema.json"; then
            log_success "Created $json_file"
            ((MIGRATED++)) || true
        else
            rm -f "$json_file"
            ((FAILED++)) || true
            return 1
        fi
    fi
}

# ============================================================================
# Migration: repos.conf -> repos.json
# ============================================================================

migrate_repos_conf() {
    local dry_run="${1:-false}"

    local conf_file="$DOTFILES_DIR/repos.conf"
    local json_file="$DOTFILES_DIR/repos.json"

    # Skip if no conf file
    if [[ ! -f "$conf_file" ]]; then
        log_warn "No repos.conf found"
        return 0
    fi

    # Skip if JSON already exists
    if [[ -f "$json_file" ]]; then
        log_info "repos.json already exists, skipping"
        ((SKIPPED++)) || true
        return 0
    fi

    log_info "Migrating repos.conf..."

    # Parse the conf file
    declare -a repos_json_array

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse NAME="url|path"
        if [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*\"([^|]+)\|([^\"]+)\" ]]; then
            local name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"
            local path="${BASH_REMATCH[3]}"

            # Normalize path
            path=$(normalize_target_path "$path")

            repos_json_array+=("$(printf '    {\n      "name": "%s",\n      "url": "%s",\n      "path": "%s"\n    }' \
                "$name" "$url" "$path")")
        fi
    done < "$conf_file"

    # Build the JSON
    local repos_list
    repos_list=$(IFS=$',\n'; echo "${repos_json_array[*]}")

    local json_content
    json_content=$(cat <<EOF
{
  "\$schema": "lib/dotfiles-system/schemas/repos.schema.json",
  "repositories": [
$repos_list
  ]
}
EOF
)

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Would create:${NC} $json_file"
        echo "$json_content"
        echo ""
    else
        # Write the file
        echo "$json_content" > "$json_file"

        # Validate
        if validate_json "$json_file" "$SCHEMAS_DIR/repos.schema.json"; then
            log_success "Created $json_file"
            ((MIGRATED++)) || true
        else
            rm -f "$json_file"
            ((FAILED++)) || true
            return 1
        fi
    fi
}

# ============================================================================
# Migration: machines/*.sh -> machines/*.json
# ============================================================================

migrate_machine_profile() {
    local profile_path="$1"
    local dry_run="${2:-false}"

    # Skip non-.sh files
    [[ "$profile_path" == *.sh ]] || return 0

    local profile_name
    profile_name=$(basename "$profile_path" .sh)
    local json_file="${profile_path%.sh}.json"

    # Skip if JSON already exists
    if [[ -f "$json_file" ]]; then
        log_info "$profile_name.json already exists, skipping"
        ((SKIPPED++)) || true
        return 0
    fi

    log_info "Migrating $profile_name.sh..."

    # Parse the .sh file
    local description=""
    declare -a tools_array
    declare -A tool_layers

    # Source the file in a subshell to extract variables
    (
        # Define arrays to capture
        TOOLS=()

        # Source the profile (this defines TOOLS and *_layers arrays)
        source "$profile_path"

        # Output tools
        echo "TOOLS=${TOOLS[*]}"

        # Output layer assignments
        for tool in "${TOOLS[@]}"; do
            local layers_var="${tool}_layers[@]"
            local layers_array=("${!layers_var}")
            echo "${tool}_layers=${layers_array[*]}"
        done
    ) > /tmp/migrate_profile_vars_$$

    # Read the extracted variables
    while IFS= read -r line; do
        if [[ "$line" =~ ^TOOLS=(.*)$ ]]; then
            IFS=' ' read -ra tools_array <<< "${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^([a-z][a-z0-9_-]*)_layers=(.*)$ ]]; then
            local tool="${BASH_REMATCH[1]}"
            local layers="${BASH_REMATCH[2]}"
            tool_layers["$tool"]="$layers"
        fi
    done < /tmp/migrate_profile_vars_$$
    rm -f /tmp/migrate_profile_vars_$$

    # Extract description from comment (second line typically)
    description=$(grep -m1 "^#.*configuration" "$profile_path" 2>/dev/null | sed 's/^#[[:space:]]*//' || true)
    [[ -z "$description" ]] && description="$profile_name configuration"

    # Build tools JSON object
    local tools_json="{"
    local first=true
    for tool in "${tools_array[@]}"; do
        [[ "$first" == "true" ]] || tools_json+=","
        first=false

        local layers="${tool_layers[$tool]:-base}"
        # Convert space-separated to JSON array
        local layers_json_array="["
        local layer_first=true
        for layer in $layers; do
            [[ "$layer_first" == "true" ]] || layers_json_array+=", "
            layer_first=false
            layers_json_array+="\"$layer\""
        done
        layers_json_array+="]"

        tools_json+=$(printf '\n    "%s": %s' "$tool" "$layers_json_array")
    done
    tools_json+=$'\n  }'

    # Build the JSON
    local json_content
    json_content=$(cat <<EOF
{
  "\$schema": "../lib/dotfiles-system/schemas/machine.schema.json",
  "name": "$profile_name",
  "description": "$description",
  "tools": $tools_json
}
EOF
)

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Would create:${NC} $json_file"
        echo "$json_content"
        echo ""
    else
        # Write the file
        echo "$json_content" > "$json_file"

        # Validate
        if validate_json "$json_file" "$SCHEMAS_DIR/machine.schema.json"; then
            log_success "Created $json_file"
            ((MIGRATED++)) || true
        else
            rm -f "$json_file"
            ((FAILED++)) || true
            return 1
        fi
    fi
}

# ============================================================================
# Main
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Migrate configuration files from key=value/bash format to JSON.

Options:
  --dry-run       Preview changes without writing files
  --tool <name>   Migrate a single tool's tool.conf
  --repos         Migrate repos.conf only
  --machines      Migrate machines/*.sh only
  --help          Show this help

Examples:
  $(basename "$0") --dry-run        # Preview all migrations
  $(basename "$0")                  # Migrate everything
  $(basename "$0") --tool git       # Migrate only tools/git/tool.conf
  $(basename "$0") --repos          # Migrate only repos.conf
  $(basename "$0") --machines       # Migrate only machine profiles
EOF
}

main() {
    local dry_run=false
    local target="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --tool)
                [[ -z "${2:-}" ]] && { log_error "--tool requires a tool name"; exit 1; }
                target="tool:$2"
                shift 2
                ;;
            --repos)
                target="repos"
                shift
                ;;
            --machines)
                target="machines"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Check for jq
    if ! command -v jq &>/dev/null; then
        log_error "jq is required for JSON migration"
        log_error "Install via: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi

    echo "============================================"
    echo "JSON Configuration Migration"
    echo "============================================"
    [[ "$dry_run" == "true" ]] && echo -e "${YELLOW}DRY RUN MODE${NC} - No files will be written"
    echo ""

    case "$target" in
        all)
            # Migrate all tools
            for tool_dir in "$DOTFILES_DIR"/tools/*/; do
                [[ -d "$tool_dir" ]] && migrate_tool_conf "$tool_dir" "$dry_run"
            done

            # Migrate repos.conf
            migrate_repos_conf "$dry_run"

            # Migrate machine profiles
            for profile in "$DOTFILES_DIR"/machines/*.sh; do
                [[ -f "$profile" ]] && migrate_machine_profile "$profile" "$dry_run"
            done
            ;;
        tool:*)
            local tool_name="${target#tool:}"
            local tool_dir="$DOTFILES_DIR/tools/$tool_name"
            if [[ ! -d "$tool_dir" ]]; then
                log_error "Tool not found: $tool_name"
                exit 1
            fi
            migrate_tool_conf "$tool_dir" "$dry_run"
            ;;
        repos)
            migrate_repos_conf "$dry_run"
            ;;
        machines)
            for profile in "$DOTFILES_DIR"/machines/*.sh; do
                [[ -f "$profile" ]] && migrate_machine_profile "$profile" "$dry_run"
            done
            ;;
    esac

    # Summary
    echo ""
    echo "============================================"
    echo "Migration Summary"
    echo "============================================"
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run - no files were written"
    else
        echo -e "Migrated: ${GREEN}$MIGRATED${NC}"
        echo -e "Skipped:  ${YELLOW}$SKIPPED${NC}"
        echo -e "Failed:   ${RED}$FAILED${NC}"
    fi
    echo "============================================"

    [[ $FAILED -gt 0 ]] && exit 1
    exit 0
}

main "$@"
