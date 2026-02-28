#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# ── Helper ──────────────────────────────────────────────────────────────────
symlink() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  echo "    $dst → $src"
}

OS="$(uname -s)"

# ── Linux (server) ──────────────────────────────────────────────────────────
if [ "$OS" = "Linux" ]; then
  echo "==> Detected Linux — running server setup..."

  # Prerequisites
  echo "==> Installing prerequisites..."
  apt-get install -y jq mosh zsh

  # Eternal Terminal
  echo "==> Installing Eternal Terminal..."
  add-apt-repository -y ppa:jgmath2000/et
  apt-get update
  apt-get upgrade -y

  apt-get install -y et

  # GitHub CLI
  if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    apt-get install -y gh
  fi

  # Claude Code (native install)
  echo "==> Installing/updating Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash

  # Starship prompt
  if ! command -v starship &>/dev/null; then
    echo "==> Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "==> Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  # Third-party zsh plugins
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

  # Set zsh as default shell
  if [ "$(basename "$SHELL")" != "zsh" ]; then
    echo "==> Setting zsh as default shell..."
    chsh -s "$(which zsh)"
  fi

# ── macOS ───────────────────────────────────────────────────────────────────
elif [ "$OS" = "Darwin" ]; then
  echo "==> Detected macOS — running Mac setup..."

  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi

  echo "==> Updating packages..."
  brew update
  brew upgrade

  echo "==> Installing mosh..."
  brew install mosh

  echo "==> Installing jq..."
  brew install jq

  echo "==> Installing GitHub CLI..."
  brew install gh

  echo "==> Installing Eternal Terminal..."
  brew install MisterTea/et/et

  echo "==> Installing iTerm2..."
  brew install --cask iterm2

  echo "==> Installing Nerd Font..."
  brew install --cask font-jetbrains-mono-nerd-font

  echo "==> Setting iTerm2 font to JetBrains Mono Nerd Font..."
  ITERM_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  if [ ! -f "$ITERM_PLIST" ]; then
    echo "    Launching iTerm2 briefly to generate preferences..."
    open -a iTerm2
    sleep 3
    osascript -e 'quit app "iTerm2"'
    sleep 1
  fi
  /usr/libexec/PlistBuddy -c "Set ':New Bookmarks:0:Normal Font' 'JetBrainsMonoNF-Regular 13'" \
    "$ITERM_PLIST" 2>/dev/null || true

  echo "==> Configuring iTerm2 tmux integration (open in tabs, not windows)..."
  defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2

  echo "==> Installing Starship prompt..."
  brew install starship

  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "==> Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  # Third-party zsh plugins
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

else
  echo "ERROR: Unsupported OS: $OS"
  exit 1
fi

# ── Shared config (both platforms) ───────────────────────────────────────────
echo "==> Symlinking shared config files..."
symlink "$DOTFILES/git/gitconfig"            "$HOME/.gitconfig"
symlink "$DOTFILES/shell/aliases.sh"        "$HOME/.aliases"
symlink "$DOTFILES/zsh/zshrc"               "$HOME/.zshrc"
symlink "$DOTFILES/starship/starship.toml"  "$HOME/.config/starship.toml"
symlink "$DOTFILES/tmux/tmux.conf"          "$HOME/.tmux.conf"
symlink "$DOTFILES/claude/hooks/notify.sh"  "$HOME/.claude/hooks/notify.sh"
symlink "$DOTFILES/claude/settings.json"    "$HOME/.claude/settings.json"
symlink "$DOTFILES/claude/statusline.sh"   "$HOME/.claude/statusline.sh"

# ── Claude Code plugins ──────────────────────────────────────────────────────
if command -v claude &>/dev/null; then
  echo "==> Installing/updating Claude Code plugins..."
  claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null || true
  claude plugin marketplace add EveryInc/compound-engineering-plugin 2>/dev/null || true
  claude plugin install superpowers@superpowers-marketplace
  claude plugin install compound-engineering@every-marketplace
else
  echo "    Skipping Claude plugins (claude not found in PATH)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "==> All done!"
echo ""
echo "    Versions:"
echo "    mosh: $(mosh-server --version 2>&1 | head -1)"
echo "    ET:   $(etserver --version 2>&1 | head -1)"

echo "    starship: $(starship --version 2>&1 | head -1)"

if [ "$OS" = "Linux" ]; then
  NTFY_TOPIC="sanjeev-claude-99e0b7e3e3ae"
  echo "    claude: $(claude --version)"
  echo ""
  echo "    Next steps:"
  echo "    1. Run 'claude' to authenticate via OAuth"
  echo "    2. Subscribe to ntfy topic: ${NTFY_TOPIC}"
  echo "       https://ntfy.sh/${NTFY_TOPIC}"
fi
