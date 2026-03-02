# Bootstrap Script Cleanup

## Problem

`bootstrap.sh` has accumulated several issues: an outdated "Next steps" message referencing OAuth auth that's no longer needed, duplicated Oh My Zsh blocks, full system upgrades on every run, missing idempotency guards, and Claude Code only installing on Linux.

## Changes

### 1. Remove full system upgrades

- **Linux**: Remove `apt-get upgrade -y`. Keep a single `apt-get update` at the top for fresh package indexes.
- **macOS**: Remove `brew update && brew upgrade`. Rely on `brew install` which is idempotent (installs if missing, upgrades if outdated).

### 2. Guard the ET PPA (Linux)

Only add the PPA if not already present:

```bash
if ! grep -qr "jgmath2000/et" /etc/apt/sources.list.d/ 2>/dev/null; then
  add-apt-repository -y ppa:jgmath2000/et
  apt-get update
fi
apt-get install -y et
```

### 3. Drop macOS brew guards

Remove all `command -v` and `if` checks around `brew install` calls. `brew install` is idempotent — it installs if missing and upgrades if outdated.

### 4. Deduplicate Oh My Zsh + zsh plugins

Move the Oh My Zsh install and zsh plugin clone blocks from both platform sections to the shared section. Both platforms install zsh before reaching the shared section.

### 5. Move Claude Code install to shared section

Move `curl -fsSL https://claude.ai/install.sh | bash` to the shared section, before the plugin install block that depends on it. Works on both macOS and Linux.

### 6. Fix summary/next steps

Remove the outdated "Run 'claude' to authenticate via OAuth" block. The only "next steps" message is the existing `setup-op-token.sh` hint when `OP_SERVICE_ACCOUNT_TOKEN` is missing.

### 7. Guard version output

Wrap `mosh-server --version` and `etserver --version` with `command -v` checks so they don't error if installs failed.
