# Chezmoi Migration Design

## Overview

Migrate the dotfiles repo from a custom symlink-based approach (`bootstrap.sh` + `ln -sfn`) to chezmoi + mise + 1Password. The goal is a future-forward architecture that scales across multiple Macs, multiple Linux VMs, and multiple AI coding agents.

## Stack

- **chezmoi** — dotfile management, templating, deployment
- **mise** — language runtime version management (Node, Python)
- **1Password** — secrets management (service account token prompted at init)
- **No age encryption** — 1Password is the single source of truth for secrets
- **No CI** — manual testing for now

## Agents

- **Claude Code** — installed via native installer (`claude.ai/install.sh`)
- **Codex** — installed via native installer
- Both managed as `dot_claude/` and `dot_codex/` directories, trivial to add `dot_gemini/`, `dot_cursor/` later

## Machine Types

| Type | Platform | Example |
|------|----------|---------|
| `mac-personal` | macOS | Personal MacBook |
| `linux-server` | Linux | Hetzner VMs (root user) |

Extensible — add `mac-work` later when needed.

## Source Directory

`~/dotfiles` on all machines. Set via `sourceDir` in `.chezmoi.toml.tmpl`.

Current repo moves from `~/sanjeev/dotfiles` to `~/dotfiles`. Git history preserved.

## Bootstrap

Single command on any fresh machine:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Sanjeev-S
```

### Init prompts

1. Machine type: `mac-personal` or `linux-server`
2. 1Password service account token (leave blank to skip)

### Execution order

```
1. chezmoi binary downloaded to ~/.local/bin/
2. Repo cloned to ~/dotfiles
3. .chezmoi.toml.tmpl prompts for machine_type + OP token
4. run_once_before_01-install-mise.sh.tmpl
   - macOS: brew install mise (install brew first if missing)
   - Linux: curl https://mise.run | sh
5. run_once_before_02-install-packages.sh.tmpl
   - macOS: brew install jq mosh gh starship terminal-notifier et iterm2 font-jetbrains-mono-nerd-font 1password-cli ripgrep bat fd fzf delta zoxide
   - Linux: apt-get install jq mosh zsh gh et 1password-cli
   - Sets zsh as default shell if not already
6. All dotfiles deployed (templates rendered, files placed)
7. run_onchange_after_mise-install.sh.tmpl
   - mise install -y (node lts, python 3.12)
8. run_once_after_install-claude-code.sh.tmpl
   - curl -fsSL https://claude.ai/install.sh | bash
9. run_once_after_install-claude-plugins.sh.tmpl
   - claude plugin marketplace add + install
10. run_once_after_cache-secrets.sh.tmpl
    - If OP token is set: fetch NTFY_TOPIC, OPENROUTER_API_KEY from 1Password
    - Save to ~/.config/dotfiles/secrets.sh
11. (macOS only) LaunchAgent loaded for ntfy subscriber
```

### Updating an existing machine

```bash
chezmoi apply
```

Only changed files get updated. `run_onchange` scripts re-run only if tracked config changed. `run_once` scripts don't re-run.

## Repository Structure

```
dotfiles/                              # Root = chezmoi source directory
├── CLAUDE.md                          # For agents working ON this repo (not deployed)
├── README.md                          # Not deployed
├── setup-op-token.sh                  # Legacy/fallback (not deployed)
├── docs/                              # Plans, brainstorms (not deployed)
│
├── .chezmoi.toml.tmpl                 # Init prompts + sourceDir config
├── .chezmoiignore                     # Exclude non-deployable files + OS conditionals
├── .chezmoiscripts/
│   ├── run_once_before_01-install-mise.sh.tmpl
│   ├── run_once_before_02-install-packages.sh.tmpl
│   ├── run_onchange_after_mise-install.sh.tmpl
│   ├── run_once_after_install-claude-code.sh.tmpl
│   ├── run_once_after_install-claude-plugins.sh.tmpl
│   └── run_once_after_cache-secrets.sh.tmpl
│
├── dot_config/
│   ├── mise/config.toml               # Global mise config (node, python)
│   └── starship.toml
│
├── dot_claude/
│   ├── CLAUDE.md                      # Global everyday Claude Code instructions
│   ├── settings.json.tmpl             # Templated: permissions/hooks per OS
│   ├── hooks/
│   │   ├── executable_notify.sh
│   │   └── executable_ntfy-subscriber.sh
│   └── executable_statusline.sh
│
├── dot_codex/
│   └── (codex config files)
│
├── dot_gitconfig.tmpl                 # Templated: email per machine type
├── dot_zshrc.tmpl                     # Templated: OS-conditional blocks
├── dot_aliases
├── dot_tmux.conf
│
└── private_Library/                   # macOS only (ignored on Linux)
    └── LaunchAgents/
        └── com.sanjeev.ntfy-subscriber.plist.tmpl
```

## .chezmoiignore

```
CLAUDE.md
README.md
docs/
setup-op-token.sh

{{ if ne .chezmoi.os "darwin" }}
private_Library/
dot_claude/hooks/executable_ntfy-subscriber.sh
{{ end }}
```

## Template Variables

### .chezmoi.toml.tmpl

```toml
sourceDir = "{{ .chezmoi.homeDir }}/dotfiles"

[data]
machine_type = prompt for mac-personal | linux-server
op_token = prompt for 1Password service account token (optional)
email = "Sanjeev-S@users.noreply.github.com"
```

### What gets templated

| File | Why |
|------|-----|
| `.chezmoi.toml.tmpl` | Init prompts, sourceDir |
| `dot_gitconfig.tmpl` | Email could vary by machine type |
| `dot_zshrc.tmpl` | OS-conditional blocks (brew shellenv on Mac) |
| `dot_claude/settings.json.tmpl` | Different permissions/hooks per OS |
| `private_Library/.../plist.tmpl` | Inject correct home directory path |
| `.chezmoiscripts/*.tmpl` | OS-conditional package installs |

### What stays static

| File | Why |
|------|-----|
| `dot_tmux.conf` | Same everywhere |
| `dot_config/starship.toml` | Same everywhere |
| `dot_config/mise/config.toml` | Same tools on all machines |
| `dot_claude/CLAUDE.md` | Same agent instructions everywhere |
| `dot_claude/hooks/executable_notify.sh` | Handles missing NTFY_TOPIC gracefully |
| `dot_claude/executable_statusline.sh` | Same everywhere |
| `dot_aliases` | Same everywhere |

## mise Config

```toml
[tools]
node = "lts"
python = "3.12"

[settings]
idiomatic_version_file_enable_tools = ["node", "python"]
```

mise manages language runtimes only. CLI tools (jq, ripgrep, bat, fd, fzf, delta, zoxide) stay in brew/apt.

## Secrets

1. 1Password service account token prompted during `chezmoi init`
2. Token saved to `~/.config/dotfiles/.env` by chezmoi
3. `run_once_after_cache-secrets.sh.tmpl` fetches secrets from 1Password if token is set
4. Secrets cached to `~/.config/dotfiles/secrets.sh` (NTFY_TOPIC, OPENROUTER_API_KEY)
5. `dot_zshrc.tmpl` sources both `.env` and `secrets.sh` if present

No encrypted files in the repo. Secrets never committed.

## Migration Path

1. Rename files to chezmoi conventions (`zsh/zshrc` → `dot_zshrc.tmpl`, etc.)
2. Convert `bootstrap.sh` logic into `.chezmoiscripts/` templates
3. Move repo from `~/sanjeev/dotfiles` to `~/dotfiles`
4. Remove `bootstrap.sh` (replaced by chezmoi scripts)
5. Test on Mac, then test on a Linux VM
6. Git history preserved throughout

## Two CLAUDE.md Files

| File | Location | Purpose |
|------|----------|---------|
| `CLAUDE.md` (repo root) | Not deployed | Instructions for agents working on the dotfiles repo itself |
| `dot_claude/CLAUDE.md` | Deployed to `~/.claude/CLAUDE.md` | Global everyday Claude Code instructions |

## References

- [chezmoi docs](https://www.chezmoi.io/)
- [mise docs](https://mise.jdx.dev/)
- [joelazar/dotfiles](https://github.com/joelazar/dotfiles) — multi-agent chezmoi setup
- [shunk031/dotfiles](https://github.com/shunk031/dotfiles) — chezmoi + mise + BATS tests
- [Adirelle's gist](https://gist.github.com/Adirelle/41b9a2309dc5fe24bf02471f906c9042) — canonical mise + chezmoi pattern
- [Sync Claude Code with chezmoi](https://www.arun.blog/sync-claude-code-with-chezmoi-and-age/)
