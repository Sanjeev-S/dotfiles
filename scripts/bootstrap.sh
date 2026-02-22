#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Ensure ~/.local/bin is in PATH
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "==> Claude Code installed! Version:"
claude --version
echo ""
echo "==> Next step: run 'claude' to authenticate via OAuth."
echo "    It will show a URL — open it in your local browser and paste the code back."
