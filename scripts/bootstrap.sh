#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Pick up the new PATH (~/.local/bin)
# shellcheck source=/dev/null
source ~/.bashrc

echo ""
echo "==> Claude Code installed! Version:"
claude --version
echo ""
echo "==> Next step: run 'claude' to authenticate via OAuth."
echo "    It will show a URL — open it in your local browser and paste the code back."
