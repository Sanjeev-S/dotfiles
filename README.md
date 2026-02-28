# dotfiles

Bootstrap a fresh server or Mac with Claude Code, mosh, Eternal Terminal, tmux, native notifications, and a modern zsh setup (Oh My Zsh + Starship + plugins).

Config files live in topic directories and get symlinked into `$HOME` — edits in either location propagate automatically.

## Setup (Linux server)

```bash
ssh hetzner-default

git clone https://github.com/Sanjeev-S/dotfiles.git ~/dotfiles
bash ~/dotfiles/bootstrap.sh

# Authenticate (opens a URL — paste code back)
claude
```

## Setup (Mac)

```bash
git clone https://github.com/Sanjeev-S/dotfiles.git ~/dotfiles
bash ~/dotfiles/bootstrap.sh
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

## Notifications

Claude Code hooks send push notifications via [ntfy.sh](https://ntfy.sh) when:
- **Claude finishes** a task (Stop)
- **Claude needs input** (AskUserQuestion) — high priority

On macOS, a LaunchAgent subscribes to the ntfy topic and shows native Notification Center alerts via `terminal-notifier`. The subscriber starts automatically at login and is installed by `bootstrap.sh`.

## What's included

| Tool | Purpose | Platform |
|------|---------|----------|
| Claude Code | AI coding assistant | Linux |
| mosh | Mobile-friendly SSH (UDP, roaming) | Both |
| Eternal Terminal | Auto-reconnecting remote shell | Both |
| tmux | Terminal multiplexer (persistent sessions) | Both |
| ntfy hooks | Push notifications for Claude events | Both |
| ntfy subscriber | Native macOS notifications from ntfy | macOS |
| terminal-notifier | macOS Notification Center integration | macOS |
| Oh My Zsh | Zsh plugin framework | macOS |
| Starship | Fast, customizable prompt | macOS |
| zsh-autosuggestions | Fish-like command suggestions | macOS |
| zsh-syntax-highlighting | Real-time command highlighting | macOS |
| JetBrains Mono NF | Nerd Font with icon support | macOS |
| iTerm2 | Terminal emulator | macOS |

## Repo structure

```
.gitignore                # .DS_Store, *.swp, settings.local.json
bootstrap.sh              # single entry point (detects OS)
tmux/tmux.conf            # → ~/.tmux.conf (both)
claude/hooks/notify.sh    # → ~/.claude/hooks/notify.sh (both)
claude/hooks/ntfy-subscriber.sh  # → ~/.claude/hooks/ntfy-subscriber.sh (both)
claude/com.sanjeev.ntfy-subscriber.plist  # → ~/Library/LaunchAgents/... (macOS)
claude/settings.json      # → ~/.claude/settings.json (both)
shell/aliases.sh          # → ~/.aliases (macOS)
zsh/zshrc                 # → ~/.zshrc (macOS)
starship/starship.toml    # → ~/.config/starship.toml (macOS)
```
