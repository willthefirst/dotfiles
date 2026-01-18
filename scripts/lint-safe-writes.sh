#!/usr/bin/env bash
# scripts/lint-safe-writes.sh
# Check for unsafe file write patterns in tool scripts

# Require bash 4+ for array features
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: Bash 4+ required (found ${BASH_VERSION})" >&2
    echo "Run with: /opt/homebrew/bin/bash $0" >&2
    exit 1
fi

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Unsafe patterns to detect
# These patterns indicate direct file writes without backup
UNSAFE_PATTERNS=(
    'cat[[:space:]]*>[[:space:]]*[^|]'      # cat > file (but not cat > ... |)
    'echo[[:space:]].*>[[:space:]]*\$'      # echo ... > $file
    'printf.*>[[:space:]]*\$'               # printf ... > $file
    'jq[[:space:]].*>[[:space:]]*\$'        # jq ... > $file
)

# Directories to check
CHECK_DIRS=(
    "$DOTFILES_DIR/tools"
    "$DOTFILES_DIR/lib/helpers"
)

# Files to exclude (safe-write.sh itself, tests, etc.)
EXCLUDE_PATTERNS=(
    "safe-write.sh"
    "test"
    ".bak"
)

found_issues=0

check_file() {
    local file="$1"
    local issues_in_file=0

    # Skip excluded files
    for exclude in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$file" == *"$exclude"* ]]; then
            return 0
        fi
    done

    # Only check shell scripts
    if [[ ! "$file" =~ \.(sh|bash)$ ]]; then
        return 0
    fi

    # Check each unsafe pattern
    for pattern in "${UNSAFE_PATTERNS[@]}"; do
        local matches
        matches=$(grep -nE "$pattern" "$file" 2>/dev/null | grep -v "^[[:space:]]*#" || true)
        if [[ -n "$matches" ]]; then
            if [[ $issues_in_file -eq 0 ]]; then
                echo -e "${YELLOW}$file${NC}"
                issues_in_file=1
            fi
            echo "$matches" | while read -r line; do
                echo -e "  ${RED}$line${NC}"
            done
            ((found_issues++)) || true
        fi
    done
}

echo "Checking for unsafe file write patterns..."
echo ""

for dir in "${CHECK_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        while IFS= read -r -d '' file; do
            check_file "$file"
        done < <(find "$dir" -type f -print0 2>/dev/null)
    fi
done

echo ""
if [[ $found_issues -gt 0 ]]; then
    echo -e "${RED}Found $found_issues potential unsafe write patterns${NC}"
    echo ""
    echo "Use safe-write helpers instead:"
    echo "  - safe_write_file \"\$target\" \"content\""
    echo "  - safe_write_heredoc \"\$target\" <<EOF"
    echo "  - safe_jq_write \"\$target\" 'filter' inputs..."
    exit 1
else
    echo -e "${GREEN}No unsafe write patterns found${NC}"
    exit 0
fi
