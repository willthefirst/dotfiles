# Robust Backup System for Dotfiles

## Background

This is a dotfiles repo with a layered configuration system. It has:
- **Machine profiles** in `machines/` (personal-mac, stripe-mac, stripe-devbox)
- **Tool configs** in `tools/` with merge strategies (git, zsh, nvim, ssh, ghostty, karabiner, vscode, claude)
- **Base configs** in `configs/`
- **Core framework** in `lib/dotfiles-system/` (git submodule)
- **Helper libraries** in `lib/helpers/`

The system merges configs from multiple layers (base + work) and writes them to target locations like `~/.gitconfig`, `~/.config/nvim/`, etc.

## Problem

File overwrites happen without guaranteed backups. If the target has user edits not in the dotfiles, they can be lost.

**What exists:**
- `safe_remove()` in `lib/dotfiles-system/lib/utils.sh:73-103` moves files to `~/.dotfiles-backup/` with timestamps
- `symlink_with_backup()` in `lib/helpers/symlink-factory.sh:18-39` wraps it
- Built-in merge strategies in `lib/dotfiles-system/lib/builtins.sh` mostly call `safe_remove()` first

**Gaps found:**
- `tools/git/merge.sh:17` uses `cat > "$TARGET"` - NO backup
- `tools/nvim/merge.sh:117` uses `cat > "$TARGET/lua/lib/layers.lua"` - NO backup
- `tools/vscode/merge.sh:56` uses `jq ... > "$TARGET/keybindings.json"` - NO backup
- `lib/helpers/json-merge.sh:32` uses `jq ... > "$output"` - NO backup
- `lib/helpers/install-helpers.sh:108` uses `mv` for binaries - NO backup
- `lib/dotfiles-system/lib/builtins.sh:238` `builtin_merge_source()` uses `cat >` after safe_remove but doesn't check return value
- No error propagation - if `safe_remove()` fails, operations continue

## Requirements

1. **Backups before all overwrites** - every file write must backup first
2. **Graceful failure** - if backup fails, abort that tool only, continue with others
3. **Recovery guidance** - print concrete next steps (force overwrite option, diff option)
4. **Single system** - one set of wrapper functions, used everywhere
5. **Enforcement** - linting to catch unsafe patterns

---

## Implementation Plan

### Phase 1: Enhance `safe_remove()` with Error Handling

**File:** `lib/dotfiles-system/lib/utils.sh`

Current implementation (lines 73-103) doesn't return meaningful error codes.

**Changes:**
1. Add return codes:
   - 0 = success (backed up and removed, or didn't exist)
   - 1 = can't create backup directory
   - 2 = can't move file (in use, etc.)
   - 3 = permission denied

2. Add `_suggest_recovery()` helper function that prints:
   ```
   Recovery options:
     1. Check disk space/permissions for backup directory
     2. Set DOTFILES_BACKUP_DIR to a writable location
     3. Run with --force to overwrite without backup (DESTRUCTIVE)
     4. Review diff: diff "$target" <new-content>
   ```

3. Use `log_error` and `log_warn` from `lib/helpers/log.sh` for messaging

### Phase 2: Create Safe Write Helpers

**New file:** `lib/helpers/safe-write.sh`

Use `lib/helpers/symlink-factory.sh` as a template for structure/style.

```bash
#!/usr/bin/env bash
# Safe file writing utilities that always create backups

[[ -n "${_DOTFILES_SAFE_WRITE_LOADED:-}" ]] && return 0
_DOTFILES_SAFE_WRITE_LOADED=1

source "${BASH_SOURCE%/*}/log.sh"
source "${DOTFILES_DIR:-$HOME/.dotfiles}/lib/dotfiles-system/lib/utils.sh"

# Write content to file with automatic backup
# Returns: 0 on success, 1 on backup failure (aborts write)
safe_write_file() {
    local target="$1"
    local content="${2:-}"

    # Read from stdin if no content provided
    if [[ -z "$content" && ! -t 0 ]]; then
        content=$(cat)
    fi

    mkdir -p "$(dirname "$target")"

    if [[ -e "$target" || -L "$target" ]]; then
        if ! safe_remove "$target"; then
            log_error "Backup failed, aborting write to: $target"
            return 1
        fi
    fi

    printf '%s' "$content" > "$target"
}

# Write heredoc content with backup
# Usage: safe_write_heredoc "$target" <<'EOF'
safe_write_heredoc() {
    local target="$1"
    safe_write_file "$target" "$(cat)"
}

# Append to file (backup on first append per session)
declare -A _SAFE_APPEND_BACKED_UP
safe_append_file() {
    local target="$1"
    local content="$2"

    if [[ -z "${_SAFE_APPEND_BACKED_UP[$target]:-}" && (-e "$target" || -L "$target") ]]; then
        local backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
        mkdir -p "$backup_dir"
        cp -a "$target" "$backup_dir/$(basename "$target")_$(date +%Y%m%d_%H%M%S)" || return 1
        _SAFE_APPEND_BACKED_UP[$target]=1
    fi

    printf '%s' "$content" >> "$target"
}

# Run jq and write output safely
safe_jq_write() {
    local output="$1"
    local filter="$2"
    shift 2

    if [[ -e "$output" || -L "$output" ]]; then
        if ! safe_remove "$output"; then
            log_error "Backup failed, aborting jq write to: $output"
            return 1
        fi
    fi

    mkdir -p "$(dirname "$output")"
    jq "$filter" "$@" > "$output"
}

# Install binary with backup
safe_install_binary() {
    local source="$1"
    local name="$2"
    local dest_dir="${3:-${DOTFILES_BIN_DIR:-/usr/local/bin}}"
    local target="$dest_dir/$name"

    chmod +x "$source"

    if [[ -e "$target" || -L "$target" ]]; then
        if ! safe_remove "$target"; then
            log_error "Backup failed, aborting binary install: $target"
            return 1
        fi
    fi

    if [[ -w "$dest_dir" ]]; then
        mv "$source" "$target"
    else
        sudo mv "$source" "$target"
    fi
}
```

### Phase 3: Create Pre-flight Checks

**New file:** `lib/helpers/preflight.sh`

```bash
#!/usr/bin/env bash
# Pre-flight checks before installation

[[ -n "${_DOTFILES_PREFLIGHT_LOADED:-}" ]] && return 0
_DOTFILES_PREFLIGHT_LOADED=1

source "${BASH_SOURCE%/*}/log.sh"

run_preflight_checks() {
    local failed=0
    log_section "Running pre-flight checks"

    # Check backup directory writable
    local backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        log_error "Cannot create backup directory: $backup_dir"
        ((failed++))
    else
        local test_file="$backup_dir/.write_test_$$"
        if ! touch "$test_file" 2>/dev/null; then
            log_error "Backup directory not writable: $backup_dir"
            ((failed++))
        else
            rm -f "$test_file"
            log_ok "Backup directory: $backup_dir"
        fi
    fi

    # Check required commands
    local missing=()
    for cmd in jq git curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        ((failed++))
    else
        log_ok "Required commands available"
    fi

    # Check disk space (100MB minimum)
    local available_kb=$(df -k "$backup_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    if [[ $available_mb -lt 100 ]]; then
        log_error "Low disk space: ${available_mb}MB (need 100MB)"
        ((failed++))
    else
        log_ok "Disk space: ${available_mb}MB available"
    fi

    [[ $failed -eq 0 ]]
}
```

**Update:** `lib/dotfiles-system/install.sh` - add early call to `run_preflight_checks`

### Phase 4: Migrate Existing Code

**Files to update:**

1. **`tools/git/merge.sh`** (lines 17-25)
   - Add: `source "$DOTFILES_DIR/lib/helpers/safe-write.sh"`
   - Replace `cat > "$TARGET" << 'HEADER'` with:
     ```bash
     safe_write_heredoc "$TARGET" << 'HEADER'
     ```
   - Replace `echo "[include]..." >> "$TARGET"` with:
     ```bash
     safe_append_file "$TARGET" "[include]..."
     ```

2. **`tools/nvim/merge.sh`** (line 117)
   - Add source for safe-write.sh
   - Replace `cat > "$TARGET/lua/lib/layers.lua"` with `safe_write_heredoc`

3. **`tools/vscode/merge.sh`** (line 56)
   - Replace `jq -s 'add' ... > "$TARGET/keybindings.json"` with:
     ```bash
     safe_jq_write "$TARGET/keybindings.json" '-s add' "${keybindings_files[@]}"
     ```

4. **`lib/helpers/json-merge.sh`** (line 32)
   - Replace `jq -s '...' ... > "$output"` with `safe_jq_write`

5. **`lib/helpers/install-helpers.sh`** (lines 97-112)
   - Replace `install_binary()` implementation to use `safe_install_binary` pattern
   - Or: add `safe_remove "$target"` before the `mv`

6. **`lib/dotfiles-system/lib/builtins.sh`**
   - `builtin_merge_source()` (line 238): check `safe_remove` return value
   - `builtin_merge_concat()`: same
   - `builtin_merge_json()`: same

### Phase 5: Add Linting (Optional)

**New file:** `scripts/lint-safe-writes.sh`

Script that greps for unsafe patterns like `cat >`, `echo >`, `jq >` in tools/ and lib/ (excluding tests). Exit non-zero if found.

### Phase 6: Update CLAUDE.md

Add section:
```markdown
## Safe File Operations

All file writes must use safe-write helpers to ensure backups:

- `safe_write_file "$target" "content"` - write with backup
- `safe_write_heredoc "$target" <<EOF` - heredoc with backup
- `safe_append_file "$target" "content"` - append with backup on first use
- `safe_jq_write "$target" 'filter' inputs...` - jq output with backup

Never use `cat >`, `echo >`, or `jq ... >` directly in tool scripts.
```

---

## Order of Implementation

1. Enhance `safe_remove()` in `lib/dotfiles-system/lib/utils.sh`
2. Create `lib/helpers/safe-write.sh`
3. Create `lib/helpers/preflight.sh`
4. Update `lib/dotfiles-system/install.sh` to call preflight
5. Migrate `tools/git/merge.sh`
6. Migrate `tools/nvim/merge.sh`
7. Migrate `tools/vscode/merge.sh`
8. Migrate `lib/helpers/json-merge.sh`
9. Migrate `lib/helpers/install-helpers.sh`
10. Update `lib/dotfiles-system/lib/builtins.sh`
11. Update `CLAUDE.md`
12. (Optional) Add `scripts/lint-safe-writes.sh`

---

## Verification

1. `./install.sh personal-mac --dry-run` - pre-flight should pass
2. Create dummy file at `~/.gitconfig`, run install, verify backup in `~/.dotfiles-backup/`
3. `chmod 000 ~/.dotfiles-backup`, run install - should fail gracefully with recovery message
4. Run linting script - should find no unsafe patterns
