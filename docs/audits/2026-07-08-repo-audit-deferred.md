# 2026-07-08 repo audit — deferred findings

A full-repo audit surfaced 18 findings; 14 were fixed in the commit run of
2026-07-12. These four were deliberately deferred, not rejected.

## 1. Claude Code notification hooks never fire (deferred: cross-agent topic)

`dot_claude/settings.json.tmpl` registers `Stop|AskUserQuestion` as a
`PostToolUse` matcher, but `Stop` is a top-level hook event and
`AskUserQuestion` isn't a `PostToolUse` matcher — so no ntfy notification has
ever been sent by this config, and the README's Notifications section
describes behavior that doesn't happen. Verified against
https://code.claude.com/docs/en/hooks-guide.

Sketch of the fix when picked up: top-level `Stop` event ("Claude finished")
plus `Notification` event (`idle_prompt` / `permission_prompt` matchers,
"needs input"); `notify.sh` must switch on `hook_event_name` (Stop payloads
have no `tool_name`) and read stdin with `$(cat)` instead of `read -r`. Keep
the `is_user_watching` gate. Deferred because notification handling should be
designed once across all agents (Claude, Codex, agy), not patched per-agent.

## 2. Machine-type gating for Codex/agy full-trust settings

The `agy --dangerously-skip-permissions` alias (`dot_aliases.tmpl`) and
Codex's `approval_policy = "never"` + `danger-full-access`
(`dot_codex/config.toml.tmpl`) are wrapped in conditionals listing all three
machine types — currently gating nothing. Read as an allowlist it's
fail-closed for future machine types; but note the asymmetry: Claude Code is
more cautious on mac-personal while Codex/agy are full-trust everywhere.
Decide alongside the notifications/agent-posture pass: keep-with-comment,
delete, or pull mac-personal out.

## 3. Unguarded `claude plugin install` in bootstrap

`run_once_after_03-install-claude.sh.tmpl` runs two `claude plugin install`
commands without `|| true` under `set -e`; a transient failure aborts the
whole first `chezmoi apply` on a fresh machine. Fix is trivial (cushion like
the adjacent marketplace-add lines); dotup's daily `plugin update` failure
banner remains the loud signal.

## 4. shellcheck adoption

No linting for ~15 shell scripts; this audit's two logic bugs (always-true
`run_step`, failure-proof `curl | bash` pipe) are exactly shellcheck's
territory. Proposal when picked up: add `shellcheck` to the brew/apt package
lists and one AGENTS.md line ("run shellcheck on any shell script you
touch"), plus a one-time sweep of the repo.
