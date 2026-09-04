# Hermes on linux-dev: dedicated `hermes` service user, not root

The personal Hermes Agent gateway (migrated 2026-08 from the Mac mini,
`docs/plans/2026-08-16-hermes-mac-mini-handoff.md` era install) is a
Telegram-reachable daemon with terminal/file/code-execution/browser tools. On
the Hetzner box everything else runs as root (ADR 0002 accepted that for
interactively-driven Claude Code), but an always-on agent fed by a messaging
platform and the open web is a different exposure class: 2026's OpenClaw-class
incident wave (21k+ exposed instances, infostealers targeting agent config
paths within 48h) hit exactly the agent-as-root/personal-user default. Hermes
upstream is explicit — the security docs say never run the gateway as root, and
`hermes gateway install --system` on a root-only host refuses outright; their
official Docker image runs as an unprivileged user named `hermes` (uid 10000).

Decision: a dedicated unprivileged `hermes` user runs the gateway. Locked
password, no SSH keys, no sudo — the only way in is root's `runuser`/`sudo -iu`,
which is also the orchestration path (a root-side `~/.local/bin/hermes` wrapper
execs the CLI as the service user, so `ssh hetzner-16g hermes …` keeps working;
`hermes-hetzner` aliases wrap that from other machines). Supervision is the
vendor-preferred headless pattern: per-user systemd unit + `loginctl
enable-linger`, because Hermes regenerates and restarts its own unit
(`hermes update --yes`) and a root-owned system unit would need sudo for every
restart. The generic system-unit-plus-hardening pattern (`User=`,
`ProtectSystem=strict`, …) was considered and declined for now: `/root` is
already mode-700 against the service user, and fighting `hermes gateway
install`'s unit management is a standing tax. Revisit if threat model changes;
`terminal.backend: docker` is the documented next hardening rung.

The agent home gets no dotfiles. chezmoi manages the applying user's home
(root); the `hermes` account is an appliance provisioned BY root's chezmoi
scripts, never WITH its own — applying dotfiles there would re-import the
broad 1Password service-account token the split exists to isolate. Secrets
follow the scoped-SA pattern instead: a purpose-made 1Password vault holds only
what the agent may read, a service account restricted to that vault is stored
via `hermes secrets onepassword setup` (mode-600 `.env` in the agent home), and
`.env` entries are `op://` references resolved in-memory at process start —
the raw bot token never rests on disk, and revoking the SA in the 1Password
console de-fangs the agent without touching the box. Accepted trade-offs:
gateway (re)start depends on 1Password reachability; on Individual/Families
plans SA usage shares a 1,000-requests/24h account-wide cap with the machine
SAs (Hermes's `restart_loop_guard`/`respawn_storm` bound crash-loop reads).
Never run two gateways against one Telegram bot token, and never point a
second Hermes process at the same HERMES_HOME.

Follow-up recorded, not yet done: the same split on mac-dev for the family
profile (Harold) before its terminal/file/code-execution toolsets are enabled —
as `sanjeevsuresh`, those tools would read the broad SA token and every cached
secret. On macOS that means a service account + LaunchDaemon with `UserName=`
(fixes LaunchAgent≠boot from the handoff doc); desktop computer-use needs a GUI
session and is the open question there.
