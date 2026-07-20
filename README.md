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
| Tailscale | Mesh VPN reaching the dev boxes (manual sign-in per device) | Both |
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

Machine types (`mac-personal`, `mac-dev`, `linux-dev`, `dgx-spark`) drive per-machine config differences via `{{ .machine_type }}` in templates.

## Mac mini (mac-dev)

Tailscale runs as the open-source `tailscaled` system daemon — not the GUI app —
so the box is on the tailnet from boot with nobody logged in (ADR 0004).
Bring-up or recovery:

```bash
# On the mini (first time: remove any GUI Tailscale.app after signing out of it)
chezmoi update        # installs tailscale formula, registers daemon,
                      # enables Remote Login, starts et
sudo tailscale up --hostname=macmini

# From any signed-in device
ssh macmini
macmini-connect       # et + tmux -CC
```

If `systemsetup -setremotelogin on` errors (Full Disk Access), enable Remote
Login in System Settings > General > Sharing instead.

## DGX Spark

Complete NVIDIA's first-boot wizard using Ethernet when available. Create the
`sanjeevsuresh` user and do not interrupt the wizard while it is working. When it
finishes, use DGX Dashboard to install all OS, driver, and firmware updates before
continuing, then run:

```bash
sudo hostnamectl set-hostname dgx-spark
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply Sanjeev-S
# Choose machine type: dgx-spark

sudo tailscale up --ssh --hostname=dgx-spark
tailscale status
tailscale ip
```

Open the authentication URL printed by `tailscale up`, approve the Spark in the
tailnet, and connect from a signed-in device:

```bash
ssh dgx-spark
```

Tailscale authentication is deliberately not automated: no reusable auth key is
stored in this repo. If the tailnet uses a custom access policy, it must permit both
network access and Tailscale SSH to this device.

The `dgx-spark` machine type treats the box's contents as disposable: it grants the
account passwordless sudo, disables system sleep, enables Wi-Fi autoconnect with
power saving disabled, and gives local agents unrestricted tool access. Do not put
broad personal credentials on this host or advertise home-LAN subnet routes from it.
