#!/bin/sh
set -e

# Bootstrap a fresh Mac: Xcode CLT → Homebrew → chezmoi → dotfiles
# Usage: curl -fsSL https://raw.githubusercontent.com/Sanjeev-S/dotfiles/main/bootstrap-mac.sh | sh

echo "==> Checking Xcode Command Line Tools..."
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Waiting for Xcode CLT installation to complete..."
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
  done
  echo "==> Xcode CLT installed"
fi

echo "==> Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Running chezmoi init --apply..."
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply Sanjeev-S

echo "==> Bootstrap complete! Open a new terminal to pick up changes."
