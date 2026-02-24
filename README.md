# dotfiles

Bootstrap a fresh server or Mac with Claude Code, mosh, Eternal Terminal, tmux, ntfy notifications, and a modern zsh setup (Oh My Zsh + Starship + plugins).

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

Subscribe to your topic in the ntfy app (topic is printed at the end of bootstrap).

## What's included

| Tool | Purpose |
|------|---------|
| Claude Code | AI coding assistant |
| mosh | Mobile-friendly SSH (UDP, roaming) |
| Eternal Terminal | Auto-reconnecting remote shell |
| tmux | Terminal multiplexer (persistent sessions) |
| ntfy hooks | Push notifications for Claude events |
| Oh My Zsh | Zsh plugin framework |
| Starship | Fast, customizable prompt |
| zsh-autosuggestions | Fish-like command suggestions |
| zsh-syntax-highlighting | Real-time command highlighting |
| JetBrains Mono NF | Nerd Font with icon support |

## Repo structure

```
bootstrap.sh              # single entry point (detects OS)
zsh/zshrc                 # → ~/.zshrc
starship/starship.toml    # → ~/.config/starship.toml
shell/aliases.sh          # → ~/.aliases
tmux/tmux.conf            # → ~/.tmux.conf
claude/hooks/notify.sh    # → ~/.claude/hooks/notify.sh
claude/settings.json      # → ~/.claude/settings.json
```
