# Herdr trial — evaluation plan (2026-07-12)

**Question:** Does herdr fix "I lose track of which parallel agents are blocked on input"?
Decision date: ~2026-07-26 (2 weeks).

## Setup (done)

- herdr 0.7.3 installed locally (brew) and on hetzner-16g (`/root/.local/bin/herdr`, on PATH).
- Trial aliases in `~/.aliases`: `hetzner-16g-herdr` (et path) and `hetzner-16g-herdr-native` (`herdr --remote`).
- tmux untouched; `hetzner-16g-connect` still works as fallback. No chezmoi install-script changes until promotion.
- Config: `~/.config/herdr/config.toml` (defaults during trial).

## Decisions made (grilling 2026-07-12)

1. Architecture: herdr runs **on** the remote box (not local dashboard over SSH panes).
2. Notifications: dashboard-first; ntfy not relied on. notify.sh flagged as likely dead code either way.
3. Scope: local + hetzner-16g simultaneously.
4. tmux full-replacement vs coexist: **deferred** until trial data exists.

## Pass criteria

1. State detection accurate for Claude Code **and** Codex — no false idle-while-blocked.
2. Blocked-agent alert visible/audible at the Mac when attached to the remote box (`herdr notification` / sound).
3. Survives et or ssh disconnect, reattach, and Mac sleep without losing agents.
4. Mouse, clipboard (OSC 52), scrollback tolerable vs `tmux -CC` native windows.

Also compare: `--remote` native attach vs et path — which feels better day-to-day?

## On pass

Add herdr to `.chezmoiscripts` installs, manage `dot_config/herdr/`, rewrite `*-connect` aliases, decide tmux fate (deferred item), delete/gut `dot_claude/hooks/executable_notify.sh`.

## On fail

Delete trial aliases from `dot_aliases.tmpl`, `brew uninstall herdr`, remove remote binary, keep this doc as the record.
