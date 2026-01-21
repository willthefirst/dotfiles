---
description: Save Claude settings (permissions, model, commands) to dotfiles
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# Task: Save Claude Settings to Dotfiles

Save the current Claude Code session's permissions, settings, or commands to the user's layered dotfiles system for persistence.

## Architecture Overview

The user has a two-layer dotfiles system:
- **Personal (base)**: `~/.dotfiles/configs/claude/` - personal settings, synced everywhere
- **Stripe (work)**: `~/.dotfiles-stripe/claude/` - work-specific overrides (may not exist yet)

Current live config is symlinked from: `~/.claude/settings.json` → `~/.dotfiles/configs/claude/settings.json`

Machine profile at `~/.dotfiles/machines/stripe-mac.json` controls which layers are active.

## Current State

- Live settings: !`cat ~/.claude/settings.json 2>/dev/null || echo "No settings file"`
- Personal dotfiles settings: !`cat ~/.dotfiles/configs/claude/settings.json 2>/dev/null || echo "No personal settings"`
- Stripe dotfiles settings: !`cat ~/.dotfiles-stripe/claude/settings.json 2>/dev/null || echo "No stripe settings (layer not created)"`
- Personal commands: !`ls ~/.dotfiles/configs/claude/commands/ 2>/dev/null || echo "No commands"`
- Stripe commands: !`ls ~/.dotfiles-stripe/claude/commands/ 2>/dev/null || echo "No stripe commands"`

## Step 1: Determine What to Save

Ask the user what they want to save. Options include:
1. **Permissions** - The allow/deny rules for tools (most common)
2. **Model preference** - Which Claude model to use
3. **A new command** - Create a new slash command
4. **All current settings** - Full settings.json

Use AskUserQuestion to clarify if not obvious from context.

## Step 2: Determine Which Layer

Ask the user which layer to save to:

| Layer | Location | Use Case |
|-------|----------|----------|
| **Personal** | `~/.dotfiles/configs/claude/` | Settings you want everywhere (personal machines, any context) |
| **Stripe** | `~/.dotfiles-stripe/claude/` | Work-specific settings (Stripe MCP tools, work permissions) |

Guidelines for the user:
- **Personal**: General dev tools (git, npm, python, docker, etc.)
- **Stripe**: Stripe-specific tools (mcp__toolshed__*, mcp__sourcegraph__*, work-specific commands)

If the Stripe layer doesn't exist yet and user selects it, you'll need to:
1. Create `~/.dotfiles-stripe/claude/` directory
2. Create the settings.json or commands/ as needed
3. Update `~/.dotfiles/machines/stripe-mac.json` to include `"claude": ["base", "stripe"]`
4. Update `~/.dotfiles/tools/claude/tool.json` to add the stripe layer definition

## Step 3: Perform the Modification

### For Permissions

If saving to the **same layer** as current settings:
- Edit the existing settings.json to add/modify permissions

If saving to a **new/different layer**:
- For Stripe layer (if it doesn't exist):
  1. Create `~/.dotfiles-stripe/claude/settings.json` with just the work-specific permissions
  2. Add to `~/.dotfiles/tools/claude/tool.json`:
     ```json
     { "name": "stripe", "source": "env", "env": "STRIPE_DOTFILES", "path": "claude" }
     ```
  3. Update `~/.dotfiles/machines/stripe-mac.json`: change `"claude": ["base"]` to `"claude": ["base", "stripe"]`

### For Commands

- Create the `.md` file in the appropriate `commands/` directory
- Follow the format of existing commands (YAML frontmatter with description and allowed-tools)

### For Model/Full Settings

- Edit the appropriate settings.json file

## Step 4: Validate Changes

After making changes:
1. Run `~/.dotfiles/install.sh stripe-mac --tool claude --dry-run` to preview
2. If looks good, run `~/.dotfiles/install.sh stripe-mac --tool claude` to apply
3. Verify symlinks are correct with `ls -la ~/.claude/`

## Step 5: Commit and Push

For each modified repository, ask the user if they want to commit and push:

### Personal dotfiles (~/.dotfiles)
```bash
cd ~/.dotfiles
git status
git diff
# If user approves:
git add -A
git commit -m "claude: <description of change>"
git push
```

### Stripe dotfiles (~/.dotfiles-stripe)
```bash
cd ~/.dotfiles-stripe
git status
git diff
# If user approves:
git add -A
git commit -m "claude: <description of change>"
git push
```

Ask separately for each repo - user may want to commit one but not the other.

## Step 6: Error Handling and Self-Improvement

If any errors occur during this process:
1. Note the error and what caused it
2. Attempt to fix it if possible
3. At the end of the session, if there were errors that required manual intervention or workarounds, propose an update to THIS command file (`~/.dotfiles/configs/claude/commands/save-dotfiles.md`) to handle that case better next time

Example self-improvement proposal:
```
I encountered an issue where [X]. To handle this better next time, I suggest adding the following to the save-dotfiles command:

[Proposed addition to the command file]

Would you like me to update the command now?
```

## Common Scenarios

### "Save my current permissions"
1. Read current live permissions from `~/.claude/settings.json`
2. Compare with what's in dotfiles
3. Ask which new permissions to save and to which layer
4. Update the appropriate settings.json
5. Offer to commit/push

### "Add Stripe MCP tools to my allowed permissions"
1. These should go in Stripe layer
2. Create Stripe claude layer if needed
3. Add permissions like `mcp__toolshed__*`, `mcp__sourcegraph__*`
4. Update machine profile and tool.json
5. Re-run install.sh
6. Offer to commit/push

### "Create a new command"
1. Ask for command name, description, and what it should do
2. Ask which layer (personal commands vs work commands)
3. Create the .md file with proper frontmatter
4. Symlinks should auto-update if using same commands/ dir
5. Offer to commit/push

## Important Notes

- The live `~/.claude/settings.json` is a **symlink** - edits go directly to the dotfiles repo
- After creating a new Stripe layer, must run `install.sh` to update symlinks
- The merge.sh uses "last layer wins" - Stripe layer completely overrides base for settings.json
- For additive permissions, you may want to keep base permissions broad and stripe-specific ones in stripe layer
- Always verify changes with `--dry-run` first
