#!/usr/bin/env bash
set -euo pipefail

# Prompts for the 1Password service account token and saves it to ~/.config/dotfiles/.env
# Run once per machine. The token is never echoed or logged.

ENV_FILE="$HOME/.config/dotfiles/.env"

install -d -m 700 "$HOME/.config/dotfiles"

echo "Paste your 1Password service account token (input is hidden):"
read -rs TOKEN

if [ -z "$TOKEN" ]; then
  echo "ERROR: No token provided." >&2
  exit 1
fi

(
  umask 077
  printf 'export OP_SERVICE_ACCOUNT_TOKEN=%q\n' "$TOKEN" > "$ENV_FILE"
)

echo "Token saved to $ENV_FILE"
echo "Open a new terminal tab, then run bootstrap.sh"
