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
  apt-get update
  apt-get install -y jq mosh zsh

  # Eternal Terminal (requires PPA)
  if ! grep -qr "jgmath2000/et" /etc/apt/sources.list.d/ 2>/dev/null; then
    echo "==> Adding Eternal Terminal PPA..."
    add-apt-repository -y ppa:jgmath2000/et
    apt-get update
  fi
  echo "==> Installing Eternal Terminal..."
  apt-get install -y et

  # GitHub CLI
  echo "==> Installing GitHub CLI..."
  apt-get install -y gh

  # Starship prompt
  if ! command -v starship &>/dev/null; then
    echo "==> Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  # 1Password CLI
  if ! command -v op &>/dev/null; then
    echo "==> Installing 1Password CLI..."
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
      tee /etc/apt/sources.list.d/1password.list
    mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
      tee /etc/debsig/policies/AC2D62742012EA22/1password.pol > /dev/null
    mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22/
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
    apt-get update && apt-get install -y 1password-cli
  fi

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

  echo "==> Installing packages via Homebrew..."
  brew install mosh
  brew install jq
  brew install gh
  brew install MisterTea/et/et
  brew install --cask iterm2
  brew install --cask font-jetbrains-mono-nerd-font
  brew install terminal-notifier
  brew install starship
  brew install --cask 1password-cli

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

else
  echo "ERROR: Unsupported OS: $OS"
  exit 1
fi

# ── Shared config (both platforms) ───────────────────────────────────────────

# ── Oh My Zsh + plugins (both platforms) ──────────────────────────────────
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "==> Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

echo "==> Symlinking shared config files..."
symlink "$DOTFILES/git/gitconfig"            "$HOME/.gitconfig"
symlink "$DOTFILES/shell/aliases.sh"        "$HOME/.aliases"
symlink "$DOTFILES/zsh/zshrc"               "$HOME/.zshrc"
symlink "$DOTFILES/starship/starship.toml"  "$HOME/.config/starship.toml"
symlink "$DOTFILES/tmux/tmux.conf"          "$HOME/.tmux.conf"
symlink "$DOTFILES/claude/hooks/notify.sh"            "$HOME/.claude/hooks/notify.sh"
symlink "$DOTFILES/claude/hooks/ntfy-subscriber.sh"   "$HOME/.claude/hooks/ntfy-subscriber.sh"
symlink "$DOTFILES/claude/settings.json"              "$HOME/.claude/settings.json"
symlink "$DOTFILES/claude/statusline.sh"              "$HOME/.claude/statusline.sh"

# Cache secrets from 1Password
if command -v op &>/dev/null && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "==> Caching secrets from 1Password..."
  install -d -m 700 "$HOME/.config/dotfiles"
  (
    umask 077
    SECRETS_FILE="$HOME/.config/dotfiles/secrets.sh"
    : > "$SECRETS_FILE"

    NTFY_TOPIC_VAL="$(op read 'op://Dotfiles/ntfy-topic/credential' --no-newline 2>/dev/null)" && {
      printf 'export NTFY_TOPIC=%q\n' "$NTFY_TOPIC_VAL" >> "$SECRETS_FILE"
    } || echo "    WARNING: Failed to read NTFY_TOPIC from 1Password."

    OPENROUTER_API_KEY_VAL="$(op read 'op://Dotfiles/openrouter-api-key/credential' --no-newline 2>/dev/null)" && {
      printf 'export OPENROUTER_API_KEY=%q\n' "$OPENROUTER_API_KEY_VAL" >> "$SECRETS_FILE"
    } || echo "    WARNING: Failed to read OPENROUTER_API_KEY from 1Password."

    echo "    Secrets cached to ~/.config/dotfiles/secrets.sh"
  )
else
  echo "    NOTE: op CLI or OP_SERVICE_ACCOUNT_TOKEN missing. Skipping secret caching."
fi

# macOS-only: LaunchAgent for ntfy subscriber → native notifications
if [ "$OS" = "Darwin" ]; then
  symlink "$DOTFILES/claude/com.sanjeev.ntfy-subscriber.plist" \
    "$HOME/Library/LaunchAgents/com.sanjeev.ntfy-subscriber.plist"
  launchctl bootout gui/"$(id -u)" "$HOME/Library/LaunchAgents/com.sanjeev.ntfy-subscriber.plist" 2>/dev/null || true
  launchctl bootstrap gui/"$(id -u)" "$HOME/Library/LaunchAgents/com.sanjeev.ntfy-subscriber.plist"
fi

# ── Claude Code ───────────────────────────────────────────────────────────
echo "==> Installing/updating Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

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
command -v mosh-server &>/dev/null && echo "    mosh: $(mosh-server --version 2>&1 | head -1)"
command -v etserver &>/dev/null && echo "    ET:   $(etserver --version 2>&1 | head -1)"
command -v starship &>/dev/null && echo "    starship: $(starship --version 2>&1 | head -1)"
command -v claude &>/dev/null && echo "    claude: $(claude --version)"

if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo ""
  echo "    To enable ntfy notifications:"
  echo "    1. Run ./setup-op-token.sh"
  echo "    2. Re-run bootstrap.sh"
fi
