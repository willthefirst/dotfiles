# machines/stripe-mac.sh
# Stripe Mac configuration - base + stripe layers

TOOLS=(
    git
    zsh
    nvim
    ssh
    ghostty
    karabiner
    claude
)

# Layer assignments (base + stripe for work machine)
git_layers=(base stripe)
zsh_layers=(base stripe)
nvim_layers=(base stripe)
ssh_layers=(base stripe)
ghostty_layers=(base)   # No stripe-specific ghostty config
karabiner_layers=(base) # No stripe-specific karabiner config
claude_layers=(base)    # Same Claude config everywhere
