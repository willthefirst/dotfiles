# Plan: Add VS Code Settings to Dotfiles

## Status

### Completed
- [x] **Phase 1**: Shared utilities created and tested
  - `lib/helpers/json-merge.sh` - JSON deep merge, validate, get
  - `lib/helpers/symlink-factory.sh` - symlink with backup, layer symlinks
  - `lib/helpers/extension-installer.sh` - VS Code extension management
  - Unit tests for json-merge and symlink-factory

- [x] **Bug fixes** (discovered during implementation)
  - Fixed `((VAR++))` arithmetic returning exit 1 when VAR=0 (bash gotcha with `set -e`)
  - Fixed test runner double-execution (was sourcing tests twice)
  - Fixed missing `log.sh` source in `utils.sh`
  - Added documentation: `CLAUDE.md`, `lib/helpers/README.md`, `test/README.md`

### Remaining
- [x] **Phase 3**: VS Code tool implementation
  - `tools/vscode/tool.conf`
  - `tools/vscode/merge.sh`
  - `tools/vscode/install.sh`
  - `configs/vscode/` base config files
  - Update machine profiles

---

## Overview
Add VS Code configuration management with full layer support (base + work), managing settings.json, keybindings.json, snippets/, and extensions.

**Approach**: Refactor shared patterns first, then implement VS Code using the new utilities.

---

## Identified Refactoring Opportunities

| Pattern | Current Location | Issue |
|---------|-----------------|-------|
| JSON deep merge | `builtins.sh` (shallow only) | VS Code needs recursive merge |
| Layer file iteration | `nvim/merge.sh` (4x repeated) | Same loop repeated 4 times |
| Symlink with backup | `claude/merge.sh`, `nvim/merge.sh` | Duplicated ~6 lines each |
| Extension installer | None | New capability needed |

---

# Phase 1: Create Shared Utilities

## Task 1A: Create `lib/helpers/json-merge.sh`

**Purpose**: Provide deep JSON merging utilities for layered configs.

**File**: `lib/helpers/json-merge.sh`

**Dependencies**:
- `jq` (should be available on macOS via brew, Linux via apt)
- Source `lib/helpers/log.sh` for logging

**Functions to implement**:

```bash
#!/usr/bin/env bash
# lib/helpers/json-merge.sh
# JSON merging utilities for layered configuration management

# Ensure jq is available
_require_jq() {
    if ! command -v jq &>/dev/null; then
        error "jq is required for JSON merging but not found"
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
        error "File not found: $file"
        return 1
    fi

    if ! jq empty "$file" 2>/dev/null; then
        error "Invalid JSON in $file"
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
```

**Testing**: Create `lib/dotfiles-system/test/unit/test_json_merge.sh`
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/../test_utils.sh"
source "$(dirname "$0")/../../lib/helpers/json-merge.sh"

test_json_deep_merge_basic() {
    setup_test_env

    echo '{"a": 1, "b": 2}' > "$TEST_DIR/base.json"
    echo '{"b": 3, "c": 4}' > "$TEST_DIR/overlay.json"

    json_deep_merge "$TEST_DIR/output.json" "$TEST_DIR/base.json" "$TEST_DIR/overlay.json"

    local result=$(cat "$TEST_DIR/output.json")
    assert_contains "$result" '"a": 1'
    assert_contains "$result" '"b": 3'  # overlay wins
    assert_contains "$result" '"c": 4'

    teardown_test_env
}

test_json_deep_merge_nested() {
    setup_test_env

    echo '{"editor": {"fontSize": 14, "tabSize": 2}}' > "$TEST_DIR/base.json"
    echo '{"editor": {"fontSize": 16}}' > "$TEST_DIR/overlay.json"

    json_deep_merge "$TEST_DIR/output.json" "$TEST_DIR/base.json" "$TEST_DIR/overlay.json"

    # Should have fontSize=16 but preserve tabSize=2
    local result=$(cat "$TEST_DIR/output.json")
    assert_contains "$result" '"fontSize": 16'
    assert_contains "$result" '"tabSize": 2'

    teardown_test_env
}

test_json_validate_valid() {
    setup_test_env
    echo '{"valid": true}' > "$TEST_DIR/valid.json"
    assert_success json_validate "$TEST_DIR/valid.json"
    teardown_test_env
}

test_json_validate_invalid() {
    setup_test_env
    echo '{invalid json' > "$TEST_DIR/invalid.json"
    assert_failure json_validate "$TEST_DIR/invalid.json"
    teardown_test_env
}

# Run tests
test_json_deep_merge_basic
test_json_deep_merge_nested
test_json_validate_valid
test_json_validate_invalid
print_summary
```

---

## Task 1B: Create `lib/helpers/symlink-factory.sh`

**Purpose**: Provide reusable symlink creation patterns with backup support.

**File**: `lib/helpers/symlink-factory.sh`

**Dependencies**:
- Source `lib/dotfiles-system/lib/utils.sh` for `safe_remove()`
- Source `lib/helpers/log.sh` for logging

**Functions to implement**:

```bash
#!/usr/bin/env bash
# lib/helpers/symlink-factory.sh
# Symlink creation utilities with backup support

# Ensure required functions are available
_require_utils() {
    if ! declare -f safe_remove &>/dev/null; then
        source "${DOTFILES_DIR:-$HOME/.dotfiles}/lib/dotfiles-system/lib/utils.sh"
    fi
}

# Create symlink with automatic backup of existing file
# Usage: symlink_with_backup source target
symlink_with_backup() {
    _require_utils
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
        warn "Source does not exist: $source"
        return 1
    fi

    # Create parent directory if needed
    local target_dir=$(dirname "$target")
    [[ -d "$target_dir" ]] || mkdir -p "$target_dir"

    # Remove existing (with backup)
    if [[ -e "$target" || -L "$target" ]]; then
        safe_remove "$target"
    fi

    ln -sf "$source" "$target"
    detail "Symlinked: $target -> $source"
}

# Create symlinks for all files matching pattern in a directory
# Later layers override earlier layers for same filename
# Usage: create_layer_symlinks target_dir pattern layer_paths_array
# Example: create_layer_symlinks "$HOME/.config/vscode/snippets" "*.code-snippets" layer_paths
create_layer_symlinks() {
    _require_utils
    local target_dir="$1"
    local pattern="$2"
    shift 2
    local -a layer_paths=("$@")

    # Track files across layers (later wins)
    declare -A file_map

    for layer_path in "${layer_paths[@]}"; do
        [[ -d "$layer_path" ]] || continue

        for file in "$layer_path"/$pattern; do
            [[ -f "$file" ]] || continue
            local filename=$(basename "$file")
            file_map["$filename"]="$file"
        done
    done

    # Create target directory
    mkdir -p "$target_dir"

    # Create symlinks
    for filename in "${!file_map[@]}"; do
        local source="${file_map[$filename]}"
        local target="$target_dir/$filename"
        symlink_with_backup "$source" "$target"
    done
}

# Symlink entire directory (for simple configs like ghostty)
# Usage: symlink_directory source target
symlink_directory() {
    _require_utils
    local source="$1"
    local target="$2"

    if [[ ! -d "$source" ]]; then
        warn "Source directory does not exist: $source"
        return 1
    fi

    local target_parent=$(dirname "$target")
    [[ -d "$target_parent" ]] || mkdir -p "$target_parent"

    if [[ -e "$target" || -L "$target" ]]; then
        safe_remove "$target"
    fi

    ln -sf "$source" "$target"
    detail "Symlinked directory: $target -> $source"
}
```

**Testing**: Create `lib/dotfiles-system/test/unit/test_symlink_factory.sh`
```bash
#!/usr/bin/env bash
source "$(dirname "$0")/../test_utils.sh"
source "$(dirname "$0")/../../lib/helpers/symlink-factory.sh"

test_symlink_with_backup_new() {
    setup_test_env

    echo "source content" > "$TEST_DIR/source.txt"
    symlink_with_backup "$TEST_DIR/source.txt" "$TEST_DIR/target.txt"

    assert_file_exists "$TEST_DIR/target.txt"
    assert_equals "$(readlink "$TEST_DIR/target.txt")" "$TEST_DIR/source.txt"

    teardown_test_env
}

test_symlink_with_backup_existing() {
    setup_test_env

    echo "old content" > "$TEST_DIR/target.txt"
    echo "new content" > "$TEST_DIR/source.txt"

    symlink_with_backup "$TEST_DIR/source.txt" "$TEST_DIR/target.txt"

    # Check symlink points to new source
    assert_equals "$(readlink "$TEST_DIR/target.txt")" "$TEST_DIR/source.txt"
    # Check backup was created (backup directory from safe_remove)

    teardown_test_env
}

test_create_layer_symlinks() {
    setup_test_env

    # Create layer structure
    mkdir -p "$TEST_DIR/layer1" "$TEST_DIR/layer2" "$TEST_DIR/target"
    echo "layer1 a" > "$TEST_DIR/layer1/a.txt"
    echo "layer1 b" > "$TEST_DIR/layer1/b.txt"
    echo "layer2 b" > "$TEST_DIR/layer2/b.txt"  # Override
    echo "layer2 c" > "$TEST_DIR/layer2/c.txt"

    create_layer_symlinks "$TEST_DIR/target" "*.txt" "$TEST_DIR/layer1" "$TEST_DIR/layer2"

    # a.txt from layer1, b.txt from layer2 (override), c.txt from layer2
    assert_equals "$(readlink "$TEST_DIR/target/a.txt")" "$TEST_DIR/layer1/a.txt"
    assert_equals "$(readlink "$TEST_DIR/target/b.txt")" "$TEST_DIR/layer2/b.txt"
    assert_equals "$(readlink "$TEST_DIR/target/c.txt")" "$TEST_DIR/layer2/c.txt"

    teardown_test_env
}

test_symlink_with_backup_new
test_symlink_with_backup_existing
test_create_layer_symlinks
print_summary
```

---

## Task 1C: Create `lib/helpers/extension-installer.sh`

**Purpose**: Install VS Code extensions from manifest files.

**File**: `lib/helpers/extension-installer.sh`

**Dependencies**:
- Source `lib/helpers/log.sh` for logging
- `code` CLI must be available

**Functions to implement**:

```bash
#!/usr/bin/env bash
# lib/helpers/extension-installer.sh
# VS Code extension installation utilities

# Find the VS Code CLI
_find_code_cli() {
    # Check common locations
    if command -v code &>/dev/null; then
        echo "code"
        return 0
    fi

    # macOS: Check for VS Code in Applications
    if [[ -f "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
        echo "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        return 0
    fi

    # Linux: Check snap installation
    if [[ -f "/snap/bin/code" ]]; then
        echo "/snap/bin/code"
        return 0
    fi

    return 1
}

# Check if VS Code is available
vscode_available() {
    _find_code_cli &>/dev/null
}

# Get list of installed extensions
# Usage: vscode_list_extensions
vscode_list_extensions() {
    local code_cli
    code_cli=$(_find_code_cli) || { warn "VS Code CLI not found"; return 1; }
    "$code_cli" --list-extensions 2>/dev/null
}

# Install a single extension
# Usage: vscode_install_extension extension_id
vscode_install_extension() {
    local ext="$1"
    local code_cli
    code_cli=$(_find_code_cli) || { warn "VS Code CLI not found"; return 1; }

    detail "Installing extension: $ext"
    "$code_cli" --install-extension "$ext" --force 2>/dev/null
}

# Install extensions from a text file (one extension ID per line)
# Lines starting with # are comments, empty lines are ignored
# Usage: vscode_install_extensions_from_file extensions.txt
vscode_install_extensions_from_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        warn "Extensions file not found: $file"
        return 1
    fi

    local code_cli
    code_cli=$(_find_code_cli) || { warn "VS Code CLI not found"; return 1; }

    while IFS= read -r ext || [[ -n "$ext" ]]; do
        # Skip empty lines and comments
        [[ -z "$ext" || "$ext" == \#* ]] && continue
        # Trim whitespace
        ext=$(echo "$ext" | xargs)
        [[ -z "$ext" ]] && continue

        vscode_install_extension "$ext"
    done < "$file"
}

# Install extensions from multiple layer files
# Usage: vscode_install_extensions_from_layers layer_paths extensions_filename
# Example: vscode_install_extensions_from_layers "$LAYER_PATHS" "extensions.txt"
vscode_install_extensions_from_layers() {
    local layer_paths_str="$1"
    local filename="${2:-extensions.txt}"

    IFS=':' read -ra layer_paths <<< "$layer_paths_str"

    for layer_path in "${layer_paths[@]}"; do
        local ext_file="$layer_path/$filename"
        if [[ -f "$ext_file" ]]; then
            step "Installing extensions from $ext_file"
            vscode_install_extensions_from_file "$ext_file"
        fi
    done
}
```

**Note**: Unit tests for extension installer would require mocking the `code` CLI, which is complex. Instead, test manually or with integration tests.

---

# Phase 2: Extend Framework Builtins (Optional)

**Skip for now** - Custom merge.sh scripts are sufficient. Can add builtins later if the pattern proves useful across many tools.

---

# Phase 3: Implement VS Code Tool

## Task 3A: Create `tools/vscode/tool.conf`

**File**: `tools/vscode/tool.conf`

```bash
# VS Code configuration
# Uses JSON deep-merge for settings/keybindings, symlinks for snippets

tool_layers_from "vscode"

if is_macos; then
    tool_target="${HOME}/Library/Application Support/Code/User"
else
    tool_target="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
fi

tool_merge_hook "./merge.sh"
tool_install_hook "./install.sh"
```

---

## Task 3B: Create `tools/vscode/merge.sh`

**File**: `tools/vscode/merge.sh`

**Dependencies**:
- Source helpers: `log.sh`, `json-merge.sh`, `symlink-factory.sh`
- Uses environment from framework: `$LAYER_PATHS`, `$TARGET`

```bash
#!/usr/bin/env bash
# tools/vscode/merge.sh
# Merge VS Code configuration from layers

set -euo pipefail

# Source helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

source "$DOTFILES_DIR/lib/helpers/log.sh"
source "$DOTFILES_DIR/lib/helpers/json-merge.sh"
source "$DOTFILES_DIR/lib/helpers/symlink-factory.sh"

# Parse layer paths from environment (colon-separated)
IFS=':' read -ra layer_paths <<< "$LAYER_PATHS"

section "Merging VS Code configuration"

# Ensure target directory exists
mkdir -p "$TARGET"

# 1. Deep merge settings.json from all layers
step "Merging settings.json"
settings_files=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -f "$layer_path/settings.json" ]]; then
        settings_files+=("$layer_path/settings.json")
        detail "Including: $layer_path/settings.json"
    fi
done

if [[ ${#settings_files[@]} -gt 0 ]]; then
    json_deep_merge "$TARGET/settings.json" "${settings_files[@]}"
    ok "Created $TARGET/settings.json"
else
    warn "No settings.json found in any layer"
fi

# 2. Deep merge keybindings.json from all layers
step "Merging keybindings.json"
keybindings_files=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -f "$layer_path/keybindings.json" ]]; then
        keybindings_files+=("$layer_path/keybindings.json")
        detail "Including: $layer_path/keybindings.json"
    fi
done

if [[ ${#keybindings_files[@]} -gt 0 ]]; then
    # Keybindings is an array, need different merge strategy
    # Later keybindings should override earlier for same key combo
    # For now, concatenate arrays (user can manage conflicts)
    jq -s 'add' "${keybindings_files[@]}" > "$TARGET/keybindings.json"
    ok "Created $TARGET/keybindings.json"
else
    warn "No keybindings.json found in any layer"
fi

# 3. Symlink snippet files from layers (later layers override)
step "Symlinking snippets"
snippet_dirs=()
for layer_path in "${layer_paths[@]}"; do
    if [[ -d "$layer_path/snippets" ]]; then
        snippet_dirs+=("$layer_path/snippets")
    fi
done

if [[ ${#snippet_dirs[@]} -gt 0 ]]; then
    # Collect all snippet files, later layers win
    declare -A snippet_map
    for snippet_dir in "${snippet_dirs[@]}"; do
        for file in "$snippet_dir"/*.code-snippets; do
            [[ -f "$file" ]] || continue
            filename=$(basename "$file")
            snippet_map["$filename"]="$file"
        done
    done

    # Create snippets directory and symlinks
    mkdir -p "$TARGET/snippets"
    for filename in "${!snippet_map[@]}"; do
        symlink_with_backup "${snippet_map[$filename]}" "$TARGET/snippets/$filename"
    done
    ok "Symlinked ${#snippet_map[@]} snippet file(s)"
else
    detail "No snippet directories found"
fi

ok "VS Code configuration merged"
```

---

## Task 3C: Create `tools/vscode/install.sh`

**File**: `tools/vscode/install.sh`

**Purpose**: Install extensions from layer extension files.

```bash
#!/usr/bin/env bash
# tools/vscode/install.sh
# Install VS Code extensions from layers

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

source "$DOTFILES_DIR/lib/helpers/log.sh"
source "$DOTFILES_DIR/lib/helpers/extension-installer.sh"

section "Installing VS Code extensions"

# Check if VS Code is available
if ! vscode_available; then
    warn "VS Code CLI not found, skipping extension installation"
    detail "Install VS Code and ensure 'code' is in PATH"
    exit 0
fi

# Install extensions from all layers
vscode_install_extensions_from_layers "$LAYER_PATHS" "extensions.txt"

ok "VS Code extensions installed"
```

---

## Task 3D: Create base config `configs/vscode/`

**Directory structure**:
```
configs/vscode/
├── settings.json      # Base VS Code settings
├── keybindings.json   # Base keyboard shortcuts (empty array to start)
├── snippets/          # Base snippets directory (can be empty)
└── extensions.txt     # List of extensions (one per line)
```

**File**: `configs/vscode/settings.json`
```json
{
    "editor.fontSize": 14,
    "editor.tabSize": 2,
    "editor.formatOnSave": true,
    "editor.minimap.enabled": false,
    "files.autoSave": "onFocusChange",
    "workbench.colorTheme": "Default Dark+"
}
```
*Note: User should customize with their actual settings*

**File**: `configs/vscode/keybindings.json`
```json
[]
```
*Note: Empty array, user adds their keybindings*

**File**: `configs/vscode/extensions.txt`
```
# VS Code Extensions
# One extension ID per line

# Core
esbenp.prettier-vscode
dbaeumer.vscode-eslint

# Git
eamodio.gitlens

# Themes (optional)
# dracula-theme.theme-dracula
```
*Note: User should customize with their extensions*

**Directory**: `configs/vscode/snippets/`
- Create empty directory, user can add `.code-snippets` files

---

## Task 3E: Update machine profiles

**File**: `machines/personal-mac.sh`
Add to the tools array and layer definition:
```bash
# Add to tools array
tools=(... vscode)

# Add layer definition
vscode_layers=(base)
```

**File**: `machines/stripe-mac.sh`
Add to the tools array and layer definition:
```bash
# Add to tools array
tools=(... vscode)

# Add layer definition
vscode_layers=(base stripe)
```

**File**: `machines/stripe-devbox.sh`
- Do NOT add vscode (no GUI on devbox)
- Or optionally add if using VS Code Remote SSH

---

# Phase 4: Optional Refactoring (After VS Code Works)

## Task 4A: Simplify `tools/nvim/merge.sh`

Replace the repeated loop patterns with `create_layer_symlinks` from symlink-factory.sh.

**Before** (repeated 4 times):
```bash
for i in "${!layer_paths[@]}"; do
    layer_path="${layer_paths[$i]}"
    for file in "$layer_path"/lua/config/*.lua; do
        ...
    done
done
```

**After**:
```bash
source "$DOTFILES_DIR/lib/helpers/symlink-factory.sh"
create_layer_symlinks "$TARGET/lua/config" "*.lua" "${layer_paths[@]}"
create_layer_symlinks "$TARGET/lua/plugins" "*.lua" "${layer_paths[@]}"
```

## Task 4B: Simplify `tools/claude/merge.sh`

Replace manual symlink logic with `symlink_with_backup`.

---

# Testing Strategy

## Unit Tests

| Test File | Tests |
|-----------|-------|
| `test/unit/test_json_merge.sh` | `json_deep_merge`, `json_validate`, nested merge |
| `test/unit/test_symlink_factory.sh` | `symlink_with_backup`, `create_layer_symlinks` |

## Running Tests

```bash
# Run all tests
bash lib/dotfiles-system/test/run_tests.sh

# Run with integration tests
bash lib/dotfiles-system/test/run_tests.sh --integration
```

## Verification Checklist

1. **Phase 1 verification**:
   - [ ] Run unit tests: `bash lib/dotfiles-system/test/run_tests.sh`
   - [ ] All tests pass

2. **Phase 3 verification**:
   - [ ] Dry run: `./install.sh personal-mac --dry-run --tool vscode`
   - [ ] Install: `./install.sh personal-mac --tool vscode`
   - [ ] Check `~/Library/Application Support/Code/User/settings.json` exists
   - [ ] Open VS Code, verify settings applied (Cmd+,)
   - [ ] Check extensions: `code --list-extensions`

3. **Full system verification**:
   - [ ] Full install: `./install.sh personal-mac`
   - [ ] All tools work correctly
   - [ ] VS Code settings and extensions applied

---

# Summary: Files to Create

## Phase 1: Shared Utilities
| File | Lines (est.) |
|------|-------------|
| `lib/helpers/json-merge.sh` | ~60 |
| `lib/helpers/symlink-factory.sh` | ~70 |
| `lib/helpers/extension-installer.sh` | ~70 |
| `lib/dotfiles-system/test/unit/test_json_merge.sh` | ~60 |
| `lib/dotfiles-system/test/unit/test_symlink_factory.sh` | ~50 |

## Phase 3: VS Code Tool
| File | Lines (est.) |
|------|-------------|
| `tools/vscode/tool.conf` | ~12 |
| `tools/vscode/merge.sh` | ~80 |
| `tools/vscode/install.sh` | ~25 |
| `configs/vscode/settings.json` | ~10 (user customizes) |
| `configs/vscode/keybindings.json` | ~1 |
| `configs/vscode/extensions.txt` | ~10 (user customizes) |
| `machines/personal-mac.sh` | +2 lines |
| `machines/stripe-mac.sh` | +2 lines |

## Phase 4: Optional Refactoring (DONE)
| File | Action |
|------|--------|
| `tools/nvim/merge.sh` | Simplified with symlink-factory helpers |
| `tools/claude/merge.sh` | Simplified with symlink-factory helpers |
