#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Ensure ~/.local/bin is in PATH permanently.
# Insert at top of .bashrc so it takes effect before any early-return guard
# (e.g. "[ -z "$PS1" ] && return" which skips the rest for non-interactive shells).
if ! grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' ~/.bashrc 2>/dev/null; then
  sed -i '1a export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc
fi
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "==> Claude Code installed! Version:"
claude --version
echo ""
echo "==> Next step: run 'claude' to authenticate via OAuth."
echo "    It will show a URL — open it in your local browser and paste the code back."
