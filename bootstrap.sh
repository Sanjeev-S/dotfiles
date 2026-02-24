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
  apt-get install -y jq mosh

  # Eternal Terminal
  echo "==> Installing Eternal Terminal..."
  add-apt-repository -y ppa:jgmath2000/et
  apt-get update
  apt-get install -y et

  # Claude Code
  echo "==> Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash

  # Ensure ~/.local/bin is in PATH permanently.
  # Insert at top of .bashrc so it takes effect before any early-return guard
  # (e.g. "[ -z "$PS1" ] && return" which skips the rest for non-interactive shells).
  if ! grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' ~/.bashrc 2>/dev/null; then
    sed -i '1a export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc
  fi
  export PATH="$HOME/.local/bin:$PATH"

  # Symlink config files
  echo "==> Symlinking config files..."
  symlink "$DOTFILES/tmux/tmux.conf"          "$HOME/.tmux.conf"
  symlink "$DOTFILES/claude/hooks/notify.sh"  "$HOME/.claude/hooks/notify.sh"
  symlink "$DOTFILES/claude/settings.json"    "$HOME/.claude/settings.json"

# ── macOS ───────────────────────────────────────────────────────────────────
elif [ "$OS" = "Darwin" ]; then
  echo "==> Detected macOS — running Mac setup..."

  if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi

  echo "==> Installing mosh..."
  brew install mosh

  echo "==> Installing Eternal Terminal..."
  brew install MisterTea/et/et

  echo "==> Installing iTerm2..."
  brew install --cask iterm2

  # Symlink config files
  echo "==> Symlinking config files..."
  symlink "$DOTFILES/shell/aliases.sh"        "$HOME/.aliases"
  symlink "$DOTFILES/claude/hooks/notify.sh"  "$HOME/.claude/hooks/notify.sh"
  symlink "$DOTFILES/claude/settings.json"    "$HOME/.claude/settings.json"

  # Source aliases from .zshrc
  if ! grep -q 'source.*\.aliases' "$HOME/.zshrc" 2>/dev/null; then
    echo '[ -f ~/.aliases ] && source ~/.aliases' >> "$HOME/.zshrc"
    echo "    Added alias sourcing to .zshrc"
  fi

else
  echo "ERROR: Unsupported OS: $OS"
  exit 1
fi

# ── Shared ──────────────────────────────────────────────────────────────────
echo ""
echo "==> All done!"

if [ "$OS" = "Linux" ]; then
  NTFY_TOPIC="sanjeev-claude-99e0b7e3e3ae"
  echo ""
  echo "    Versions:"
  echo "    mosh:   $(mosh-server --version 2>&1 | head -1)"
  echo "    ET:     $(etserver --version 2>&1 | head -1)"
  echo "    claude: $(claude --version)"
  echo ""
  echo "    Next steps:"
  echo "    1. Run 'claude' to authenticate via OAuth"
  echo "    2. Subscribe to ntfy topic: ${NTFY_TOPIC}"
  echo "       https://ntfy.sh/${NTFY_TOPIC}"
fi

if [ "$OS" = "Darwin" ]; then
  echo ""
  echo "    Versions:"
  echo "    mosh: $(mosh-server --version 2>&1 | head -1)"
  echo "    ET:   $(etserver --version 2>&1 | head -1)"
fi
