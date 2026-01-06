# =============================================================================
# .zshrc - Base Shell Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Oh My Zsh Setup
# -----------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"

if [[ ! -d "$ZSH" ]]; then
    echo "Warning: Oh My Zsh not found at $ZSH"
    echo "Install: sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
else
    ZSH_THEME="robbyrussell"

    # Plugins - add wisely, as too many plugins slow down shell startup
    plugins=(git)

    source $ZSH/oh-my-zsh.sh
fi

# -----------------------------------------------------------------------------
# Shell Tools
# -----------------------------------------------------------------------------

# Zoxide - smarter cd command
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# Pure theme (if installed via Homebrew)
if command -v brew &> /dev/null; then
    brew_prefix="$(brew --prefix)"
    if [[ -d "$brew_prefix/share/zsh/site-functions" ]]; then
        fpath+=("$brew_prefix/share/zsh/site-functions")
        autoload -U promptinit; promptinit
        if (( $+functions[prompt_pure_setup] )); then
            prompt pure
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Completions
# -----------------------------------------------------------------------------
autoload -Uz compinit; compinit
autoload -Uz bashcompinit; bashcompinit

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
export EDITOR='nvim'
export LANG=en_US.UTF-8

# -----------------------------------------------------------------------------
# PATH
# -----------------------------------------------------------------------------
# Add RVM to PATH for scripting (if installed)
[[ -d "$HOME/.rvm/bin" ]] && export PATH="$PATH:$HOME/.rvm/bin"

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
alias ll='ls -la'
alias vim='nvim'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
# Add custom functions here

