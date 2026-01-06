# machines/stripe-devbox.sh
# Stripe devbox configuration - base + stripe layers
# Note: ghostty not applicable on devbox (no GUI)

TOOLS=(
    git
    zsh
    nvim
    ssh
)

# Layer assignments
git_layers=(base stripe)
zsh_layers=(base stripe)
nvim_layers=(base stripe)
ssh_layers=(base stripe)
