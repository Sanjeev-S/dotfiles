# Bootstrap Script Cleanup — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up `bootstrap.sh` to remove stale messages, deduplicate blocks, drop full system upgrades, guard the ET PPA, and make Claude Code install cross-platform.

**Architecture:** Single-file refactor of `bootstrap.sh`. Platform-specific sections handle only platform-specific installs; shared section handles Oh My Zsh, zsh plugins, Claude Code, symlinks, secrets, and plugins.

**Tech Stack:** Bash (strict mode: `set -euo pipefail`)

---

### Task 1: Remove full system upgrades

**Files:**
- Modify: `bootstrap.sh:26-28` (Linux `apt-get upgrade`)
- Modify: `bootstrap.sh:92-94` (macOS `brew update && brew upgrade`)

**Step 1: Edit Linux section**

Remove lines 26-28 (`add-apt-repository`, `apt-get update`, `apt-get upgrade`). Replace with a single `apt-get update` for fresh package indexes, then a guarded ET PPA block:

```bash
  # Update package index
  apt-get update

  # Eternal Terminal (requires PPA)
  if ! grep -qr "jgmath2000/et" /etc/apt/sources.list.d/ 2>/dev/null; then
    echo "==> Adding Eternal Terminal PPA..."
    add-apt-repository -y ppa:jgmath2000/et
    apt-get update
  fi
  echo "==> Installing Eternal Terminal..."
  apt-get install -y et
```

This replaces lines 24-30 (the old ET block).

**Step 2: Edit macOS section**

Remove lines 92-94:
```bash
  echo "==> Updating packages..."
  brew update
  brew upgrade
```

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "Remove full system upgrades, guard ET PPA

Linux: replace apt-get upgrade with targeted apt-get update + PPA guard.
macOS: remove brew update && brew upgrade (brew install is idempotent)."
```

---

### Task 2: Drop macOS brew guards and simplify install lines

**Files:**
- Modify: `bootstrap.sh:32-36` (gh guard)
- Modify: `bootstrap.sh:96-136` (macOS brew installs)

**Step 1: Remove `command -v gh` guard on Linux**

Replace lines 32-36:
```bash
  # GitHub CLI
  if ! command -v gh &>/dev/null; then
    echo "==> Installing GitHub CLI..."
    apt-get install -y gh
  fi
```

With:
```bash
  # GitHub CLI
  echo "==> Installing GitHub CLI..."
  apt-get install -y gh
```

`apt-get install` is idempotent — it upgrades if already installed.

**Step 2: Remove Starship guard on Linux**

Replace lines 42-46:
```bash
  # Starship prompt
  if ! command -v starship &>/dev/null; then
    echo "==> Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi
```

With:
```bash
  # Starship prompt
  echo "==> Installing Starship prompt..."
  curl -sS https://starship.rs/install.sh | sh -s -- -y
```

**Step 3: Clean up macOS echo lines**

The macOS section has individual `echo` lines before each `brew install`. Since `brew install` already prints output, consolidate to a single echo:

```bash
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
```

**Step 4: Commit**

```bash
git add bootstrap.sh
git commit -m "Drop redundant install guards

apt-get install and brew install are both idempotent.
Consolidate macOS brew installs into a single block."
```

---

### Task 3: Deduplicate Oh My Zsh + zsh plugins to shared section

**Files:**
- Modify: `bootstrap.sh:64-75` (Linux Oh My Zsh + plugins — remove)
- Modify: `bootstrap.sh:138-149` (macOS Oh My Zsh + plugins — remove)
- Modify: `bootstrap.sh:156+` (shared section — add before symlinks)

**Step 1: Remove Oh My Zsh + plugins from Linux section**

Delete lines 64-75 (the Oh My Zsh install and zsh plugin clone blocks).

**Step 2: Remove Oh My Zsh + plugins from macOS section**

Delete lines 138-149 (identical block).

**Step 3: Add to shared section**

Insert before the "Symlinking shared config files" line:

```bash
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

```

**Step 4: Commit**

```bash
git add bootstrap.sh
git commit -m "Deduplicate Oh My Zsh + plugins to shared section"
```

---

### Task 4: Move Claude Code install to shared section

**Files:**
- Modify: `bootstrap.sh:38-40` (Linux Claude install — remove)
- Modify: shared section (add before plugin block)

**Step 1: Remove Claude Code install from Linux section**

Delete lines 38-40:
```bash
  # Claude Code (native install)
  echo "==> Installing/updating Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
```

**Step 2: Add Claude Code install to shared section**

Insert before the "Claude Code plugins" block:

```bash
# ── Claude Code ───────────────────────────────────────────────────────────
echo "==> Installing/updating Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
```

**Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "Move Claude Code install to shared section

Works on both macOS and Linux. Runs before plugin installs."
```

---

### Task 5: Fix summary and version output

**Files:**
- Modify: `bootstrap.sh:202-224` (summary section)

**Step 1: Guard version output and remove outdated next steps**

Replace the entire summary section (lines 202-224) with:

```bash
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
```

This removes the outdated "Run 'claude' to authenticate via OAuth" block and guards all version checks.

**Step 2: Commit**

```bash
git add bootstrap.sh
git commit -m "Fix summary: remove outdated OAuth message, guard version output"
```

---

### Task 6: Final review

**Step 1: Read the full file and verify**

Read `bootstrap.sh` end-to-end and verify:
- No duplicated blocks
- No full system upgrades
- ET PPA is guarded
- Oh My Zsh + plugins appear only in shared section
- Claude Code install is in shared section before plugins
- Summary has no stale messages
- All version checks are guarded

**Step 2: Squash into a single commit (optional)**

If the user prefers a single commit, squash all changes:

```bash
git reset --soft HEAD~5
git commit -m "Clean up bootstrap.sh

- Remove full system upgrades (apt-get upgrade, brew update/upgrade)
- Guard ET PPA to avoid re-adding on every run
- Drop redundant install guards (apt/brew are idempotent)
- Deduplicate Oh My Zsh + zsh plugins to shared section
- Move Claude Code install to shared section (cross-platform)
- Remove outdated 'authenticate via OAuth' next steps message
- Guard version output with command -v checks"
```
