# Modular Architecture Implementation Plan

> **Purpose**: Re-architect the dotfiles system with clear module boundaries, enforceable contracts, and comprehensive testability through dependency injection and mocking.

> **Status**: 🟢 Phase 6 Complete - Ready for Phase 7 (Migration)

> **Last Updated**: 2026-01-11

---

## Table of Contents

1. [Overview](#overview)
2. [Current State Analysis](#current-state-analysis)
3. [Target Architecture](#target-architecture)
4. [Implementation Phases](#implementation-phases)
5. [Phase Details](#phase-details)
6. [Documentation Requirements](#documentation-requirements)
7. [Testing Strategy](#testing-strategy)
8. [Migration & Compatibility](#migration--compatibility)
9. [Plan Maintenance](#plan-maintenance)

---

## Overview

### Goals

1. **Clear Module Boundaries**: Each module has explicit public API, private implementation, and declared dependencies
2. **Enforceable Contracts**: Data structures validated at boundaries; fail fast on invalid input
3. **Testability via DI**: All I/O abstracted behind injectable interfaces; tests use mocks
4. **Focused Unit Tests**: Each test file tests ONE module; relies on contracts for integration
5. **Self-Documenting**: Architecture documented in-place via README.md in each module directory

### Non-Goals

- Changing the user-facing tool.conf or machine profile format (maintain compatibility)
- Rewriting working tool merge scripts unnecessarily
- Adding features beyond architectural improvements

### Success Criteria

- [ ] All modules have README.md documenting public API and contracts
- [ ] All I/O goes through injectable `fs` module
- [ ] All configs validated at parse time with clear error messages
- [ ] Unit tests use mocks; no filesystem side effects
- [ ] Integration tests verify end-to-end with real filesystem
- [ ] Zero regressions in existing functionality

---

## Current State Analysis

### Directory Structure (Current)

```
lib/
├── dotfiles-system/           # Framework (git submodule)
│   ├── install.sh             # Main entry point
│   ├── lib/
│   │   ├── utils.sh           # Mixed utilities (safe_remove, find_config_file, etc.)
│   │   ├── layers.sh          # TOOL_CTX global, layer resolution
│   │   ├── hooks.sh           # Hook execution, env building
│   │   ├── builtins.sh        # Builtin merge/install strategies
│   │   ├── repos.sh           # External repo management
│   │   └── log.sh             # Logging
│   └── test/
│       ├── run_tests.sh
│       ├── test_utils.sh
│       └── unit/test_*.sh
│
└── helpers/                   # Custom helpers
    ├── safe-write.sh
    ├── preflight.sh
    ├── symlink-factory.sh
    ├── json-merge.sh
    ├── install-helpers.sh
    ├── platform.sh
    ├── pkg-manager.sh
    └── extension-installer.sh
```

### Key Problems

| Problem | Location | Impact |
|---------|----------|--------|
| Global mutable state | `layers.sh` - TOOL_CTX | Hard to test, unpredictable |
| Legacy duplicate globals | `layers.sh` - TOOL_TARGET, TOOL_LAYERS | Confusion, maintenance burden |
| String-based layer specs | `tool.conf` parsing | Fragile, implicit parsing |
| No input validation | `parse_tool_conf()` | Errors surface late |
| Tight coupling | Helpers source each other | Can't test in isolation |
| Mixed concerns | `utils.sh` | Too many unrelated functions |
| Tests touch filesystem | `test/unit/*.sh` | Slow, side effects, flaky |

### Data Flow (Current)

```
install.sh
    → source machines/profile.sh     (sets TOOLS array, *_layers arrays)
    → for each tool:
        → parse_tool_conf()          (populates global TOOL_CTX)
        → resolve_layers()           (mutates TOOL_CTX)
        → build_hook_env()           (exports env vars)
        → run_merge_hook()           (reads TOOL_CTX, env vars)
```

**Problem**: Every step relies on global state mutation. Can't test `run_merge_hook()` without setting up all the globals.

---

## Target Architecture

### Directory Structure (Target)

```
lib/dotfiles-system/
├── install.sh                 # Entry point (thin wrapper)
├── lib/
│   ├── core/                  # Core modules with clear boundaries
│   │   ├── README.md          # Core module overview
│   │   ├── fs.sh              # Filesystem abstraction (injectable)
│   │   ├── log.sh             # Logging (injectable)
│   │   ├── backup.sh          # Backup operations (uses fs)
│   │   └── errors.sh          # Error codes and handling
│   │
│   ├── config/                # Configuration parsing & validation
│   │   ├── README.md          # Config module overview
│   │   ├── parser.sh          # Parse tool.conf files
│   │   ├── validator.sh       # Validate parsed configs
│   │   ├── schema.sh          # Schema definitions (contracts)
│   │   └── machine.sh         # Machine profile loading
│   │
│   ├── resolver/              # Layer and path resolution
│   │   ├── README.md          # Resolver module overview
│   │   ├── layers.sh          # Layer resolution logic
│   │   ├── paths.sh           # Path expansion and validation
│   │   └── repos.sh           # External repo management
│   │
│   ├── executor/              # Hook execution
│   │   ├── README.md          # Executor module overview
│   │   ├── registry.sh        # Strategy registry
│   │   ├── runner.sh          # Hook runner (isolated env)
│   │   └── builtins/          # Builtin strategies
│   │       ├── symlink.sh
│   │       ├── concat.sh
│   │       ├── source.sh
│   │       └── json-merge.sh
│   │
│   ├── orchestrator.sh        # Main workflow coordination
│   │
│   └── contracts/             # Contract definitions (documentation + validation)
│       ├── README.md          # Contract overview
│       ├── tool_config.sh     # ToolConfig contract
│       ├── layer_spec.sh      # LayerSpec contract
│       ├── hook_result.sh     # HookResult contract
│       └── machine_config.sh  # MachineConfig contract
│
└── test/
    ├── run_tests.sh
    ├── lib/
    │   ├── test_utils.sh      # Test framework
    │   ├── mocks/             # Mock implementations
    │   │   ├── fs_mock.sh     # Mock filesystem
    │   │   └── log_mock.sh    # Mock logger (captures output)
    │   └── fixtures/          # Test data
    │       ├── tool_configs/
    │       └── machine_profiles/
    │
    ├── unit/                  # Unit tests (use mocks)
    │   ├── core/
    │   │   ├── test_fs.sh
    │   │   ├── test_backup.sh
    │   │   └── test_errors.sh
    │   ├── config/
    │   │   ├── test_parser.sh
    │   │   ├── test_validator.sh
    │   │   └── test_machine.sh
    │   ├── resolver/
    │   │   ├── test_layers.sh
    │   │   ├── test_paths.sh
    │   │   └── test_repos.sh
    │   └── executor/
    │       ├── test_registry.sh
    │       ├── test_runner.sh
    │       └── builtins/
    │           └── test_*.sh
    │
    └── integration/           # Integration tests (real filesystem)
        ├── test_full_install.sh
        ├── test_tool_workflow.sh
        └── test_backup_restore.sh
```

### Module Dependency Graph

```
                    ┌─────────────────┐
                    │   install.sh    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  orchestrator   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼───────┐   ┌────────▼────────┐   ┌──────▼───────┐
│    config/    │   │    resolver/    │   │   executor/  │
│  parser.sh    │   │   layers.sh     │   │  registry.sh │
│  validator.sh │   │   paths.sh      │   │  runner.sh   │
│  machine.sh   │   │   repos.sh      │   │  builtins/   │
└───────┬───────┘   └────────┬────────┘   └──────┬───────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                    ┌────────▼────────┐
                    │     core/       │
                    │   fs.sh         │
                    │   log.sh        │
                    │   backup.sh     │
                    │   errors.sh     │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   contracts/    │
                    │  (validation)   │
                    └─────────────────┘
```

**Rule**: Dependencies only flow downward. No circular dependencies.

### Data Flow (Target)

```
install.sh(profile)
    │
    ▼
orchestrator.process(profile, deps)     # deps = {fs, log, backup}
    │
    ├─► config/machine.load(profile)
    │       → MachineConfig (validated)
    │
    ├─► for each tool in MachineConfig.tools:
    │       │
    │       ├─► config/parser.parse(tool_dir)
    │       │       → RawConfig
    │       │
    │       ├─► config/validator.validate(RawConfig)
    │       │       → ToolConfig (validated) or ERROR
    │       │
    │       ├─► resolver/layers.resolve(ToolConfig)
    │       │       → ResolvedConfig (with absolute paths)
    │       │
    │       ├─► executor/runner.execute(ResolvedConfig, deps)
    │       │       → HookResult
    │       │
    │       └─► collect results
    │
    └─► return AggregateResult
```

**Key Change**: Every function receives explicit inputs, returns explicit outputs. No global state mutation.

---

## Implementation Phases

| Phase | Name | Description | Dependencies |
|-------|------|-------------|--------------|
| 1 | Core Infrastructure | fs, log, backup, errors modules | None |
| 2 | Contracts | Schema definitions and validators | Phase 1 |
| 3 | Config Module | Parser and validator | Phases 1, 2 |
| 4 | Resolver Module | Layer and path resolution | Phases 1, 2, 3 |
| 5 | Executor Module | Registry and hook runner | Phases 1, 2, 3, 4 |
| 6 | Orchestrator | Main workflow coordination | Phases 1-5 |
| 7 | Migration | Migrate existing code, remove legacy | Phase 6 |
| 8 | Cleanup | Remove deprecated code, final polish | Phase 7 |

### Phase Status Tracking

Update this table as work progresses:

| Phase | Status | Started | Completed | Notes |
|-------|--------|---------|-----------|-------|
| 1 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Core modules implemented with mock support |
| 2 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Contracts module with LayerSpec, ToolConfig, MachineConfig, HookResult |
| 3 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Config module with parser, validator, machine loader (107 new tests) |
| 4 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Resolver module with paths, repos, layers (116 new tests, 410 total) |
| 5 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Executor module with registry, runner, 4 builtins (39 new tests, 449 total) |
| 6 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Orchestrator with unit/integration tests (40 new unit, 31 integration, 520 total) |
| 7 | 🔴 Not Started | - | - | - |
| 8 | 🔴 Not Started | - | - | - |

Status key: 🔴 Not Started | 🟡 In Progress | 🟢 Complete | 🔵 Blocked

---

## Phase Details

### Phase 1: Core Infrastructure

**Goal**: Create foundational modules with injectable backends for testing.

**Files to Create**:

#### `lib/core/README.md`
```markdown
# Core Module

Low-level infrastructure used by all other modules.

## Modules

- `fs.sh` - Filesystem operations with mock support
- `log.sh` - Logging with configurable output
- `backup.sh` - Backup creation and restoration
- `errors.sh` - Error codes and handling utilities

## Usage

All modules support dependency injection for testing:

    source "$LIB_DIR/core/fs.sh"
    fs_init "mock"  # Use mock backend for tests
    fs_init "real"  # Use real filesystem (default)
```

#### `lib/core/fs.sh`

```bash
#!/usr/bin/env bash
# MODULE: core/fs
# PURPOSE: Filesystem operations with injectable backend
#
# PUBLIC API:
#   fs_init(backend)           - Initialize with "real" or "mock" backend
#   fs_read(path)              - Read file contents to stdout
#   fs_write(path, content)    - Write content to file
#   fs_append(path, content)   - Append content to file
#   fs_exists(path)            - Check if path exists (file or dir)
#   fs_is_file(path)           - Check if path is a regular file
#   fs_is_dir(path)            - Check if path is a directory
#   fs_is_symlink(path)        - Check if path is a symlink
#   fs_remove(path)            - Remove file or empty directory
#   fs_remove_rf(path)         - Remove recursively
#   fs_mkdir(path)             - Create directory (with parents)
#   fs_symlink(source, target) - Create symlink
#   fs_readlink(path)          - Read symlink target
#   fs_list(path)              - List directory contents
#   fs_copy(src, dst)          - Copy file
#
# MOCK API (for testing):
#   fs_mock_reset()            - Clear all mock state
#   fs_mock_set(path, content) - Set mock file content
#   fs_mock_get(path)          - Get mock file content
#   fs_mock_calls()            - Get list of operations performed
#   fs_mock_assert_written(path, content) - Assert file was written
#
# DEPENDENCIES: None (leaf module)

[[ -n "${_FS_LOADED:-}" ]] && return 0
_FS_LOADED=1

# --- State ---
_fs_backend="real"
declare -A _fs_mock_files=()
declare -a _fs_mock_calls=()

# --- Initialization ---

fs_init() {
    _fs_backend="${1:-real}"
    if [[ "$_fs_backend" == "mock" ]]; then
        _fs_mock_files=()
        _fs_mock_calls=()
    fi
}

# --- Public API ---

fs_read() {
    local path="$1"
    _fs_mock_calls+=("read:$path")

    case "$_fs_backend" in
        real) cat "$path" 2>/dev/null ;;
        mock) printf '%s' "${_fs_mock_files[$path]:-}" ;;
    esac
}

fs_write() {
    local path="$1" content="$2"
    _fs_mock_calls+=("write:$path")

    case "$_fs_backend" in
        real)
            local dir
            dir=$(dirname "$path")
            [[ -d "$dir" ]] || mkdir -p "$dir"
            printf '%s' "$content" > "$path"
            ;;
        mock)
            _fs_mock_files["$path"]="$content"
            ;;
    esac
}

fs_exists() {
    local path="$1"
    case "$_fs_backend" in
        real) [[ -e "$path" ]] ;;
        mock) [[ -v "_fs_mock_files[$path]" ]] ;;
    esac
}

fs_is_file() {
    local path="$1"
    case "$_fs_backend" in
        real) [[ -f "$path" ]] ;;
        mock) [[ -v "_fs_mock_files[$path]" && "${_fs_mock_files[$path]}" != "__DIR__" ]] ;;
    esac
}

fs_is_dir() {
    local path="$1"
    case "$_fs_backend" in
        real) [[ -d "$path" ]] ;;
        mock) [[ -v "_fs_mock_files[$path]" && "${_fs_mock_files[$path]}" == "__DIR__" ]] ;;
    esac
}

fs_remove() {
    local path="$1"
    _fs_mock_calls+=("remove:$path")

    case "$_fs_backend" in
        real) rm "$path" 2>/dev/null ;;
        mock) unset "_fs_mock_files[$path]" ;;
    esac
}

fs_mkdir() {
    local path="$1"
    _fs_mock_calls+=("mkdir:$path")

    case "$_fs_backend" in
        real) mkdir -p "$path" ;;
        mock) _fs_mock_files["$path"]="__DIR__" ;;
    esac
}

fs_symlink() {
    local source="$1" target="$2"
    _fs_mock_calls+=("symlink:$source->$target")

    case "$_fs_backend" in
        real) ln -sf "$source" "$target" ;;
        mock) _fs_mock_files["$target"]="__SYMLINK:$source" ;;
    esac
}

# ... (additional functions follow same pattern)

# --- Mock API ---

fs_mock_reset() {
    _fs_mock_files=()
    _fs_mock_calls=()
}

fs_mock_set() {
    local path="$1" content="$2"
    _fs_mock_files["$path"]="$content"
}

fs_mock_get() {
    local path="$1"
    printf '%s' "${_fs_mock_files[$path]:-}"
}

fs_mock_calls() {
    printf '%s\n' "${_fs_mock_calls[@]}"
}

fs_mock_assert_written() {
    local path="$1" expected="$2"
    [[ "${_fs_mock_files[$path]:-}" == "$expected" ]]
}
```

#### `lib/core/errors.sh`

```bash
#!/usr/bin/env bash
# MODULE: core/errors
# PURPOSE: Error codes and handling utilities
#
# PUBLIC API:
#   Error codes (constants):
#     E_OK=0              - Success
#     E_GENERIC=1         - Generic failure
#     E_INVALID_INPUT=2   - Invalid input/arguments
#     E_NOT_FOUND=3       - File/resource not found
#     E_PERMISSION=4      - Permission denied
#     E_VALIDATION=5      - Validation failed
#     E_DEPENDENCY=6      - Missing dependency
#     E_BACKUP=7          - Backup operation failed
#
#   error_message(code)   - Get human-readable message for code
#   error_die(code, msg)  - Log error and exit with code
#
# DEPENDENCIES: core/log.sh (optional, falls back to echo)

[[ -n "${_ERRORS_LOADED:-}" ]] && return 0
_ERRORS_LOADED=1

# --- Error Codes ---
readonly E_OK=0
readonly E_GENERIC=1
readonly E_INVALID_INPUT=2
readonly E_NOT_FOUND=3
readonly E_PERMISSION=4
readonly E_VALIDATION=5
readonly E_DEPENDENCY=6
readonly E_BACKUP=7

# --- Error Messages ---
declare -A _ERROR_MESSAGES=(
    [0]="Success"
    [1]="Operation failed"
    [2]="Invalid input or arguments"
    [3]="File or resource not found"
    [4]="Permission denied"
    [5]="Validation failed"
    [6]="Missing required dependency"
    [7]="Backup operation failed"
)

error_message() {
    local code="$1"
    printf '%s' "${_ERROR_MESSAGES[$code]:-Unknown error}"
}

error_die() {
    local code="$1" msg="$2"
    if type -t log_error &>/dev/null; then
        log_error "$msg"
    else
        echo "ERROR: $msg" >&2
    fi
    exit "$code"
}
```

#### `lib/core/log.sh`

```bash
#!/usr/bin/env bash
# MODULE: core/log
# PURPOSE: Logging with configurable output
#
# PUBLIC API:
#   log_init(config)         - Initialize logger (config: output, level, color)
#   log_section(msg)         - Major section header
#   log_step(msg)            - Step within section
#   log_detail(msg)          - Detail message (verbose only)
#   log_ok(msg)              - Success message
#   log_warn(msg)            - Warning message
#   log_error(msg)           - Error message
#   log_skip(msg)            - Skipped operation
#
# MOCK API:
#   log_mock_reset()         - Clear captured logs
#   log_mock_get()           - Get all captured logs
#   log_mock_assert(pattern) - Assert log contains pattern
#
# DEPENDENCIES: None

[[ -n "${_LOG_LOADED:-}" ]] && return 0
_LOG_LOADED=1

# --- State ---
_log_output="/dev/stderr"  # or "mock" for testing
_log_level="info"          # debug, info, warn, error
_log_color=1
declare -a _log_mock_buffer=()

# --- Initialization ---

log_init() {
    local -n config=$1 2>/dev/null || true
    _log_output="${config[output]:-/dev/stderr}"
    _log_level="${config[level]:-info}"
    _log_color="${config[color]:-1}"

    if [[ "$_log_output" == "mock" ]]; then
        _log_mock_buffer=()
    fi
}

# --- Internal ---

_log_write() {
    local level="$1" msg="$2" prefix="$3" color="$4"

    if [[ "$_log_output" == "mock" ]]; then
        _log_mock_buffer+=("[$level] $msg")
        return 0
    fi

    if [[ "$_log_color" == 1 && -t 2 ]]; then
        printf '%b%s%b %s\n' "$color" "$prefix" '\033[0m' "$msg" >> "$_log_output"
    else
        printf '%s %s\n' "$prefix" "$msg" >> "$_log_output"
    fi
}

# --- Public API ---

log_section() { _log_write "section" "$1" "==>" '\033[1;34m'; }
log_step()    { _log_write "step" "$1" "  ->" '\033[0;36m'; }
log_detail()  { [[ "$_log_level" == "debug" ]] && _log_write "detail" "$1" "     " '\033[0;37m'; }
log_ok()      { _log_write "ok" "$1" "  ✓" '\033[0;32m'; }
log_warn()    { _log_write "warn" "$1" "  ⚠" '\033[0;33m'; }
log_error()   { _log_write "error" "$1" "  ✗" '\033[0;31m'; }
log_skip()    { _log_write "skip" "$1" "  ○" '\033[0;90m'; }

# --- Mock API ---

log_mock_reset() { _log_mock_buffer=(); }
log_mock_get() { printf '%s\n' "${_log_mock_buffer[@]}"; }
log_mock_assert() {
    local pattern="$1"
    printf '%s\n' "${_log_mock_buffer[@]}" | grep -q "$pattern"
}
```

#### `lib/core/backup.sh`

```bash
#!/usr/bin/env bash
# MODULE: core/backup
# PURPOSE: Backup creation and restoration
#
# PUBLIC API:
#   backup_init(config)           - Initialize (config: dir, fs)
#   backup_create(path)           - Backup file/dir, return backup path
#   backup_restore(backup_path)   - Restore from backup
#   backup_list()                 - List all backups
#   backup_cleanup(days)          - Remove backups older than N days
#
# DEPENDENCIES: core/fs.sh, core/log.sh, core/errors.sh

[[ -n "${_BACKUP_LOADED:-}" ]] && return 0
_BACKUP_LOADED=1

# Source dependencies
_BACKUP_DIR="${BASH_SOURCE[0]%/*}"
source "$_BACKUP_DIR/fs.sh"
source "$_BACKUP_DIR/log.sh"
source "$_BACKUP_DIR/errors.sh"

# --- State ---
_backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"

# --- Initialization ---

backup_init() {
    local -n config=$1 2>/dev/null || true
    _backup_dir="${config[dir]:-$_backup_dir}"
    fs_mkdir "$_backup_dir"
}

# --- Public API ---

backup_create() {
    local path="$1"

    if ! fs_exists "$path"; then
        return $E_OK  # Nothing to backup
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local basename
    basename=$(basename "$path")
    local backup_path="$_backup_dir/${basename}.${timestamp}"

    log_detail "Backing up $path to $backup_path"

    if fs_is_dir "$path"; then
        # For real backend, use cp -r
        if [[ "$_fs_backend" == "real" ]]; then
            cp -r "$path" "$backup_path" || return $E_BACKUP
        else
            fs_write "$backup_path" "$(fs_read "$path")"
        fi
    else
        fs_write "$backup_path" "$(fs_read "$path")"
    fi

    printf '%s' "$backup_path"
    return $E_OK
}

backup_restore() {
    local backup_path="$1"
    local original_path

    # Extract original path from backup name
    # Format: /backup/dir/filename.20240115_123456 -> determine original location
    # This requires storing metadata - simplified version:

    if ! fs_exists "$backup_path"; then
        log_error "Backup not found: $backup_path"
        return $E_NOT_FOUND
    fi

    log_step "Restoring from $backup_path"
    # Implementation depends on how we store original path metadata
    return $E_OK
}

backup_list() {
    if [[ "$_fs_backend" == "real" ]]; then
        ls -la "$_backup_dir" 2>/dev/null
    else
        for path in "${!_fs_mock_files[@]}"; do
            [[ "$path" == "$_backup_dir"/* ]] && echo "$path"
        done
    fi
}
```

**Tests to Create** (Phase 1):

- `test/unit/core/test_fs.sh` - Test all fs functions with mock backend
- `test/unit/core/test_log.sh` - Test log functions, verify mock captures
- `test/unit/core/test_backup.sh` - Test backup create/restore with mocked fs
- `test/unit/core/test_errors.sh` - Test error codes and messages

**Deliverables**:
- [x] `lib/core/README.md`
- [x] `lib/core/fs.sh` with mock support
- [x] `lib/core/log.sh` with mock support
- [x] `lib/core/backup.sh`
- [x] `lib/core/errors.sh`
- [x] `test/unit/core/test_fs.sh`
- [x] `test/unit/core/test_log.sh`
- [x] `test/unit/core/test_backup.sh`
- [x] `test/unit/core/test_errors.sh`
- [x] All tests passing (147 tests)

**Lessons Learned**:
- Bash associative array key checks: Use `[[ -n "${arr[$key]+set}" ]]` instead of `[[ -v "arr[$key]" ]]` for variable keys
- Subshell state isolation: Functions that capture output via `$(...)` run in subshells; mock state changes don't persist to caller
- Solution: Use nameref (`local -n`) output parameters instead of stdout for functions that modify mock state
- Variable naming: Avoid variable name collisions between caller and callee when using namerefs

---

### Phase 2: Contracts

**Goal**: Define data structure contracts with validation functions.

> **Note**: The example code below was the initial design sketch. The actual implementation
> uses indexed keys (`layer_0_name`, `layer_0_source`) instead of JSON, and keeps validation
> pure (no filesystem access). See `lib/contracts/*.sh` for the actual API.

**Files to Create**:

#### `lib/contracts/README.md`

```markdown
# Contracts Module

Defines data structures and validation for all module boundaries.

## Philosophy

Contracts are the "types" of our bash system. Every function that crosses
a module boundary should:

1. Accept data conforming to a contract
2. Validate input at entry
3. Return data conforming to a contract

## Contracts

### ToolConfig

Represents a parsed and validated tool configuration.

Fields:
- `tool_name` (required): Tool identifier (e.g., "git", "nvim")
- `target` (required): Absolute path to installation target
- `merge_hook` (required): Hook specification ("builtin:*" or script path)
- `install_hook` (optional): Install hook specification
- `layers` (required): Array of LayerSpec

### LayerSpec

Represents a single configuration layer.

Fields:
- `name` (required): Layer name (e.g., "base", "stripe")
- `source` (required): Source type ("local" or repo name like "STRIPE_DOTFILES")
- `path` (required): Relative path within source
- `resolved_path` (computed): Absolute path after resolution

### MachineConfig

Represents a loaded machine profile.

Fields:
- `profile_name` (required): Profile identifier
- `tools` (required): Array of tool names to configure
- `tool_layers` (required): Associative array mapping tool -> layer names

### HookResult

Represents the result of hook execution.

Fields:
- `success` (required): Boolean (0 or 1)
- `error_code` (optional): Error code if failed
- `error_message` (optional): Human-readable error
- `files_modified` (optional): Array of paths modified
```

#### `lib/contracts/tool_config.sh`

```bash
#!/usr/bin/env bash
# CONTRACT: ToolConfig
# PURPOSE: Tool configuration data structure and validation

[[ -n "${_CONTRACT_TOOL_CONFIG_LOADED:-}" ]] && return 0
_CONTRACT_TOOL_CONFIG_LOADED=1

source "${BASH_SOURCE[0]%/*}/../core/errors.sh"

# Create a new ToolConfig
# Usage: tool_config_new result_ref tool_name target merge_hook
tool_config_new() {
    local -n __result=$1
    __result=(
        [tool_name]="$2"
        [target]="$3"
        [merge_hook]="$4"
        [install_hook]=""
        [layers_json]="[]"
    )
}

# Validate a ToolConfig
# Returns: E_OK if valid, E_VALIDATION if not (with error to stderr)
tool_config_validate() {
    local -n __config=$1
    local errors=()

    # Required fields
    [[ -z "${__config[tool_name]:-}" ]] && errors+=("tool_name is required")
    [[ -z "${__config[target]:-}" ]] && errors+=("target is required")
    [[ -z "${__config[merge_hook]:-}" ]] && errors+=("merge_hook is required")

    # Target must be absolute path
    if [[ -n "${__config[target]:-}" && "${__config[target]}" != /* && "${__config[target]}" != ~* ]]; then
        errors+=("target must be absolute path: ${__config[target]}")
    fi

    # merge_hook must be builtin:* or existing file
    local hook="${__config[merge_hook]:-}"
    if [[ -n "$hook" ]]; then
        case "$hook" in
            builtin:*) : ;;  # Valid builtin
            *)
                if [[ ! -f "$hook" ]]; then
                    errors+=("merge_hook file not found: $hook")
                fi
                ;;
        esac
    fi

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'ToolConfig validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Set install hook
tool_config_set_install_hook() {
    local -n __config=$1
    __config[install_hook]="$2"
}

# Add a layer (as JSON for structured storage)
tool_config_add_layer() {
    local -n __config=$1
    local name="$2" source="$3" path="$4"

    # Append to layers_json (simple approach - real impl might use jq)
    local layer="{\"name\":\"$name\",\"source\":\"$source\",\"path\":\"$path\"}"
    if [[ "${__config[layers_json]}" == "[]" ]]; then
        __config[layers_json]="[$layer]"
    else
        __config[layers_json]="${__config[layers_json]%]},$layer]"
    fi
}

# Get layers as newline-separated "name:source:path" strings (for bash iteration)
tool_config_get_layers() {
    local -n __config=$1
    # Parse layers_json - simplified; real impl uses jq
    echo "${__config[layers_json]}" | tr '{}[]"' ' ' | tr ',' '\n' | \
        grep -o 'name:[^,]*' | sed 's/name://'
    # NOTE: This is simplified - real implementation needs proper JSON parsing
}
```

#### `lib/contracts/layer_spec.sh`

```bash
#!/usr/bin/env bash
# CONTRACT: LayerSpec
# PURPOSE: Layer specification data structure

[[ -n "${_CONTRACT_LAYER_SPEC_LOADED:-}" ]] && return 0
_CONTRACT_LAYER_SPEC_LOADED=1

source "${BASH_SOURCE[0]%/*}/../core/errors.sh"

# Create a new LayerSpec
layer_spec_new() {
    local -n __result=$1
    __result=(
        [name]="$2"
        [source]="$3"
        [path]="$4"
        [resolved_path]=""
    )
}

# Validate a LayerSpec
layer_spec_validate() {
    local -n __spec=$1
    local errors=()

    [[ -z "${__spec[name]:-}" ]] && errors+=("name is required")
    [[ -z "${__spec[source]:-}" ]] && errors+=("source is required")
    [[ -z "${__spec[path]:-}" ]] && errors+=("path is required")

    # source must be "local" or uppercase identifier (repo name)
    local src="${__spec[source]:-}"
    if [[ -n "$src" && "$src" != "local" && ! "$src" =~ ^[A-Z_]+$ ]]; then
        errors+=("source must be 'local' or REPO_NAME: $src")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'LayerSpec validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Set resolved path
layer_spec_set_resolved() {
    local -n __spec=$1
    __spec[resolved_path]="$2"
}
```

**Tests to Create** (Phase 2):

- `test/unit/contracts/test_tool_config.sh`
- `test/unit/contracts/test_layer_spec.sh`
- `test/unit/contracts/test_machine_config.sh`
- `test/unit/contracts/test_hook_result.sh`

**Deliverables**:
- [x] `lib/contracts/README.md`
- [x] `lib/contracts/tool_config.sh`
- [x] `lib/contracts/layer_spec.sh`
- [x] `lib/contracts/machine_config.sh`
- [x] `lib/contracts/hook_result.sh`
- [x] `test/unit/contracts/test_layer_spec.sh`
- [x] `test/unit/contracts/test_tool_config.sh`
- [x] `test/unit/contracts/test_machine_config.sh`
- [x] `test/unit/contracts/test_hook_result.sh`
- [x] All contract unit tests passing (187 total tests)

**Lessons Learned**:
- Bash associative arrays work well for struct-like contracts using indexed keys (e.g., `layer_0_name`, `layer_0_source`)
- Nameref parameters (`local -n`) enable clean getter/setter APIs
- Validation should list all errors at once (not fail on first) for better DX
- Contract validation is pure - no filesystem access, just data shape checking

---

### Phase 3: Config Module

**Goal**: Parse and validate configuration files into contract-conforming structures.

**Key Design Decisions**:

1. Parser produces raw key-value pairs
2. Validator converts to validated ToolConfig
3. Fail fast on invalid config (don't proceed with partial data)

**Files to Create**:

- `lib/config/README.md`
- `lib/config/parser.sh` - Parse tool.conf into raw associative array
- `lib/config/validator.sh` - Convert raw config to validated ToolConfig
- `lib/config/machine.sh` - Load machine profiles into MachineConfig

**Interface Example**:

```bash
# Parser - reads tool.conf into raw key-value pairs
parse_tool_conf() {
    local tool_dir="$1"
    local -n raw_config=$2
    # Populates raw_config with key-value pairs from tool.conf
    # Returns E_OK or E_NOT_FOUND
}

# Validator - converts raw config to validated ToolConfig contract
build_tool_config() {
    local -n raw=$1
    local -n tool_config=$2

    # Create contract using Phase 2 APIs
    tool_config_new tool_config "${raw[tool_name]}" "${raw[target]}" "${raw[merge_hook]}"

    # Add layers from raw config (layers_base, layers_work, etc.)
    for key in "${!raw[@]}"; do
        if [[ "$key" == layers_* ]]; then
            local layer_name="${key#layers_}"
            # Parse "source:path" format
            tool_config_add_layer tool_config "$layer_name" ...
        fi
    done

    # Validate using contract
    tool_config_validate tool_config
}

# Machine loader - loads profile into MachineConfig contract
load_machine_profile() {
    local profile="$1"
    local -n machine_config=$2

    # Source the profile, extract TOOLS array and *_layers arrays
    # Build MachineConfig using Phase 2 APIs
    machine_config_new machine_config "$profile"
    for tool in "${TOOLS[@]}"; do
        machine_config_add_tool machine_config "$tool"
        machine_config_set_tool_layers machine_config "$tool" ...
    done

    machine_config_validate machine_config
}
```

**Deliverables**:
- [x] `lib/config/README.md`
- [x] `lib/config/parser.sh`
- [x] `lib/config/validator.sh`
- [x] `lib/config/machine.sh`
- [x] `test/unit/config/test_parser.sh` (43 tests)
- [x] `test/unit/config/test_validator.sh` (32 tests)
- [x] `test/unit/config/test_machine.sh` (32 tests)
- [x] All tests passing (294 total tests)

**Lessons Learned**:
- Bash `set -e` with arithmetic: `((line_num++))` fails when `line_num=0` because `((0))` returns 1. Use `((++line_num))` for pre-increment or avoid post-increment with zero.
- Return code capture with `set -e`: Use `local rc=0; cmd || rc=$?` pattern to capture non-zero return codes without exiting.
- Machine config validation: Need to check both key existence AND non-empty value for tool layers.
- Parser design: Keeping parser output as raw key-value (no interpretation) makes validator simpler and more testable.

---

### Phase 4: Resolver Module

**Goal**: Resolve layer specifications to absolute paths, handle external repos.

**Files to Create**:

- `lib/resolver/README.md`
- `lib/resolver/layers.sh` - Layer resolution logic
- `lib/resolver/paths.sh` - Path expansion utilities
- `lib/resolver/repos.sh` - External repo management

**Key Changes from Current**:

1. No global state - takes ToolConfig, returns ResolvedConfig
2. Repo operations go through fs abstraction where possible
3. Clear separation: paths.sh for string manipulation, repos.sh for git operations

**Deliverables**:
- [x] `lib/resolver/README.md`
- [x] `lib/resolver/layers.sh`
- [x] `lib/resolver/paths.sh`
- [x] `lib/resolver/repos.sh`
- [x] `test/unit/resolver/test_layers.sh` (39 tests)
- [x] `test/unit/resolver/test_paths.sh` (42 tests)
- [x] `test/unit/resolver/test_repos.sh` (35 tests, with mock support for git operations)
- [x] All tests passing (410 total tests)

**Lessons Learned**:
- Path normalization is subtle: Need to handle `.`, `..`, multiple slashes, and relative vs absolute paths differently
- Mock strategy for git operations: Use `repos_mock_set_exists()` to control whether repo appears cloned without actual git calls
- Layer resolution builds on contracts: Using `tool_config_get_layer_*` and `tool_config_set_layer_resolved` makes the interface clean
- Separation of concerns: `paths.sh` is pure (no I/O), `repos.sh` manages state, `layers.sh` orchestrates both

---

### Phase 5: Executor Module

**Goal**: Execute hooks with proper isolation and strategy dispatch.

**Files to Create**:

- `lib/executor/README.md`
- `lib/executor/registry.sh` - Strategy registration and lookup
- `lib/executor/runner.sh` - Hook execution with isolated environment
- `lib/executor/builtins/*.sh` - Individual builtin strategies

**Key Design**:

```bash
# Registry pattern
declare -A MERGE_STRATEGIES
strategy_register "symlink" "builtin_merge_symlink"
strategy_register "concat" "builtin_merge_concat"

# Dispatch
strategy_execute() {
    local name="$1"
    local -n config=$2
    local -n deps=$3  # {fs, log, backup}

    local handler="${MERGE_STRATEGIES[$name]}"
    "$handler" config deps
}

# Hook runner - creates isolated subprocess
run_hook_isolated() {
    local hook_path="$1"
    local -n config=$2
    local -n env_vars=$3

    # Execute in subprocess with only specified env vars
    env -i "${env_vars[@]}" bash "$hook_path"
}
```

**Deliverables**:
- [x] `lib/executor/README.md`
- [x] `lib/executor/registry.sh`
- [x] `lib/executor/runner.sh`
- [x] `lib/executor/builtins/symlink.sh`
- [x] `lib/executor/builtins/concat.sh`
- [x] `lib/executor/builtins/source.sh`
- [x] `lib/executor/builtins/json-merge.sh`
- [x] `test/unit/executor/test_registry.sh` (14 tests)
- [x] `test/unit/executor/test_runner.sh` (17 tests)
- [x] `test/unit/executor/builtins/test_symlink.sh` (14 tests)
- [x] `test/unit/executor/builtins/test_concat.sh` (13 tests)
- [x] `test/unit/executor/builtins/test_source.sh` (14 tests)
- [x] `test/unit/executor/builtins/test_json_merge.sh` (14 tests)
- [x] All tests passing (449 total tests)

**Lessons Learned**:
- Builtin strategies share common patterns: file finding, backup, parent directory creation. Consider extracting shared utilities in future.
- Mock filesystem works well for testing I/O operations without side effects
- Strategy registry pattern allows easy extension with custom strategies
- HookResult contract provides consistent error reporting across all builtins
- Tilde expansion needs to happen at execution time, not parse time

---

### Phase 6: Orchestrator

**Goal**: Coordinate workflow using all modules, no direct I/O.

**File to Create**:

- `lib/orchestrator.sh`

**Key Design**:

```bash
# Main orchestration function - pure coordination, no I/O
orchestrate_install() {
    local profile="$1"
    local -n deps=$2  # Injected dependencies: {fs, log, backup}
    local -n result=$3

    # 1. Load machine config
    local -A machine_config
    load_machine_profile "$profile" machine_config || return $?

    # 2. Process each tool
    local -a results=()
    for tool in "${machine_config[tools]}"; do
        local -A tool_config
        local -A resolved_config
        local -A hook_result

        # Parse -> Validate -> Resolve -> Execute
        parse_tool_conf "$tool" tool_config || continue
        validate_tool_config tool_config || continue
        resolve_layers tool_config resolved_config || continue
        execute_tool resolved_config deps hook_result

        results+=("${hook_result[*]}")
    done

    # 3. Aggregate results
    result[tools_processed]=${#results[@]}
    # ...
}
```

**Deliverables**:
- [x] `lib/orchestrator.sh`
- [x] `test/unit/test_orchestrator.sh` (40 tests using all mocks)
- [x] `test/integration/test_full_workflow.sh` (31 tests with real filesystem)
- [x] All tests passing (520 total tests)

**Lessons Learned**:
- Orchestrator is pure coordination with no direct I/O - all I/O goes through injected modules
- Layer filtering from machine profile requires careful handling of associative array key iteration
- Dry-run mode is implemented by skipping hook execution and just logging what would happen
- Empty TOOLS array in machine profile is treated as validation failure (a profile with no tools is not useful)
- Integration tests use real temp directories to verify end-to-end workflows with actual filesystem operations
- Custom merge scripts receive environment variables (TOOL, TARGET, LAYERS, LAYER_PATHS, DOTFILES_DIR, OS) for flexibility

---

### Phase 7: Migration

**Goal**: Migrate existing code to use new modules, maintain backward compatibility.

**Tasks**:

1. Update `install.sh` to use new orchestrator
2. Migrate tool merge scripts to new contract
3. Update helpers to use fs abstraction
4. Remove legacy globals (TOOL_CTX, TOOL_TARGET, TOOL_LAYERS)
5. Update CLAUDE.md with new patterns

**Approach**:

- Create compatibility shim for transition period
- Migrate one tool at a time
- Run both old and new paths, compare results
- Remove old code only after all tools migrated

**Deliverables**:
- [ ] Updated `install.sh`
- [ ] Migrated `tools/*/merge.sh` scripts
- [ ] Migrated `lib/helpers/*.sh`
- [ ] Removed legacy code
- [ ] All existing tests still pass
- [ ] Updated `CLAUDE.md`

---

### Phase 8: Cleanup

**Goal**: Final polish, documentation, and technical debt cleanup.

**Tasks**:

1. Remove all deprecated functions
2. Remove compatibility shims
3. Final documentation review
4. Performance optimization if needed
5. Update all README files

**Deliverables**:
- [ ] No deprecated code remaining
- [ ] All documentation current
- [ ] Full test coverage report
- [ ] Performance baseline established

---

## Documentation Requirements

Each module directory MUST contain a `README.md` with:

### Required Sections

```markdown
# Module Name

Brief description of module purpose.

## Public API

List all public functions with signatures:

    function_name(param1, param2) -> return_type
        Description of what it does.

    another_function(param) -> return_type
        Description.

## Dependencies

List modules this module depends on:

- `core/fs.sh` - Filesystem operations
- `core/log.sh` - Logging

## Contracts

List contracts this module produces/consumes:

- Produces: ToolConfig
- Consumes: LayerSpec, MachineConfig

## Usage Example

    source "lib/module/file.sh"

    # Example usage
    my_function "arg1" "arg2"

## Testing

How to run tests for this module:

    ./test/run_tests.sh unit/module/
```

### Architecture Documentation

Create `lib/ARCHITECTURE.md` with:

- High-level system overview
- Module dependency graph
- Data flow diagrams
- Contract summary table
- Extension points for new tools

---

## Testing Strategy

### Test Organization

```
test/
├── run_tests.sh           # Test runner
├── lib/
│   ├── test_utils.sh      # Assertions, setup/teardown
│   ├── mocks/
│   │   ├── fs_mock.sh     # Mock filesystem
│   │   └── log_mock.sh    # Mock logger
│   └── fixtures/
│       ├── tool_configs/  # Sample tool.conf files
│       │   ├── valid/
│       │   └── invalid/
│       └── machine_profiles/
│
├── unit/                  # Unit tests (isolated, use mocks)
│   └── <module>/
│       └── test_<file>.sh
│
└── integration/           # Integration tests (real filesystem)
    └── test_<scenario>.sh
```

### Unit Test Rules

1. **One Module Per Test File**: `test_parser.sh` only tests `parser.sh`
2. **Use Mocks**: All I/O through mocked fs/log
3. **Test Contract Boundaries**: Input validation, output format
4. **Fast**: < 100ms per test file
5. **Isolated**: No shared state between tests
6. **Deterministic**: Same result every run

### Unit Test Template

```bash
#!/usr/bin/env bash
# Test: config/parser.sh

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../../lib/test_utils.sh"
source "$TEST_DIR/../../lib/mocks/fs_mock.sh"

# Module under test
source "$LIB_DIR/config/parser.sh"

setup() {
    fs_init "mock"
    fs_mock_reset
}

teardown() {
    fs_mock_reset
}

test_parse_valid_tool_conf() {
    # Arrange
    fs_mock_set "/tools/git/tool.conf" 'target="~/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"'

    # Act
    declare -A result
    parse_tool_conf "/tools/git" result
    local rc=$?

    # Assert
    assert_equals 0 $rc
    assert_equals '~/.gitconfig' "${result[target]}"
    assert_equals 'builtin:symlink' "${result[merge_hook]}"
    assert_equals 'local:configs/git' "${result[layers_base]}"
}

test_parse_missing_file_returns_error() {
    # Arrange - no mock file set

    # Act
    declare -A result
    parse_tool_conf "/tools/nonexistent" result
    local rc=$?

    # Assert
    assert_equals $E_NOT_FOUND $rc
}

test_parse_ignores_comments() {
    fs_mock_set "/tools/git/tool.conf" '# Comment
target="~/.gitconfig"  # inline comment
merge_hook="builtin:symlink"'

    declare -A result
    parse_tool_conf "/tools/git" result

    assert_equals '~/.gitconfig' "${result[target]}"
}

run_tests
```

### Integration Test Rules

1. **Real Filesystem**: Use temp directories
2. **Full Workflows**: Test complete scenarios
3. **Cleanup**: Always remove temp files
4. **Slow OK**: Can take seconds
5. **Document Prerequisites**: External tools needed

### Integration Test Template

```bash
#!/usr/bin/env bash
# Integration Test: Full tool installation workflow

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/../lib/test_utils.sh"

TEMP_DIR=""

setup() {
    TEMP_DIR=$(mktemp -d)
    export DOTFILES_DIR="$TEMP_DIR/dotfiles"
    export HOME="$TEMP_DIR/home"
    mkdir -p "$DOTFILES_DIR" "$HOME"

    # Set up minimal dotfiles structure
    mkdir -p "$DOTFILES_DIR/tools/test"
    mkdir -p "$DOTFILES_DIR/configs/test"
    echo 'test config' > "$DOTFILES_DIR/configs/test/config"
}

teardown() {
    [[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

test_install_symlink_tool() {
    # Arrange
    cat > "$DOTFILES_DIR/tools/test/tool.conf" << 'EOF'
target="~/.testrc"
merge_hook="builtin:symlink"
layers_base="local:configs/test"
EOF

    cat > "$DOTFILES_DIR/machines/test.sh" << 'EOF'
TOOLS=(test)
test_layers=(base)
EOF

    # Act
    "$DOTFILES_DIR/install.sh" test
    local rc=$?

    # Assert
    assert_equals 0 $rc
    assert_file_exists "$HOME/.testrc"
    assert_symlink "$HOME/.testrc"
}

run_tests
```

---

## Migration & Compatibility

### Backward Compatibility Strategy

1. **Phase 7a**: Create shim layer that maps old globals to new contracts
2. **Phase 7b**: Migrate tools one at a time (start with simplest)
3. **Phase 7c**: Run parallel validation (old + new, compare results)
4. **Phase 7d**: Remove shims once all tools migrated

### Compatibility Shim Example

```bash
# lib/compat/legacy_globals.sh
# Provides TOOL_CTX and legacy globals for tools not yet migrated

# When new system calls a tool, populate legacy globals from ToolConfig
populate_legacy_globals() {
    local -n config=$1

    # Old-style globals
    export TOOL="${config[tool_name]}"
    export TARGET="${config[target]}"
    # ... etc

    # TOOL_CTX for tools using newer-old style
    declare -gA TOOL_CTX
    TOOL_CTX[tool_name]="${config[tool_name]}"
    TOOL_CTX[target]="${config[target]}"
    # ... etc
}
```

### Migration Checklist Per Tool

- [ ] Tool merge.sh uses new hook interface
- [ ] Tool merge.sh receives deps (fs, log, backup) if using them
- [ ] No direct filesystem access (use fs module)
- [ ] No reliance on global TOOL_CTX
- [ ] Unit test exists with mocked dependencies
- [ ] Integration test verifies end-to-end

---

## Plan Maintenance

> **IMPORTANT FOR AGENTS**: This plan is a living document. The example code and interfaces
> in phase descriptions are *initial designs*, not specifications. When your implementation
> diverges from the plan (better patterns discovered, simpler approaches found, etc.),
> **update the plan to reflect reality**. Future agents will read this plan to understand
> the system - outdated examples cause confusion and wasted effort.

### How to Update This Plan

When working on this implementation:

1. **Before Starting a Phase**:
   - Update status table to 🟡 In Progress
   - Add start date
   - Note any blockers discovered

2. **During Phase Work**:
   - Check off deliverables as completed
   - Add notes about deviations from plan
   - Document any new requirements discovered

3. **After Completing a Phase**:
   - Update status to 🟢 Complete
   - Add completion date
   - Document lessons learned
   - Update next phase if needed based on learnings
   - **Review for drift**: Compare what you built to the plan's example code.
     If they differ significantly, either:
     - Add a note to the phase saying "example is outdated, see actual implementation"
     - Update the example code to match reality
     - Update downstream phases that reference the outdated APIs

4. **If Blocked**:
   - Update status to 🔵 Blocked
   - Document what's blocking
   - Add resolution steps

### Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-01-11 | Initial plan created | Claude |
| 2026-01-11 | Phase 1 complete: core modules (fs, log, backup, errors) with mock support and 70 unit tests | Claude |
| 2026-01-11 | Phase 2 complete: contracts module (LayerSpec, ToolConfig, MachineConfig, HookResult) with 187 total tests | Claude |
| 2026-01-11 | Phase 3 complete: config module (parser, validator, machine) with 294 total tests | Claude |
| 2026-01-11 | Phase 4 complete: resolver module (paths, repos, layers) with 410 total tests | Claude |
| 2026-01-11 | Phase 5 complete: executor module (registry, runner, 4 builtins) with 449 total tests | Claude |
| 2026-01-11 | Phase 6 complete: orchestrator module with 40 unit tests and 31 integration tests (520 total) | Claude |

### Open Questions

Track questions that need resolution:

1. Should we use JSON for tool.conf or stick with bash key=value?
   - **Decision**: TBD (for tool.conf file format)
   - **Trade-offs**: JSON = better structure, worse bash ergonomics
   - **Note**: For in-memory contracts, we chose indexed keys (`layer_0_name`) over JSON.
     This avoids jq dependency in core code and is more bash-native.

2. How to handle backward compat for external tool repos (STRIPE_DOTFILES)?
   - **Decision**: TBD
   - **Consideration**: External repos may have their own merge.sh scripts

3. Performance: Is fs abstraction overhead acceptable?
   - **Decision**: TBD - needs benchmarking
   - **Note**: 294 tests run in ~3 seconds, so mock overhead appears minimal

---

## Quick Reference

### Starting Fresh Session

For new agents/sessions picking up this work:

1. Read this entire plan document
2. Check phase status table for current state
3. Read completed phase documentation in `lib/*/README.md`
4. Read test files for completed modules to understand contracts
5. **Trust the code over the plan** - if example code in the plan differs from
   actual implementation, the implementation is correct (and update the plan!)
6. Continue from current phase

### Key Files to Understand Current State

```bash
# Check implementation progress (paths relative to lib/dotfiles-system/)
ls lib/dotfiles-system/lib/core/           # Phase 1 modules
ls lib/dotfiles-system/lib/contracts/      # Phase 2 contracts
ls lib/dotfiles-system/lib/config/         # Phase 3 config parsing
ls lib/dotfiles-system/lib/resolver/       # Phase 4 resolution
ls lib/dotfiles-system/lib/executor/       # Phase 5 execution

# Check test status
./lib/dotfiles-system/test/run_tests.sh    # Run all tests

# Check this plan
cat PLAN-modular-architecture.md | grep "^| Phase"  # Status summary
```

### Commands for Development

```bash
# Run specific test
./lib/dotfiles-system/test/run_tests.sh unit/core/test_fs.sh

# Run all unit tests
./lib/dotfiles-system/test/run_tests.sh unit/

# Run integration tests
./lib/dotfiles-system/test/run_tests.sh integration/

# Lint for unsafe writes (existing)
./scripts/lint-safe-writes.sh
```
