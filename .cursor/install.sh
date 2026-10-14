#!/usr/bin/env bash
# Cloud Agent bootstrap for the dotfiles repo.
#
# Scope: install the tools needed to *develop and validate the chezmoi source*
# — not to provision a real machine. A real `chezmoi apply` runs the package
# installs in .chezmoiscripts/ and needs a 1Password service-account token, so
# it is intentionally out of scope here. This script only sets up:
#   - chezmoi : renders/applies the templates (the core edit-validate loop)
#   - mise    : the repo's pinned language-runtime manager (Node, Python)
#   - shellcheck : lints the many bash scripts and script templates
# It is idempotent: every step is guarded so re-running is a fast no-op.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

echo "==> chezmoi (dotfiles manager)"
if ! command -v chezmoi >/dev/null 2>&1; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi
chezmoi --version

echo "==> mise (pinned runtime manager)"
if ! command -v mise >/dev/null 2>&1; then
  curl -fsSL https://mise.run | sh
fi
mise --version

echo "==> shellcheck (script linter)"
if ! command -v shellcheck >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y shellcheck
fi
shellcheck --version | sed -n '2p'

echo "==> Installing the repo's pinned runtimes via mise"
# Honor the versions pinned in the source of truth (dot_config/mise/config.toml
# deploys to ~/.config/mise/config.toml on a real machine). The stock Ubuntu
# image lacks the -dev headers pyenv would need to build CPython from source, so
# fetch a precompiled standalone build instead of compiling.
install -Dm644 "$REPO_ROOT/dot_config/mise/config.toml" "$HOME/.config/mise/config.toml"
mise settings set python.compile false
mise install -y

echo "==> Environment ready. Pinned runtimes:"
mise exec -- node --version
mise exec -- python --version
