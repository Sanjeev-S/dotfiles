# Dotfiles

Cross-platform (macOS + Linux) dotfiles managed via symlinks from topic directories into `$HOME`.

## Repo Layout

| Directory | Config file | Symlink target |
|-----------|------------|----------------|
| `git/` | `gitconfig` | `~/.gitconfig` |
| `zsh/` | `zshrc` | `~/.zshrc` |
| `shell/` | `aliases.sh` | `~/.aliases` |
| `tmux/` | `tmux.conf` | `~/.tmux.conf` |
| `starship/` | `starship.toml` | `~/.config/starship.toml` |
| `claude/` | `settings.json` | `~/.claude/settings.json` |
| `claude/` | `statusline.sh` | `~/.claude/statusline.sh` |
| `claude/` | `com.sanjeev.ntfy-subscriber.plist` | `~/Library/LaunchAgents/...` (macOS) |
| `claude/hooks/` | `notify.sh` | `~/.claude/hooks/notify.sh` |
| `claude/hooks/` | `ntfy-subscriber.sh` | `~/.claude/hooks/ntfy-subscriber.sh` |
| *(generated)* | `secrets.sh` | `~/.config/dotfiles/secrets.sh` |

## Conventions

- **One directory per tool.** Each tool gets its own topic directory containing its config files.
- **Symlinks, not copies.** All configs are symlinked via the `symlink()` helper in `bootstrap.sh` using `ln -sfn`.
- **Cross-platform.** `bootstrap.sh` detects the OS and runs platform-specific setup. Shared config (symlinks, plugins) runs on both. When adding install commands, add them to both the Linux and macOS sections.
- **Idempotent.** Installs use guard checks (`command -v`, `[ -d ... ]`, `|| true`) so `bootstrap.sh` can be re-run safely.
- **Bash with strict mode.** `bootstrap.sh` uses `set -euo pipefail`.

## Adding a New Tool

1. Create a topic directory: `toolname/`
2. Add the config file inside it
3. Add a `symlink` line to the "Shared config" section of `bootstrap.sh`
4. Add install commands to the Linux and/or macOS sections of `bootstrap.sh`
