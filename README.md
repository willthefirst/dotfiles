# Dotfiles

My personal dotfiles using a layered configuration system. Supports multiple machine profiles with optional work-specific overlays.

## Quick Start

### New Machine Setup

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/willthefirst/dotfiles.git ~/.dotfiles

# Run setup for your machine type
cd ~/.dotfiles
./install.sh personal-mac
```

### Stripe Machine Setup

For Stripe machines, you also need the work dotfiles:

```bash
# 1. Clone personal dotfiles
git clone --recurse-submodules https://github.com/willthefirst/dotfiles.git ~/.dotfiles

# 2. Clone work dotfiles (requires Stripe GHE access)
git clone git@git.corp.stripe.com:willm/dotfiles-stripe.git ~/.dotfiles-stripe

# 3. Run setup
cd ~/.dotfiles
./install.sh stripe-mac
```

## Machine Profiles

| Profile | Description | Layers |
|---------|-------------|--------|
| `personal-mac` | Personal Mac | Base only |
| `stripe-mac` | Stripe Mac | Base + Stripe |
| `stripe-devbox` | Stripe devbox | Base + Stripe (no Ghostty) |

## What Gets Configured

| Tool | Strategy | Location |
|------|----------|----------|
| **Git** | Includes | `~/.gitconfig` includes layer configs |
| **Zsh** | Sources | `~/.zshrc` sources layer configs |
| **Neovim** | Symlinks | `~/.config/nvim/` with file-level overrides |
| **SSH** | Concat | `~/.ssh/config` concatenated from layers |
| **Ghostty** | Symlink | `~/.config/ghostty/` symlinked |

## Usage

```bash
# Install all tools for a profile
./install.sh stripe-mac

# Install only one tool
./install.sh stripe-mac --tool nvim

# Dry run (see what would happen)
./install.sh stripe-mac --dry-run

# List available profiles
./install.sh --list
```

## Structure

```
~/.dotfiles/
├── install.sh              # Main entry point
├── repos.conf              # External repo locations
├── machines/               # Machine profiles
│   ├── personal-mac.sh
│   ├── stripe-mac.sh
│   └── stripe-devbox.sh
├── tools/                  # Tool configs + merge hooks
│   ├── git/
│   ├── zsh/
│   ├── nvim/
│   ├── ssh/
│   └── ghostty/
├── configs/                # Actual config files (base layer)
│   ├── git/
│   ├── zsh/
│   ├── nvim/
│   ├── ssh/
│   └── ghostty/
└── lib/
    └── dotfiles-system/    # Framework (submodule)
```

## How Layering Works

Each tool can pull configs from multiple "layers" which are merged together:

```
Layer 1 (base):     ~/.dotfiles/configs/nvim/
Layer 2 (stripe):   ~/.dotfiles-stripe/nvim/
                              ↓
                    Merge Hook (tool-specific)
                              ↓
Output:             ~/.config/nvim/
```

**Example: Neovim**
- Base layer provides: init.lua, plugins/, config/
- Stripe layer provides: config/lazy.lua (override), plugins-work/ (additional)
- Result: Base config with Stripe's lazy.lua and work plugins added

## Adding a New Tool

1. Create config directory: `configs/<tool>/`
2. Create tool config: `tools/<tool>/tool.conf`
3. Add to machine profiles: `machines/*.sh`

**tools/mytool/tool.conf:**
```bash
layers_base="local:configs/mytool"
layers_stripe="STRIPE_DOTFILES:mytool"
target="${HOME}/.config/mytool"
merge_hook="builtin:symlink"
```

## Updating

```bash
# Pull latest dotfiles
cd ~/.dotfiles
git pull

# Update framework submodule
git submodule update --remote

# Re-run install
./install.sh stripe-mac
```

## Troubleshooting

**Submodule not found:**
```bash
git submodule update --init
```

**Work dotfiles not found:**
```bash
# Make sure ~/.dotfiles-stripe exists
git clone git@git.corp.stripe.com:willm/dotfiles-stripe.git ~/.dotfiles-stripe
```

**Permission denied on install.sh:**
```bash
chmod +x install.sh
```
