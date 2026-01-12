# JSON Configuration Migration Plan

> **Purpose**: Migrate all configuration files from key=value/bash format to JSON for better structure, validation, and tooling support.

> **Status**: 🟢 Complete

> **Last Updated**: 2026-01-11

---

## Table of Contents

1. [Overview](#overview)
2. [Configuration Files to Migrate](#configuration-files-to-migrate)
3. [Target JSON Formats](#target-json-formats)
4. [Implementation Phases](#implementation-phases)
5. [Phase Details](#phase-details)
6. [Migration Strategy](#migration-strategy)
7. [Testing Strategy](#testing-strategy)

---

## Overview

### Goals

1. **Better Structure**: Proper arrays and objects instead of naming conventions
2. **Schema Validation**: JSON Schema for IDE support and validation
3. **Tooling Support**: JSON is widely supported by editors, linters, etc.
4. **Cleaner Parsing**: Use `jq` instead of regex-based parsing
5. **Consistency**: All configs use the same format

### Non-Goals

- Changing the functionality of the dotfiles system
- Changing the merge/install hook interface
- Breaking existing tool functionality during migration

### Success Criteria

- [x] All tool.conf files migrated to tool.json
- [x] repos.conf migrated to repos.json
- [x] All machine profiles migrated to JSON
- [x] JSON Schemas provide validation and IDE completion
- [x] All parsers support JSON natively (legacy parsers removed)
- [x] Migration scripts handle all existing configs
- [x] All tests updated and passing (399 tests)
- [x] Documentation updated

---

## Configuration Files to Migrate

| File Type | Current Format | Target Format | Count |
|-----------|----------------|---------------|-------|
| Tool configs | `tools/*/tool.conf` | `tools/*/tool.json` | 8 files |
| External repos | `repos.conf` | `repos.json` | 1 file |
| Machine profiles | `machines/*.sh` | `machines/*.json` | 3 files |

---

## Target JSON Formats

### 1. Tool Configuration (tool.json)

**Current (tool.conf)**:
```bash
# Layer sources
layers_base="local:configs/git"
layers_stripe="STRIPE_DOTFILES:git"

target="${HOME}/.gitconfig"
install_hook="./install.sh"
merge_hook="./merge.sh"
```

**Target (tool.json)**:
```json
{
  "$schema": "../../lib/dotfiles-system/schemas/tool.schema.json",
  "target": "~/.gitconfig",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" },
    { "name": "stripe", "source": "STRIPE_DOTFILES", "path": "git" }
  ],
  "install_hook": "./install.sh",
  "merge_hook": "./merge.sh"
}
```

### 2. External Repositories (repos.json)

**Current (repos.conf)**:
```bash
# External repository definitions
STRIPE_DOTFILES="git@git.corp.stripe.com:willm/dotfiles-stripe.git|${HOME}/.dotfiles-stripe"
```

**Target (repos.json)**:
```json
{
  "$schema": "lib/dotfiles-system/schemas/repos.schema.json",
  "repositories": [
    {
      "name": "STRIPE_DOTFILES",
      "url": "git@git.corp.stripe.com:willm/dotfiles-stripe.git",
      "path": "~/.dotfiles-stripe"
    }
  ]
}
```

### 3. Machine Profiles (machines/*.json)

**Current (machines/stripe-mac.sh)**:
```bash
TOOLS=(
    git
    zsh
    nvim
    ssh
)

git_layers=(base stripe)
zsh_layers=(base stripe)
nvim_layers=(base stripe)
ssh_layers=(base stripe)
```

**Target (machines/stripe-mac.json)**:
```json
{
  "$schema": "../lib/dotfiles-system/schemas/machine.schema.json",
  "name": "stripe-mac",
  "description": "Stripe Mac configuration - base + stripe layers",
  "tools": {
    "git": ["base", "stripe"],
    "zsh": ["base", "stripe"],
    "nvim": ["base", "stripe"],
    "ssh": ["base", "stripe"],
    "ghostty": ["base"],
    "karabiner": ["base"],
    "claude": ["base"],
    "vscode": ["base", "stripe"]
  }
}
```

---

## Implementation Phases

| Phase | Name | Description | Dependencies |
|-------|------|-------------|--------------|
| 1 | JSON Schemas | Define schemas for all config types | None |
| 2 | Tool Config Parser | Add JSON parsing for tool.json | Phase 1 |
| 3 | Repos Parser | Add JSON parsing for repos.json | Phase 1 |
| 4 | Machine Parser | Add JSON parsing for machine profiles | Phase 1 |
| 5 | Migration Scripts | Scripts to convert all config files | Phases 2-4 |
| 6 | Migrate All Configs | Convert all files to JSON | Phase 5 |
| 7 | Cleanup | Remove legacy parsers, update docs | Phase 6 |

### Phase Status Tracking

| Phase | Status | Started | Completed | Notes |
|-------|--------|---------|-----------|-------|
| 1 | 🟢 Complete | 2026-01-11 | 2026-01-11 | All schemas created |
| 2 | 🟢 Complete | 2026-01-11 | 2026-01-11 | JSON parser + unit/integration tests |
| 3 | 🟢 Complete | 2026-01-11 | 2026-01-11 | repos.json parser + unit/integration tests |
| 4 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Machine JSON parser + unit/integration tests |
| 5 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Migration script + unit/integration tests |
| 6 | 🟢 Complete | 2026-01-11 | 2026-01-11 | All configs migrated to JSON |
| 7 | 🟢 Complete | 2026-01-11 | 2026-01-11 | Legacy files and parsers removed, docs updated |

Status key: 🔴 Not Started | 🟡 In Progress | 🟢 Complete | 🔵 Blocked

---

## Phase Details

### Phase 1: JSON Schemas

**Goal**: Define and document JSON schemas for all configuration types.

**Files to Create**:

#### `lib/dotfiles-system/schemas/tool.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "tool.schema.json",
  "title": "Tool Configuration",
  "description": "Configuration for a dotfiles tool",
  "type": "object",
  "required": ["target", "merge_hook", "layers"],
  "properties": {
    "$schema": { "type": "string" },
    "target": {
      "type": "string",
      "description": "Target path for installation (~ expands to home)"
    },
    "layers": {
      "type": "array",
      "description": "Configuration layers in priority order (first = lowest)",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["name", "source", "path"],
        "properties": {
          "name": {
            "type": "string",
            "pattern": "^[a-z][a-z0-9_]*$"
          },
          "source": {
            "type": "string",
            "pattern": "^(local|[A-Z][A-Z0-9_]*)$"
          },
          "path": { "type": "string" }
        }
      }
    },
    "merge_hook": {
      "type": "string",
      "description": "Hook to merge layers (builtin:* or script path)"
    },
    "install_hook": {
      "type": "string",
      "description": "Optional hook to install dependencies"
    },
    "env": {
      "type": "object",
      "description": "Environment variables for hooks",
      "additionalProperties": { "type": "string" }
    }
  }
}
```

#### `lib/dotfiles-system/schemas/repos.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "repos.schema.json",
  "title": "External Repositories",
  "description": "External repository definitions for dotfiles",
  "type": "object",
  "required": ["repositories"],
  "properties": {
    "$schema": { "type": "string" },
    "repositories": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "url", "path"],
        "properties": {
          "name": {
            "type": "string",
            "pattern": "^[A-Z][A-Z0-9_]*$",
            "description": "Repository identifier (e.g., STRIPE_DOTFILES)"
          },
          "url": {
            "type": "string",
            "description": "Git clone URL"
          },
          "path": {
            "type": "string",
            "description": "Local clone path (~ expands to home)"
          }
        }
      }
    }
  }
}
```

#### `lib/dotfiles-system/schemas/machine.schema.json`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "machine.schema.json",
  "title": "Machine Profile",
  "description": "Machine-specific tool and layer configuration",
  "type": "object",
  "required": ["name", "tools"],
  "properties": {
    "$schema": { "type": "string" },
    "name": {
      "type": "string",
      "description": "Profile identifier (e.g., personal-mac)"
    },
    "description": {
      "type": "string",
      "description": "Human-readable description"
    },
    "tools": {
      "type": "object",
      "description": "Tool name -> layers array mapping",
      "additionalProperties": {
        "type": "array",
        "items": { "type": "string" },
        "minItems": 1,
        "description": "Layer names to use for this tool"
      }
    }
  }
}
```

**Deliverables**:
- [x] `lib/dotfiles-system/schemas/tool.schema.json`
- [x] `lib/dotfiles-system/schemas/repos.schema.json`
- [x] `lib/dotfiles-system/schemas/machine.schema.json`
- [x] `lib/dotfiles-system/schemas/README.md`

---

### Phase 2: Tool Config Parser

**Goal**: Update `config/parser.sh` to parse tool.json files.

**Changes to `lib/config/parser.sh`**:

```bash
# Parse tool configuration (JSON or legacy conf)
# Usage: config_parse_tool "/path/to/tools/git" result
config_parse_tool() {
    local tool_dir="$1"
    local -n __cpt_result=$2

    # Try JSON first
    if _config_parse_tool_json "$tool_dir" __cpt_result; then
        return $E_OK
    fi

    # Fall back to legacy key=value format
    config_parse_tool_conf "$tool_dir" __cpt_result
}

# Parse tool.json file
_config_parse_tool_json() {
    local tool_dir="$1"
    local -n __cptj_result=$2
    local json_path="${tool_dir}/tool.json"

    if ! fs_is_file "$json_path"; then
        return $E_NOT_FOUND
    fi

    local content
    content=$(fs_read "$json_path") || return $E_NOT_FOUND

    # Validate JSON
    if ! echo "$content" | jq . &>/dev/null; then
        echo "config/parser: invalid JSON in $json_path" >&2
        return $E_VALIDATION
    fi

    # Extract fields
    __cptj_result[target]=$(echo "$content" | jq -r '.target // empty')
    __cptj_result[merge_hook]=$(echo "$content" | jq -r '.merge_hook // empty')
    __cptj_result[install_hook]=$(echo "$content" | jq -r '.install_hook // empty')

    # Extract layers as layers_<name>=source:path
    local i=0
    while true; do
        local name source path
        name=$(echo "$content" | jq -r ".layers[$i].name // empty")
        [[ -z "$name" ]] && break
        source=$(echo "$content" | jq -r ".layers[$i].source")
        path=$(echo "$content" | jq -r ".layers[$i].path")
        __cptj_result["layers_${name}"]="${source}:${path}"
        ((i++))
    done

    return $E_OK
}
```

**Deliverables**:
- [x] `_config_parse_tool_json()` function
- [x] Update `config_parse_tool()` to try JSON first
- [x] Unit tests for JSON parsing
- [x] Integration tests with real JSON files

---

### Phase 3: Repos Parser

**Goal**: Update `resolver/repos.sh` to parse repos.json.

**Changes to `lib/resolver/repos.sh`**:

```bash
# Initialize from repos.json or legacy repos.conf
repos_init() {
    local dotfiles_dir="$1"
    _repos_dotfiles_dir="$dotfiles_dir"
    _repos_urls=()
    _repos_paths=()

    # Try JSON first
    if _repos_init_json "$dotfiles_dir"; then
        return $E_OK
    fi

    # Fall back to legacy conf
    _repos_init_conf "$dotfiles_dir"
}

_repos_init_json() {
    local dotfiles_dir="$1"
    local json_path="$dotfiles_dir/repos.json"

    if ! fs_exists "$json_path"; then
        return $E_NOT_FOUND
    fi

    local content
    content=$(fs_read "$json_path") || return $E_NOT_FOUND

    # Parse repositories array
    local i=0
    while true; do
        local name url path
        name=$(echo "$content" | jq -r ".repositories[$i].name // empty")
        [[ -z "$name" ]] && break
        url=$(echo "$content" | jq -r ".repositories[$i].url")
        path=$(echo "$content" | jq -r ".repositories[$i].path")
        # Expand ~ to $HOME
        path="${path/#\~/$HOME}"
        _repos_urls["$name"]="$url"
        _repos_paths["$name"]="$path"
        ((i++))
    done

    return $E_OK
}
```

**Deliverables**:
- [x] `_repos_init_json()` function
- [x] Update `repos_init()` to try JSON first
- [x] Unit tests for JSON parsing
- [x] Integration tests with real repos.json files

---

### Phase 4: Machine Parser

**Goal**: Update `config/machine.sh` to parse machine JSON profiles.

**Changes to `lib/config/machine.sh`**:

```bash
# Load machine profile (JSON or legacy bash)
machine_load_profile() {
    local profile_path="$1"
    local -n __mlp_config=$2

    # Determine format from extension
    if [[ "$profile_path" == *.json ]]; then
        _machine_load_json "$profile_path" __mlp_config
    else
        _machine_load_bash "$profile_path" __mlp_config
    fi
}

_machine_load_json() {
    local json_path="$1"
    local -n __mlj_config=$2

    if ! fs_is_file "$json_path"; then
        return $E_NOT_FOUND
    fi

    local content
    content=$(fs_read "$json_path") || return $E_NOT_FOUND

    # Extract profile name
    local name
    name=$(echo "$content" | jq -r '.name')
    machine_config_new __mlj_config "$name"

    # Extract tools and their layers
    local tools
    tools=$(echo "$content" | jq -r '.tools | keys[]')
    for tool in $tools; do
        machine_config_add_tool __mlj_config "$tool"
        local layers
        layers=$(echo "$content" | jq -r ".tools[\"$tool\"] | join(\":\")")
        machine_config_set_tool_layers __mlj_config "$tool" "$layers"
    done

    machine_config_validate __mlj_config
}
```

**Deliverables**:
- [x] `_machine_load_json()` function
- [x] Support both .json and .sh extensions
- [x] Unit tests for JSON machine profiles
- [x] Integration tests for JSON machine profiles

---

### Phase 5: Migration Scripts

**Goal**: Create scripts to convert all existing configs to JSON.

**Files to Create**:

#### `scripts/migrate-to-json.sh`

```bash
#!/usr/bin/env bash
# Migrate all configuration files to JSON format
#
# Usage:
#   ./scripts/migrate-to-json.sh --dry-run    # Preview changes
#   ./scripts/migrate-to-json.sh              # Perform migration
#   ./scripts/migrate-to-json.sh --tool git   # Single tool only
#   ./scripts/migrate-to-json.sh --repos      # repos.conf only
#   ./scripts/migrate-to-json.sh --machines   # machines/*.sh only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${SCRIPT_DIR}/.."

migrate_tool_conf() {
    local tool_dir="$1"
    local dry_run="${2:-false}"
    # ... (conversion logic)
}

migrate_repos_conf() {
    local dry_run="${1:-false}"
    # ... (conversion logic)
}

migrate_machine_profile() {
    local profile_path="$1"
    local dry_run="${2:-false}"
    # ... (conversion logic)
}

# Main
dry_run=false
target="all"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --tool) target="tool:$2"; shift 2 ;;
        --repos) target="repos"; shift ;;
        --machines) target="machines"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

case "$target" in
    all)
        for tool in tools/*/; do
            migrate_tool_conf "$tool" "$dry_run"
        done
        migrate_repos_conf "$dry_run"
        for profile in machines/*.sh; do
            migrate_machine_profile "$profile" "$dry_run"
        done
        ;;
    tool:*)
        migrate_tool_conf "tools/${target#tool:}" "$dry_run"
        ;;
    repos)
        migrate_repos_conf "$dry_run"
        ;;
    machines)
        for profile in machines/*.sh; do
            migrate_machine_profile "$profile" "$dry_run"
        done
        ;;
esac
```

**Deliverables**:
- [x] `scripts/migrate-to-json.sh`
- [x] `--dry-run` mode for preview
- [x] Support for migrating individual components (`--tool`, `--repos`, `--machines`)
- [x] Validation that generated JSON matches schema
- [x] Unit tests (`test/unit/scripts/test_migrate_to_json.sh`)
- [x] Integration tests (`test/integration/test_migrate_to_json.sh`)

---

### Phase 6: Migrate All Configs

**Goal**: Convert all existing configuration files to JSON.

**Migration Order**:

1. **repos.conf → repos.json** (single file, low risk)
2. **tools/*/tool.conf → tool.json** (one at a time, test each)
3. **machines/*.sh → machines/*.json** (test profiles)

**Checklist**:

**repos.json**:
- [x] Generate repos.json from repos.conf
- [x] Verify repos_init loads correctly
- [x] Test external repo cloning

**Tool Configs** (tool.json):
- [x] claude
- [x] ghostty
- [x] git
- [x] karabiner
- [x] nvim
- [x] ssh
- [x] vscode
- [x] zsh

**Machine Profiles**:
- [x] personal-mac.json
- [x] stripe-mac.json
- [x] stripe-devbox.json

**Verification**:
- [x] `./install.sh personal-mac --dry-run` works
- [x] `./install.sh stripe-mac --dry-run` works (requires external repo)
- [x] Real install of single tool works

---

### Phase 7: Cleanup

**Goal**: Remove legacy parsers and update documentation.

**Tasks**:

1. Remove legacy parser functions:
   - [x] `config_parse_tool_conf()` - removed
   - [x] `config_parse_line()` - removed
   - [x] `config_expand_vars()` - removed
   - [x] `_repos_init_conf()` - removed
   - [x] `_machine_load_bash()` - removed
   - [x] `config_parse_bash_array()` - removed

2. Delete legacy config files:
   - [x] All `tools/*/tool.conf` (8 files)
   - [x] `repos.conf`
   - [x] `machines/*.sh` (3 files)

3. Update documentation:
   - [x] README.md - updated structure and examples
   - [x] lib/dotfiles-system/README.md - updated config examples
   - [x] This plan (mark complete)

4. Update install.sh:
   - [x] Change profile argument to use .json extension
   - [x] Update `--list` to show .json profiles
   - [x] Update `_ensure_external_repos_for_profile()` for JSON

5. Update orchestrator.sh:
   - [x] Change profile extension resolution from .sh to .json

6. Update tests:
   - [x] test_orchestrator.sh - updated to use JSON configs
   - [x] test_parser.sh - removed legacy conf tests
   - [x] test_machine.sh - removed legacy bash tests

**Deliverables**:
- [x] Legacy parsers removed
- [x] All .conf and .sh configs deleted
- [x] Documentation updated
- [x] All 399 tests passing

---

## Migration Strategy

### Backward Compatibility

During Phases 2-6, the system supports both formats:

1. **JSON preferred**: Parsers try .json first
2. **Fallback**: If no JSON, uses legacy format
3. **Per-file migration**: Can migrate configs one at a time
4. **Rollback**: Keep legacy files until Phase 7

### Rollback Plan

If issues arise:
1. Legacy files kept until Phase 7
2. Parsers fall back to legacy if JSON fails
3. Git history preserves all old configs

### jq Dependency

- Required for JSON parsing
- Add preflight check in install.sh
- Provide helpful error if missing:
  ```
  Error: jq is required for JSON configuration parsing
  Install via: brew install jq (macOS) or apt install jq (Linux)
  ```

---

## Testing Strategy

### Unit Tests

```bash
# test/unit/config/test_parser_json.sh
test_parse_tool_json() { ... }
test_json_preferred_over_conf() { ... }

# test/unit/resolver/test_repos_json.sh
test_repos_init_json() { ... }
test_json_preferred_over_conf() { ... }

# test/unit/config/test_machine_json.sh
test_machine_load_json() { ... }
```

### Integration Tests

```bash
# test/integration/test_json_configs.sh
test_full_install_with_json_configs() {
    # Create all JSON configs
    # Run full install
    # Verify everything works
}
```

### Manual Verification

Before Phase 7 cleanup:
1. Run `./install.sh personal-mac` (full install)
2. Verify all tools configured correctly
3. Test on fresh machine if possible

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-01-11 | Initial plan created | Claude |
| 2026-01-11 | Phase 1 complete: JSON schemas created | Claude |
| 2026-01-11 | Phase 2 complete: Tool config JSON parser with unit/integration tests | Claude |
| 2026-01-11 | Phase 3 complete: Repos JSON parser with unit/integration tests | Claude |
| 2026-01-11 | Phase 4 complete: Machine JSON parser with unit/integration tests | Claude |
| 2026-01-11 | Phase 5 complete: Migration script with unit/integration tests | Claude |
| 2026-01-11 | Phase 6 complete: All config files migrated to JSON | Claude |
| 2026-01-11 | Phase 7 complete: Legacy files/parsers removed, docs/tests updated, migration complete | Claude |

---

## Open Questions

1. **Profile naming**: Should `./install.sh stripe-mac` auto-resolve to `machines/stripe-mac.json`?
   - **Recommendation**: Yes, for backward compatibility

2. **Comments in JSON**: How to preserve documentation from .sh/.conf files?
   - **Recommendation**: Use `"description"` fields in schemas

3. **Environment variables**: Support `${HOME}` in JSON or only `~`?
   - **Recommendation**: Only `~`, expand at parse time (simpler JSON)

4. **Layer order significance**: Document clearly in schema?
   - **Recommendation**: Yes, first layer = lowest priority (base)
