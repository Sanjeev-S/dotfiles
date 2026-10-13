# Dotfiles

Cross-platform (macOS + Linux) dotfiles managed by chezmoi with mise for language runtimes and 1Password for secrets.

Canonical vocabulary lives in [CONTEXT.md](CONTEXT.md) — notably "machine type" (not profile) and "dev box".

## Repo Layout

This repo root IS the chezmoi source directory. Files use chezmoi naming conventions:

| Prefix/Suffix | Effect |
|---------------|--------|
| `dot_` | Deploys as `.filename` in `$HOME` |
| `executable_` | Sets chmod +x |
| `private_` | Sets chmod 600/700 |
| `.tmpl` | Rendered as Go template |

### Key directories

| Source | Deploys to | Purpose |
|--------|-----------|---------|
| `dot_claude/` | `~/.claude/` | Claude Code config, hooks, statusline |
| `dot_codex/` | `~/.codex/` | Codex CLI config |
| `dot_gemini/` | `~/.gemini/` | Antigravity CLI (`agy`) instructions |
| `dot_local/bin/` | `~/.local/bin/` | User scripts (`secrets-refresh`, `dotup`, `sync-skills`) |
| `dot_config/mise/` | `~/.config/mise/` | mise tool versions (Node, Python) |
| `dot_config/starship.toml` | `~/.config/starship.toml` | Prompt theme |
| `dot_config/karabiner/` | `~/.config/karabiner/` | Karabiner-Elements keymaps (macOS only) |
| `.chezmoiscripts/` | (not deployed) | Install scripts run by chezmoi |
| `docs/` | (not deployed) | Plans, brainstorms, ADRs |

## Conventions

- **chezmoi naming.** All deployed files use chezmoi prefixes (`dot_`, `executable_`, `private_`) and `.tmpl` suffix for templates.
- **Templates for OS differences.** Use `{{ .chezmoi.os }}` and `{{ .machine_type }}` in `.tmpl` files.
- **One directory per agent.** Each AI agent gets its own `dot_` directory.
- **Scripts in .chezmoiscripts/.** Package installs, tool setup, and post-apply actions.
- **Idempotent.** Scripts use `run_once_` or `run_onchange_` prefixes. Guard checks (`command -v`, `[ -d ... ]`).
- **1Password for secrets.** No encrypted files in repo. Secrets fetched at apply time.

## Adding a New Tool

1. Add config file with chezmoi naming (e.g., `dot_config/toolname/config.toml`)
2. Add install commands to `.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl`
3. Run `chezmoi apply` to test

## Adding a New Agent

1. Create `dot_agentname/` directory
2. Add config files inside it
3. Add install script to `.chezmoiscripts/` if needed
4. Update `.chezmoiignore` if any files are OS-specific

## Bootstrap

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply Sanjeev-S
```

## Update

```bash
chezmoi apply
```

## Cloud Agent

Chezmoi and zsh are on the default PATH. The checked-in test calls the real `chezmoi` binary for template rendering:

```bash
python3 -B -m unittest discover -s docs/tests -v
```

Render one template without writing `$HOME` or prompting for a machine type:

```bash
chezmoi execute-template --override-data '{"machine_type":"linux-dev"}' < dot_aliases.tmpl
```

`chezmoi apply` and `chezmoi init --apply` prompt for a machine type and a 1Password service account token, then install machine packages and fetch secrets. Use `execute-template` while editing this repo.
