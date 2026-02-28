# Brainstorm: 1Password CLI for Dotfiles Secret Management

**Date:** 2026-02-28
**Status:** Final

## What We're Building

A pattern for managing secrets in this dotfiles repo using 1Password CLI (`op`). The immediate use case is the ntfy topic (currently hardcoded and exposed in a public repo), but the pattern should generalize to any secret a dotfile script might need.

## Why This Approach

- **1Password CLI** provides a single source of truth across Mac and Linux
- **Service Accounts** enable headless auth on remote servers without browser login
- **`op read`** fetches secrets at runtime, so nothing sensitive is ever written to disk or committed
- The user already has a 1Password account; only the CLI needs to be added

## Context: Current Problem

The ntfy topic `sanjeev-claude-99e0b7e3e3ae` is:
- Hardcoded in `claude/hooks/notify.sh` and `claude/hooks/ntfy-subscriber.sh`
- Committed to a **public** GitHub repo
- Baked into git history (even removing from HEAD doesn't help)
- Unauthenticated on the ntfy.sh side — anyone with the topic can subscribe or publish

**The current topic should be considered compromised and must be rotated.**

## Key Decisions

1. **Use `op read "op://Vault/Item/field"`** to fetch secrets inline in scripts
2. **Service Account** for headless Linux devservers — the token is set once as `OP_SERVICE_ACCOUNT_TOKEN` env var
3. **Fallback to env var** — if `op` isn't installed, scripts check `$NTFY_TOPIC` as a fallback so things don't break during bootstrap or on machines without `op`
4. **Add `op` CLI to bootstrap.sh** — install on both macOS (brew) and Linux (official apt/binary)
5. **Rotate the ntfy topic** after implementation — generate a new topic, store in 1Password, update scripts
6. **General pattern** — any future secret follows the same `op read` pattern with env var fallback

## Design Sketch

### Bootstrap-time secret materialization

`bootstrap.sh` fetches secrets from 1Password and writes them to a local gitignored file:

```bash
# In bootstrap.sh (shared config section)
if command -v op &>/dev/null; then
  mkdir -p "$HOME/.config/dotfiles"
  echo "export NTFY_TOPIC=\"$(op read 'op://Dotfiles/ntfy-topic/credential')\"" \
    > "$HOME/.config/dotfiles/secrets.sh"
fi
```

### Shell init sources the cached secrets

```bash
# In .zshrc
[ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"
```

### Scripts read from env var

```bash
# In notify.sh / ntfy-subscriber.sh
NTFY_TOPIC="${NTFY_TOPIC:?ERROR: NTFY_TOPIC not set. Run bootstrap.sh with op CLI available.}"
```

### Service Account setup (per remote server, one-time)

```bash
# Set once in ~/.bashrc or ~/.zshrc (before sourcing secrets)
export OP_SERVICE_ACCOUNT_TOKEN="<token-from-1password>"
```

### Bootstrap changes

- macOS: `brew install --cask 1password-cli`
- Linux: install `op` from 1Password's official release

## Alternatives Considered

| Approach | Why not |
|----------|---------|
| Gitignored `.secrets` file | No centralized rotation, manual sync across machines |
| macOS Keychain + `pass` | Two systems to manage, GPG complexity on Linux |
| ntfy.sh access tokens | Only solves ntfy, not a general secret pattern |

## Resolved Questions

1. **Which 1Password vault?** Dedicated "Dotfiles" vault — cleaner service account permissions, scoped to dotfile secrets only.
2. **Caching strategy** — Bootstrap-time caching. `bootstrap.sh` calls `op read` and writes secrets to a gitignored file (`~/.config/dotfiles/secrets.sh`). `.zshrc` sources that file. No `op` dependency at shell init, works offline, updated on each bootstrap run.
3. **Service account scope** — Entire "Dotfiles" vault. Simpler setup, and the vault is already scoped to dotfile secrets only.

## Open Questions

None — all questions resolved.
