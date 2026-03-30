#!/usr/bin/env bash
set -euo pipefail

# Usage: bash rotate-op-token.sh
#   or:  bash <(curl -fsSL https://raw.githubusercontent.com/Sanjeev-S/dotfiles/main/rotate-op-token.sh)
#
# Rotates the 1Password service account token everywhere:
#   1. ~/.config/dotfiles/.env (sourced by shell)
#   2. ~/.config/chezmoi/chezmoi.toml (used by chezmoi templates)
#   3. Re-caches all downstream secrets via secrets-refresh

echo "Paste your 1Password service account token (input is hidden):"
read -rs TOKEN

if [ -z "$TOKEN" ]; then
  echo "ERROR: No token provided." >&2
  exit 1
fi

# Update .env
install -d -m 700 "$HOME/.config/dotfiles"
(
  umask 077
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$TOKEN" > "$HOME/.config/dotfiles/.env"
)
echo "==> Token saved to ~/.config/dotfiles/.env"

# Update chezmoi.toml
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
if [ -f "$CHEZMOI_CONFIG" ]; then
  sed -i.bak "s|^[[:space:]]*op_token = .*|    op_token = \"$TOKEN\"|" "$CHEZMOI_CONFIG"
  rm -f "$CHEZMOI_CONFIG.bak"
  echo "==> Token updated in $CHEZMOI_CONFIG"
else
  echo "    WARNING: $CHEZMOI_CONFIG not found. Run 'chezmoi init' first."
fi

# Refresh downstream secrets
export OP_SERVICE_ACCOUNT_TOKEN="$TOKEN"
if command -v secrets-refresh &>/dev/null; then
  secrets-refresh
else
  echo "    WARNING: secrets-refresh not found in PATH. Run 'chezmoi apply' first."
fi
