# dotfiles

Cross-platform (macOS + Linux) dotfiles managed by [chezmoi](https://www.chezmoi.io/) with [mise](https://mise.jdx.dev/) for language runtimes and [1Password](https://developer.1password.com/docs/cli/) for secrets.

## Bootstrap

```bash
# First time only: save 1Password service account token
bash <(curl -fsSL https://raw.githubusercontent.com/Sanjeev-S/dotfiles/main/setup-op-token.sh)

# Then init chezmoi (prompts for machine type + 1Password token)
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply Sanjeev-S
```

## Update

```bash
chezmoi apply
```

## Connecting

### Mac (iTerm2 native tabs via ET + tmux -CC)
```bash
et root@hetzner-default -c 'tmux -CC new-session -A -s main'
```

### Phone (Blink / mosh)
```bash
mosh root@hetzner-default -- tmux attach -t main
```

### Plain SSH
```bash
ssh hetzner-default -t 'tmux new-session -A -s main'
```

## What's included

| Tool | Purpose | Platform |
|------|---------|----------|
| Claude Code | AI coding assistant + plugins (superpowers, compound-engineering) | Both |
| Codex | OpenAI Codex CLI | Both |
| mise | Language runtime manager (Node, Python) | Both |
| mosh | Mobile-friendly SSH (UDP, roaming) | Both |
| Eternal Terminal | Auto-reconnecting remote shell | Both |
| tmux | Terminal multiplexer (persistent sessions) | Both |
| Oh My Zsh | Zsh plugin framework | Both |
| Starship | Fast, customizable prompt | Both |
| zsh-autosuggestions | Fish-like command suggestions | Both |
| zsh-syntax-highlighting | Real-time command highlighting | Both |
| ripgrep | Fast recursive search (`rg`) | Both |
| bat | `cat` with syntax highlighting | Both |
| fd | Fast `find` alternative | Both |
| fzf | Fuzzy finder | Both |
| delta | Git diff pager | Both |
| zoxide | Smarter `cd` | Both |
| gh | GitHub CLI | Both |
| 1password-cli | Secret management (`op`) | Both |
| ntfy hooks | Push notifications for Claude events | Both |
| ntfy subscriber | Native macOS notifications from ntfy | macOS |
| terminal-notifier | macOS Notification Center integration | macOS |
| JetBrains Mono NF | Nerd Font with icon support | macOS |
| iTerm2 | Terminal emulator | macOS |

## Notifications

Claude Code hooks send push notifications via [ntfy.sh](https://ntfy.sh) when:
- **Claude finishes** a task (Stop)
- **Claude needs input** (AskUserQuestion) — high priority

On macOS, a LaunchAgent subscribes to the ntfy topic and shows native Notification Center alerts via `terminal-notifier`. The subscriber starts automatically at login. An idle-detection wrapper pauses notifications when the terminal is active.

## Secrets

Secrets are fetched from 1Password via `op read` — nothing is stored in the repo.

1. Run `setup-op-token.sh` to save your 1Password service account token to `~/.config/dotfiles/.env`
2. `chezmoi init` prompts for the token and stores it in chezmoi's config
3. `chezmoi apply` caches secrets to `~/.config/dotfiles/secrets.sh` on first run
4. To refresh after a secret rotation: `secrets-refresh`

Machine types (`mac-personal`, `mac-dev`, `linux-dev`) drive per-machine config differences via `{{ .machine_type }}` in templates.

## Repo structure

```
.chezmoi.toml.tmpl              # chezmoi config (machine_type, op_token prompts)
.chezmoiignore                  # files not deployed to $HOME
.chezmoiscripts/
  run_once_before_01-install-mise.sh.tmpl
  run_onchange_before_02-install-packages.sh.tmpl
  run_onchange_after_01-install-mise-tools.sh.tmpl
  run_once_after_02-cache-secrets.sh.tmpl
  run_once_after_03-install-claude.sh.tmpl
  run_onchange_after_04-update-codex.sh.tmpl
  run_once_after_05-configure-dev-server.sh.tmpl
  run_once_after_06-load-launchagent.sh.tmpl
dot_aliases                     # → ~/.aliases
dot_claude/                     # → ~/.claude/
  hooks/                        #   notify.sh, ntfy-subscriber.sh
  settings.json.tmpl            #   Claude Code settings
  CLAUDE.md                     #   Global agent instructions
  executable_statusline.sh      #   Claude Code statusline
dot_codex/                      # → ~/.codex/
  config.toml.tmpl              #   Codex CLI config
dot_config/
  mise/config.toml              # → ~/.config/mise/config.toml
  starship.toml                 # → ~/.config/starship.toml
dot_gitconfig.tmpl              # → ~/.gitconfig
dot_local/bin/
  executable_secrets-refresh    # → ~/.local/bin/secrets-refresh
dot_tmux.conf                   # → ~/.tmux.conf
dot_zshrc.tmpl                  # → ~/.zshrc
private_Library/                # → ~/Library/ (macOS only)
  LaunchAgents/                 #   ntfy subscriber plist
setup-op-token.sh               # 1Password token setup (not deployed)
docs/                           # Plans, brainstorms (not deployed)
```
