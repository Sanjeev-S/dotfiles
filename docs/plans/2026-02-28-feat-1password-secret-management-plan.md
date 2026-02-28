---
title: "feat: Add 1Password CLI secret management"
type: feat
status: completed
date: 2026-02-28
deepened: 2026-02-28
origin: docs/brainstorms/2026-02-28-1pass-secret-management-brainstorm.md
---

# feat: Add 1Password CLI secret management

## Enhancement Summary

**Deepened on:** 2026-02-28
**Agents used:** security-sentinel, architecture-strategist, code-simplicity-reviewer, performance-oracle, pattern-recognition-specialist, best-practices-researcher, Context7 (1Password CLI docs)

### Key Improvements
1. Fixed file creation race condition — use `install -d -m 700` and `umask 077` subshell
2. Fixed shell injection risk — use `printf '%q'` instead of `echo` for secret serialization
3. Fixed `export` masking `op read` exit code — split assignment and export onto separate lines
4. Added `--no-newline` flag to `op read` to prevent trailing newline issues
5. Simplified `elif` chain to single `else` branch
6. Added `secrets.sh` to `.gitignore` as defense-in-depth
7. Added Linux debsig-verify policy (missing from original plan)

### New Considerations Discovered
- LaunchAgent logs in `/tmp/` are world-readable — move to `~/Library/Logs/`
- macOS brew section doesn't use `command -v` guards (relies on brew idempotency) — match existing pattern
- Service account should be created with `--expires-in 90d` and `read_items` permission only

---

## Overview

Replace hardcoded ntfy topic in hook scripts with 1Password CLI (`op read`) secret retrieval at bootstrap time. Secrets are cached to a local file, sourced by shell init, and read by scripts via environment variables. This establishes a general pattern for any future dotfile secrets.

## Problem Statement

The ntfy topic `sanjeev-claude-99e0b7e3e3ae` is hardcoded in two scripts committed to a **public** GitHub repo. It's in git history and cannot be removed without a force-push rewrite. Anyone with the topic can subscribe to notifications or spam the user. The topic must be rotated. (See brainstorm: `docs/brainstorms/2026-02-28-1pass-secret-management-brainstorm.md`)

## Proposed Solution

**Bootstrap-time secret materialization:**

1. `bootstrap.sh` installs `op` CLI
2. If `op` is available and authenticated, `bootstrap.sh` calls `op read` to fetch secrets and writes them to `~/.config/dotfiles/secrets.sh` (chmod 600)
3. `.zshrc` sources that file — no `op` dependency at shell startup
4. Scripts read `$NTFY_TOPIC` from environment; `ntfy-subscriber.sh` sources secrets file directly (LaunchAgent doesn't go through `.zshrc`)
5. If `op` is unavailable, bootstrap skips secret caching with a warning — everything else still works

## Technical Considerations

### `set -euo pipefail` safety

`bootstrap.sh` uses strict mode. All `op` interactions must be guarded:

```bash
if command -v op &>/dev/null && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  # op read calls here — failure is caught, not fatal
fi
```

The `${OP_SERVICE_ACCOUNT_TOKEN:-}` syntax avoids tripping the `nounset` (`-u`) flag. The `op read` call itself is guarded so failure logs a warning but doesn't abort bootstrap.

#### Research Insights

**`export` masks exit codes.** `export VAR="$(op read ...)"` silently succeeds even if `op read` fails — `export` returns 0 regardless. Under `set -e`, the script continues with an empty variable instead of aborting. Always split assignment and export:

```bash
# BAD — export masks non-zero exit code
export NTFY_TOPIC="$(op read 'op://Dotfiles/ntfy-topic/credential')"

# GOOD — assignment preserves exit code
NTFY_TOPIC_VAL="$(op read 'op://Dotfiles/ntfy-topic/credential' --no-newline 2>/dev/null)"
export NTFY_TOPIC="$NTFY_TOPIC_VAL"
```

**Trailing newline.** `op read` appends a newline by default. Use `--no-newline` (or `-n`) to prevent issues when the value is interpolated into URLs.

### LaunchAgent environment isolation

`ntfy-subscriber.sh` runs via `launchd` as `/bin/bash -c "exec ~/.claude/hooks/ntfy-subscriber.sh"`. It does **not** inherit `.zshrc` environment. It must explicitly source `~/.config/dotfiles/secrets.sh`. If the file is missing, it should log an error, sleep 30s, and exit (launchd will restart via `KeepAlive`).

#### Research Insights

**Log file location.** The plist currently writes logs to `/tmp/ntfy-subscriber.log` and `/tmp/ntfy-subscriber.err`, which are world-readable. If curl errors include the ntfy URL, the topic leaks. Move logs to `~/Library/Logs/` (conventional macOS location with appropriate default permissions).

### Ordering in bootstrap.sh

Secret caching must happen:
- **After** `op` is installed (platform-specific sections)
- **Before** LaunchAgent `bootout`/`bootstrap` (so the subscriber starts with secrets available)

Insert point: shared config section, between symlinks and LaunchAgent block.

### Security

- Parent directory created with `install -d -m 700` (restrictive from the start)
- `secrets.sh` written inside a `umask 077` subshell to prevent race condition between file creation and `chmod`
- Secret values serialized with `printf '%q'` to prevent shell metacharacter injection
- Intermediate variables (`NTFY_TOPIC_VAL`) unset after use
- `OP_SERVICE_ACCOUNT_TOKEN` should never be echoed or logged
- The file lives outside the repo (`~/.config/dotfiles/`) — also add `secrets.sh` to `.gitignore` as defense-in-depth

#### Research Insights

**Process environment visibility.** On Linux, `/proc/PID/environ` exposes environment variables to the same user. This is an inherent tradeoff of env-var-based secrets. For an ntfy topic (not a credential), this is acceptable. For actual API keys in the future, consider whether the env var should be scoped tighter (e.g., only in the scripts that need it, not globally via `.zshrc`).

## Acceptance Criteria

- [x] `op` CLI installed on macOS (`brew install --cask 1password-cli`) and Linux (apt repo with debsig-verify)
- [x] `bootstrap.sh` fetches `NTFY_TOPIC` from `op://Dotfiles/ntfy-topic/credential` and writes to `~/.config/dotfiles/secrets.sh`
- [x] `secrets.sh` created with `umask 077` — no race condition window
- [x] Parent directory `~/.config/dotfiles/` created with mode 700
- [x] `.zshrc` sources `secrets.sh` with existence guard
- [x] `notify.sh` reads `NTFY_TOPIC` from env var (with fallback to sourcing secrets file)
- [x] `ntfy-subscriber.sh` sources secrets file directly (LaunchAgent doesn't go through .zshrc)
- [x] `ntfy-subscriber.sh` handles missing secrets gracefully (sleep 30s, exit, launchd restarts)
- [x] Hardcoded topic string removed from both scripts
- [x] Bootstrap completes successfully even without `op` installed or `OP_SERVICE_ACCOUNT_TOKEN` set
- [x] "Next steps" output tells user to set `OP_SERVICE_ACCOUNT_TOKEN` if `op` was skipped
- [x] `secrets.sh` added to `.gitignore`
- [x] LaunchAgent logs moved from `/tmp/` to `~/Library/Logs/`
- [x] CLAUDE.md updated with `secrets.sh` pattern

## MVP

### bootstrap.sh — macOS section addition

```bash
# After existing brew installs (~line 93)
# Match existing macOS pattern: no command -v guard (brew install is idempotent)
echo "==> Installing 1Password CLI..."
brew install --cask 1password-cli
```

### bootstrap.sh — Linux section addition

```bash
# After existing apt-get installs (~line 42)
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
```

### bootstrap.sh — shared config secret caching (after symlinks, before LaunchAgent)

```bash
# Cache secrets from 1Password
if command -v op &>/dev/null && [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo "==> Caching secrets from 1Password..."
  install -d -m 700 "$HOME/.config/dotfiles"
  (
    umask 077
    NTFY_TOPIC_VAL="$(op read 'op://Dotfiles/ntfy-topic/credential' --no-newline 2>/dev/null)" && {
      printf 'export NTFY_TOPIC=%q\n' "$NTFY_TOPIC_VAL" > "$HOME/.config/dotfiles/secrets.sh"
      echo "    Secrets cached to ~/.config/dotfiles/secrets.sh"
    } || echo "    WARNING: Failed to read secrets from 1Password."
  )
else
  echo "    NOTE: op CLI or OP_SERVICE_ACCOUNT_TOKEN missing. Skipping secret caching."
fi
```

### zsh/zshrc — source secrets

```bash
# After aliases line, before Starship
[ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"
```

### claude/hooks/notify.sh — env var with fallback

```bash
#!/usr/bin/env bash
# Claude Code hook: sends ntfy.sh notifications on Stop and AskUserQuestion events.

# Source secrets if NTFY_TOPIC not already in environment
[ -z "${NTFY_TOPIC:-}" ] && [ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"

# Exit silently if topic unavailable — notifications are best-effort
[ -z "${NTFY_TOPIC:-}" ] && exit 0

HOSTNAME="$(hostname)"
# ... rest of script unchanged, using ${NTFY_TOPIC}
```

### claude/hooks/ntfy-subscriber.sh — source secrets, handle missing

```bash
#!/usr/bin/env bash
# Long-running ntfy subscriber for macOS notifications via terminal-notifier.

export PATH="/opt/homebrew/bin:$PATH"

# Source secrets (LaunchAgent doesn't go through .zshrc)
[ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"

if [ -z "${NTFY_TOPIC:-}" ]; then
  echo "ERROR: NTFY_TOPIC not set. Run bootstrap.sh with op CLI and OP_SERVICE_ACCOUNT_TOKEN." >&2
  sleep 30
  exit 1
fi

# ... rest of script unchanged, using ${NTFY_TOPIC}
```

### .gitignore — defense-in-depth

```
secrets.sh
```

### claude/com.sanjeev.ntfy-subscriber.plist — move logs out of /tmp

```xml
<key>StandardOutPath</key>
<string>/Users/sanjeev/Library/Logs/ntfy-subscriber.log</string>
<key>StandardErrorPath</key>
<string>/Users/sanjeev/Library/Logs/ntfy-subscriber.err</string>
```

### bootstrap.sh — next steps output update

```bash
# Add to the summary section if op was skipped
if ! command -v op &>/dev/null || [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  echo ""
  echo "  To enable ntfy notifications:"
  echo "    1. Install 1Password CLI: brew install --cask 1password-cli"
  echo "    2. Set OP_SERVICE_ACCOUNT_TOKEN in your environment"
  echo "    3. Re-run bootstrap.sh"
fi
```

## Files to Modify

| File | Change |
|------|--------|
| `bootstrap.sh` | Add `op` install (macOS + Linux), secret caching block, next-steps hint |
| `zsh/zshrc` | Add `source ~/.config/dotfiles/secrets.sh` with guard |
| `claude/hooks/notify.sh` | Replace hardcoded topic with env var + fallback source |
| `claude/hooks/ntfy-subscriber.sh` | Replace hardcoded topic with explicit secrets source + graceful missing handling |
| `claude/com.sanjeev.ntfy-subscriber.plist` | Move log paths from `/tmp/` to `~/Library/Logs/` |
| `.gitignore` | Add `secrets.sh` |
| `CLAUDE.md` | Add `secrets.sh` entry to repo layout table |

## Post-Implementation

- [ ] Create "Dotfiles" vault in 1Password
- [ ] Generate new ntfy topic, store as `ntfy-topic` item in Dotfiles vault
- [ ] Create Service Account: `op service-account create "dotfiles" --expires-in 90d --vault Dotfiles:read_items`
- [ ] Save the service account token in 1Password itself (it's only shown once)
- [ ] Set `OP_SERVICE_ACCOUNT_TOKEN` on each devserver
- [ ] Run `bootstrap.sh` to materialize secrets
- [ ] Verify notifications work with new topic

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-02-28-1pass-secret-management-brainstorm.md](docs/brainstorms/2026-02-28-1pass-secret-management-brainstorm.md) — Key decisions: 1Password CLI with Dotfiles vault, bootstrap-time caching, service accounts for headless servers
- Existing bootstrap patterns: `bootstrap.sh:33-36` (guarded install), `bootstrap.sh:163` (conditional feature block)
- Existing .zshrc sourcing: `zsh/zshrc:15` (`[ -f ~/.aliases ] && source ~/.aliases`)
- LaunchAgent plist: `claude/com.sanjeev.ntfy-subscriber.plist`
- [1Password CLI — `op read` reference](https://developer.1password.com/docs/cli/reference/commands/read/)
- [1Password CLI — Load secrets into scripts](https://developer.1password.com/docs/cli/secrets-scripts/)
- [1Password Service Accounts — Security model](https://developer.1password.com/docs/service-accounts/security/)
- [1Password Linux installation](https://support.1password.com/install-linux/)
