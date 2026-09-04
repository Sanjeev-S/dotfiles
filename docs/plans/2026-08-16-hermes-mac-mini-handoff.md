# Hermes Agent on the Mac mini — handoff for Claude Code (run on the Air)

Prepared 2026-08-16 by a Cowork session that read `~/dotfiles` and the current
Hermes docs/source. Cowork could not type into a terminal, so execution moves
to Claude Code on the Air, where `ssh macmini` works natively.

**Operator prompt for Claude Code:** `cd ~/dotfiles && claude`, then
"Read docs/plans/2026-08-16-hermes-mac-mini-handoff.md and execute it. Ask me only
at the two marked STOP points." (This file is untracked — commit or delete later.)

## 1. Context (from the dotfiles repo)

- Fleet: Air = `mac-personal` (this machine). Dev boxes: Mac mini = `mac-dev`
  (tailnet name `macmini`, user `sanjeevsuresh`), `dgx-spark`, Hetzner
  `linux-dev` (root, public IP, not on tailnet).
- Reach the mini: `ssh macmini` — Tailscale SSH (`tailscale up --ssh`,
  policy `accept` member→self, no per-client keys). Alias `macmini-connect`
  = `et … tmux -CC`. Non-interactive `ssh macmini 'cmd'` gets PATH from
  `.zshenv` (`~/.local/bin`, mise shims, brew).
- On the mini: chezmoi-managed; Claude Code + Codex CLI installed by dotfiles;
  `op` (1Password CLI) installed; SA token in `~/.config/dotfiles/.env`
  (`OP_SERVICE_ACCOUNT_TOKEN`); cached secrets in `~/.config/dotfiles/secrets.sh`
  (`OPENROUTER_API_KEY`, `HF_TOKEN`, …). `dotup` LaunchAgent runs hourly.
- macOS `op` gotcha (README): always export
  `OP_BIOMETRIC_UNLOCK_ENABLED=false OP_LOAD_DESKTOP_APP_SETTINGS=false OP_CACHE=false`
  before `op read`, or it fires TCC prompts.
- Vault convention: `op://Dotfiles/<item>/credential`.

## 2. Decisions already made with Sanjeev

| Topic | Decision |
|---|---|
| Access | Claude Code on the Air → `ssh macmini` |
| Repro | **One-off install on the mini.** Do not add chezmoi scripts / edit the dotfiles repo (beyond this doc). |
| Provider | **ChatGPT/Codex OAuth** (`openai-codex`), default model `gpt-5.6-sol` (same as his Codex config). Anthropic OAuth ruled out: Anthropic's Claude Code legal page forbids third-party tools routing through Free/Pro/Max credentials. |
| Gateway | Yes — launchd service, platforms **Telegram + Discord + Slack**. Sanjeev creates the bots and stores tokens in 1Password `Dotfiles`; wire them from the mini via `op read`. |
| Extras | `--skip-computer-use` (cua-driver = GUI app in /Applications; pointless headless). Keep Playwright/browser (no sudo needed on macOS). |

## 3. Preflight (all from the Air, ~1 min)

```bash
ssh macmini 'sw_vers; uname -m; git --version; brew --version | head -1; command -v op claude codex; ls -la ~/.codex/auth.json 2>&1; test -f ~/.config/dotfiles/.env && echo op-env-ok; command -v hermes || echo no-hermes; ls -d ~/.hermes 2>/dev/null || echo no-hermes-home; launchctl managername; df -h / | tail -1'
```

Expect: arm64, git+brew present, `op` present, no `hermes` yet. Note
`launchctl managername` (Aqua vs Background) — see §8 caveat 1.

## 4. Install (one-off, per-user layout: code `~/.hermes/hermes-agent/`, binary `~/.local/bin/hermes`)

Takes 5–10 min (uv, Python 3.11, Node 26 if system node < 26, ripgrep/ffmpeg via
brew, Playwright Chromium). Run detached and poll:

```bash
ssh macmini 'nohup bash -c "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-computer-use" > ~/hermes-install.log 2>&1 &'
# poll every ~60s until the summary block appears / process exits
ssh macmini 'tail -n 25 ~/hermes-install.log; pgrep -fl "install.sh|uv |npm " >/dev/null && echo STILL-RUNNING || echo DONE'
ssh macmini 'hermes --version && hermes doctor'
```

Notes: `--skip-setup` avoids the TTY wizard; `~/.local/bin` is already on
PATH so the installer won't touch `.zshrc` (chezmoi owns it anyway). If
`brew install ffmpeg/ripgrep` prompts or fails, run it directly with `ssh -t`.

## 5. Provider: ChatGPT / Codex OAuth (device code, no TTY needed)

Hermes recommends its own OAuth session rather than importing `~/.codex/auth.json`
(refresh tokens are single-use; sharing them with Codex CLI causes conflicts).

```bash
ssh macmini 'mkdir -p ~/.hermes/logs; nohup hermes auth add openai-codex </dev/null > ~/.hermes/logs/codex-login.log 2>&1 &'
sleep 5; ssh macmini 'cat ~/.hermes/logs/codex-login.log'
```

**STOP 1 → show Sanjeev the printed URL (`https://auth.openai.com/codex/device`)
and the code.** He completes it in a browser (15-min window). Then poll the log
until `Added openai-codex OAuth credential #1`.

```bash
ssh macmini 'hermes config set model.provider openai-codex && hermes config set model.default gpt-5.6-sol && hermes config get model && hermes auth status openai-codex'
ssh macmini 'hermes chat -Q -q "Reply with exactly: hermes-ok on $(hostname -s)"'
```

If `config set model.default` is rejected, `hermes config edit` is a TUI — instead
edit `~/.hermes/config.yaml` with sed/python (`model: {provider: openai-codex,
default: gpt-5.6-sol}`); the docs accept `default:` or `model:` as the key.

## 6. Gateway service (launchd) + platforms

Install the service now even with zero platforms — Hermes documents that as a
supported degraded mode (cron scheduler runs; adapters start as tokens appear):

```bash
ssh macmini 'hermes gateway install && sleep 3 && hermes gateway status; tail -n 20 ~/.hermes/logs/gateway.log'
```

Plist: `~/Library/LaunchAgents/ai.hermes.gateway.plist` (captures PATH,
VIRTUAL_ENV, HERMES_HOME at install time; re-run `hermes gateway install`
after installing new CLI tools).

**STOP 2 → ask Sanjeev which tokens are already in 1Password.** Expected items
(vault `Dotfiles`, field `credential`):
`telegram-bot-token`, `discord-bot-token`, `slack-bot-token` (xoxb-),
`slack-app-token` (xapp-). Bot creation checklist for him:

- Telegram: @BotFather `/newbot` → token. (Optional: `/setprivacy` Disable for group use.)
- Discord: Developer Portal → New Application → Bot → **Reset Token**; enable
  **Message Content Intent** and **Server Members Intent**; OAuth2 URL
  Generator scopes `bot` + `applications.commands`, invite to his server.
- Slack: api.slack.com/apps → New App → **Socket Mode ON** (creates xapp token,
  scope `connections:write`); Bot Token Scopes: `chat:write app_mentions:read
  channels:history channels:read groups:history im:history im:read im:write
  mpim:history mpim:read users:read files:read files:write`; Event
  Subscriptions bot events: `message.im message.channels app_mention` (+
  `message.groups` for private channels); App Home → **Messages Tab** on +
  allow DMs; Install to workspace → xoxb token. Reinstall after any scope change.

Wire each available token (values never touch the shell history — command
substitution only; `hermes config set` routes secrets to `~/.hermes/.env`, mode 600):

```bash
ssh macmini 'set -e; source ~/.config/dotfiles/.env
export OP_BIOMETRIC_UNLOCK_ENABLED=false OP_LOAD_DESKTOP_APP_SETTINGS=false OP_CACHE=false
r(){ op read "op://Dotfiles/$1/credential" --no-newline; }
hermes config set TELEGRAM_BOT_TOKEN "$(r telegram-bot-token)"
hermes config set DISCORD_BOT_TOKEN  "$(r discord-bot-token)"
hermes config set SLACK_BOT_TOKEN    "$(r slack-bot-token)"
hermes config set SLACK_APP_TOKEN    "$(r slack-app-token)"
hermes gateway restart; sleep 5; hermes gateway status; tail -n 30 ~/.hermes/logs/gateway.log'
```

(Skip lines for items that don't exist yet; re-run later. Any `op read` failure
= item name/field mismatch — `op item list --vault Dotfiles` to check.)

Access control: use **DM pairing** instead of collecting user IDs — Sanjeev DMs
each bot, gets a code, then on the mini `hermes pairing approve telegram|discord|slack <CODE>`
(`hermes pairing list` to see pending). Alternative: `hermes config set
TELEGRAM_ALLOWED_USERS <id>` / `DISCORD_ALLOWED_USERS` / `SLACK_ALLOWED_USERS`.
Optionally set `*_HOME_CHANNEL` for cron/proactive messages.

## 7. Verify (definition of done)

- `hermes --version`, `hermes doctor` clean, `hermes status`.
- `hermes chat -Q -q "…"` answers via `openai-codex` / `gpt-5.6-sol`.
- `hermes gateway status` running; `~/.hermes/logs/gateway.log` shows each
  configured adapter connected; a DM to each bot gets a reply after pairing.
- Fresh non-interactive shell finds it: `ssh macmini 'command -v hermes'`.
- Nothing changed in `~/dotfiles` on the mini (`ssh macmini 'cd ~/dotfiles && git status --short'`) other than this doc if it synced.

## 8. Caveats / gotchas

1. **LaunchAgent ≠ boot-time.** `ai.hermes.gateway` (and the existing
   `com.sanjeev.dotup`) live in the per-user launchd domain and start only when
   `sanjeevsuresh` has a session. If the mini reboots to the login screen
   (the ADR-0004 scenario), the gateway is down until a console/ssh login.
   Check: `launchctl managername` (Aqua = GUI session exists) and
   `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`.
   Fixes if needed: enable auto-login for `sanjeevsuresh` (FileVault must be
   off), or hand-roll a `/Library/LaunchDaemons` plist with `UserName` — Hermes's
   `--system` flag is Linux-only. Flag it to Sanjeev; don't decide unilaterally.
2. **Hermes updates are not in `dotup`** (one-off decision). Update manually:
   `ssh macmini 'hermes update --yes'` (auto-restarts the gateway). Offer as a
   follow-up: add `run_step hermes hermes update --yes` to `dot_local/bin/executable_dotup`.
3. **Codex OAuth is tolerated, not formally sanctioned by OpenAI**; quota semantics
   undocumented. If quota errors appear, `hermes model`-free fallback: add
   OpenRouter (`hermes config set OPENROUTER_API_KEY "$(source ~/.config/dotfiles/secrets.sh; echo $OPENROUTER_API_KEY)"`)
   and configure `fallback_providers` (docs: /user-guide/features/fallback-providers).
4. `hermes model`, `hermes setup`, `hermes gateway setup`, `hermes config edit`
   are interactive TUIs — avoid; use `hermes config set/get`, `hermes auth add`.
5. Never paste token values into chat or commit them; `~/.hermes/.env` is the
   only place they land. Log files auto-redact secrets.
6. Don't run two gateways on one Telegram token (polling conflicts).

## 9. Optional follow-ups (ask first)

- `hermes import-agent --source ~/.claude` (previews first): maps global
  instructions ("Challenge my assumptions. Be extremely concise.") + skills.
- Web dashboard over the tailnet: `hermes dashboard` (needs `uv pip install -e ".[web]"`).
- Promote to dotfiles later: `run_once_after_03d-install-hermes.sh.tmpl` gated
  `mac-dev`, `hermes update --yes` in dotup, this runbook into README.

## Sources

- Hermes install: https://hermes-agent.nousresearch.com/docs/getting-started/installation
- Providers / subscription table: https://hermes-agent.nousresearch.com/docs/integrations/providers
- Messaging + launchd service: https://hermes-agent.nousresearch.com/docs/user-guide/messaging/
- Telegram / Discord / Slack setup: …/user-guide/messaging/{telegram,discord,slack}
- CLI reference (`auth add`, `config set`, `gateway`, `pairing`, `update --yes`): https://hermes-agent.nousresearch.com/docs/reference/cli-commands
- 1Password integration (alternative to `.env`): https://hermes-agent.nousresearch.com/docs/user-guide/secrets/onepassword
- Anthropic OAuth policy: https://code.claude.com/docs/en/legal-and-compliance
- Codex model list (`gpt-5.6-sol` etc.): hermes_cli/codex_models.py in NousResearch/hermes-agent
