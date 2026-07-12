# dotfiles

Cross-platform (macOS + Linux) dotfiles managed by [chezmoi](https://www.chezmoi.io/) with [mise](https://mise.jdx.dev/) for language runtimes and [1Password](https://developer.1password.com/docs/cli/) for secrets.

## Bootstrap

```bash
# First time (or token rotation): set 1Password service account token
bash <(curl -fsSL https://raw.githubusercontent.com/Sanjeev-S/dotfiles/main/rotate-op-token.sh)

# Then init chezmoi (prompts for machine type + 1Password token)
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply Sanjeev-S
```

## Update

Manual:

```bash
chezmoi apply        # apply current source to $HOME
dotup --force        # update chezmoi + Claude + Codex + Matt Pocock skills now
```

Scheduled: `dotup` runs hourly (launchd on macOS, systemd-user on Linux) and no-ops if a successful run happened in the last 24h. On any step failure, a banner appears in new zsh sessions until the next clean run. See `docs/adr/0001-dotup-scheduling-architecture.md`.

## Connecting

### Mac (iTerm2 native tabs via ET + tmux -CC)
```bash
et root@hetzner-16g -c 'tmux -CC new-session -A -s main'
```

### Phone (Blink / mosh)
```bash
mosh root@hetzner-16g -- tmux attach -t main
```

### Plain SSH
```bash
ssh hetzner-16g -t 'tmux new-session -A -s main'
```

## What's included

| Tool | Purpose | Platform |
|------|---------|----------|
| Claude Code | AI coding assistant + plugins (superpowers, compound-engineering) | Both |
| Codex | OpenAI Codex CLI + Matt Pocock skills | Both |
| Composio CLI | Connect coding agents to external app toolkits | Both |
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

1. Run `rotate-op-token.sh` to set your 1Password service account token (updates `.env`, `chezmoi.toml`, and re-caches secrets)
2. `chezmoi init` also prompts for the token on first run
3. `chezmoi apply` caches secrets to `~/.config/dotfiles/secrets.sh` on first run
4. To refresh secrets after a rotation in 1Password: `secrets-refresh`
5. To rotate the SA token itself: `bash rotate-op-token.sh`

### macOS: why `op` doesn't trigger permission prompts here

`secrets-refresh` exports `OP_BIOMETRIC_UNLOCK_ENABLED=false` and
`OP_LOAD_DESKTOP_APP_SETTINGS=false` before calling `op`. Without these, every `op`
invocation reads the 1Password desktop app's settings from its protected group container
(`~/Library/Group Containers/2BUA8C4S2C.com.1password` — hardcoded in the `op` binary),
which fires a macOS TCC prompt ("op would like to access data from other apps"). Under
launchd (`dotup`) that grant can't persist for an unbundled CLI, so it used to re-prompt
on each of the 9 daily reads. Disabling "Integrate with 1Password CLI" in the app does
NOT stop the CLI-side probe — only the env vars do. We authenticate exclusively with
`OP_SERVICE_ACCOUNT_TOKEN`, so the desktop-app integration is unused anyway. No
per-machine setup needed; the fix travels with this repo.

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
  run_once_after_03b-install-codex.sh.tmpl
  run_once_after_03c-install-codex-skills.sh.tmpl
  run_once_after_05-configure-dev-server.sh.tmpl
  run_once_after_06-load-launchagent.sh.tmpl
  run_once_after_07-schedule-dotup.sh.tmpl
dot_aliases                     # → ~/.aliases
dot_claude/                     # → ~/.claude/
  hooks/                        #   notify.sh, ntfy-subscriber.sh
  settings.json.tmpl            #   Claude Code settings
  CLAUDE.md                     #   Global agent instructions
  executable_statusline.sh      #   Claude Code statusline
dot_codex/                      # → ~/.codex/
  config.toml.tmpl              #   Codex CLI config
  AGENTS.md                     #   Global Codex instructions
dot_config/
  mise/config.toml              # → ~/.config/mise/config.toml
  starship.toml                 # → ~/.config/starship.toml
dot_gitconfig.tmpl              # → ~/.gitconfig
dot_config/systemd/user/        # → ~/.config/systemd/user/ (linux-dev only)
  dotup.service                 #   dotup oneshot unit
  dotup.timer                   #   hourly timer
dot_local/bin/
  executable_secrets-refresh    # → ~/.local/bin/secrets-refresh
  executable_dotup              # → ~/.local/bin/dotup
  executable_mattpocock-skills-sync # → ~/.local/bin/mattpocock-skills-sync
dot_tmux.conf                   # → ~/.tmux.conf
dot_zprofile.tmpl               # → ~/.zprofile (login-shell PATH after macOS path_helper)
dot_zshrc.tmpl                  # → ~/.zshrc
private_Library/                # → ~/Library/ (macOS only)
  LaunchAgents/                 #   ntfy subscriber plist (mac-personal),
                                #   dotup plist (mac-personal + mac-dev)
.chezmoiremove                  # Paths chezmoi ensures are absent in $HOME
rotate-op-token.sh              # 1Password token rotation (not deployed)
docs/                           # Plans, brainstorms, ADRs (not deployed)
```
