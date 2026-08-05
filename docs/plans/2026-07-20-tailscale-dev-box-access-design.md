# Tailscale dev-box access design

2026-07-20. Bring the owned dev boxes (Mac mini `mac-dev`, `dgx-spark`) onto the
tailnet with the same one-command access the Hetzner box has, and make every
piece of that setup reproducible from this repo except the tailnet sign-in.

## Problem

The Mac mini shows disconnected in Tailscale and refuses ssh. Root causes: the
hand-installed GUI Tailscale app only runs inside a logged-in user session (a
reboot to the login screen takes the tailnet down), nothing in the repo enables
Remote Login (macOS ships with sshd off), and none of the mac machine types
install Tailscale at all. The `dgx-spark` type installs Tailscale but never
enables the `et` daemon, so the connect-alias pattern cannot reach it. The ssh
config points `macmini` at a LAN-only hostname.

## Decisions

1. **Mac mini runs the open-source tailscaled system daemon** (brew formula +
   `sudo tailscaled install-system-daemon`), not the GUI app. Boot-time
   connectivity with no user session. See ADR 0004.
2. **Every tailnet machine type gets Tailscale installed by the repo.**
   `mac-personal`: `brew install --cask --adopt tailscale-app` (adopts the
   hand-installed copy on the Air). `mac-dev`: formula + daemon. `dgx-spark`:
   existing curl install, unchanged. `linux-dev` (Hetzner) installs no
   Tailscale, per Non-goals.
3. **Auth stays manual on every device** (existing policy: no tailnet
   credential in the repo). Each box joins via an interactive `tailscale up`.
4. **`mac-dev` enables Remote Login** on all interfaces:
   `sudo systemsetup -setremotelogin on` in the dev-server script. Caveat: on
   recent macOS, `systemsetup` may require the invoking terminal to have Full
   Disk Access; the runbook notes the System Settings fallback.
5. **`dgx-spark` enables the `et` daemon** (`systemctl enable --now et`),
   matching `linux-dev`. Tailscale SSH (already in its bring-up) remains a
   fallback path.
6. **Naming collapses to the ssh alias.** The mini re-joins as
   `--hostname=macmini`; ssh config uses MagicDNS short names (`macmini`,
   `dgx-spark`). Assumes MagicDNS on; network ACLs allow-all. Tailscale SSH
   additionally needs an `ssh` policy `accept` rule (decision 9). LAN fallback
   for the bare name is dropped — physical access covers that failure mode.
7. **No tunnel entries for tailnet boxes.** The tailnet is flat; localhost-bound
   services use `tailscale serve` or an ad-hoc `ssh -L` when the need actually
   arises. Standing `LocalForward` lists remain a Hetzner (public-internet)
   pattern only.
8. **Aliases:** retarget `macmini-connect` to `macmini`; add
   `dgx-spark-connect`, `dgx-spark-herdr` (et-wrapped, no tunnel), and
   `dgx-spark-herdr-native`, mirroring the Hetzner pair.
9. **Durable, prompt-free access is policy, not defaults** (added 2026-08-04).
   Two account-level settings make "ssh anytime, no re-auth" true: per-device
   *disable key expiry* — otherwise node keys force a browser re-auth every
   180 days, the original mini failure on a timer — and an `ssh` section
   `accept` rule in the tailnet policy for member→self. A missing `ssh`
   section denies Tailscale SSH outright; the default rule's `check` action
   forces a browser re-auth every 12h and breaks the non-interactive et
   bootstrap. Both dev boxes run Tailscale SSH (`up --ssh`, supported on the
   mini's tailscaled variant): one model over the tailnet — device identity,
   no per-client keys. Server-side ssh trust is additionally repo-managed:
   `.ssh/authorized_keys` deploys to every machine (public keys are not
   secrets) as the LAN/recovery path; only the client `config` stays
   mac-personal.

## Changes by file

- `.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl` — darwin
  section: install Tailscale per machine type (cask for `mac-personal`,
  formula for `mac-dev`).
- `.chezmoiscripts/run_once_after_05-configure-dev-server.sh.tmpl` —
  `mac-dev` branch: register tailscaled system daemon (idempotence guard on
  the LaunchDaemon plist), enable Remote Login. `dgx-spark` branch: enable
  `et` daemon. Content change makes chezmoi re-run the script on the mini.
- `private_dot_ssh/config` — `macmini` HostName becomes `macmini`.
- `dot_aliases.tmpl` — retarget `macmini-connect`; add the three dgx-spark
  aliases.
- `README.md` — new mac-dev runbook (below); reword "disposable agent box"
  to dev-box vocabulary per CONTEXT.md.

## Runbooks (README content)

**Mac mini recovery/bring-up:** sign out of and quit the GUI Tailscale app,
delete `/Applications/Tailscale.app` → `chezmoi update` (installs formula,
registers daemon, enables Remote Login, restarts et) →
`sudo tailscale up --ssh --hostname=macmini` and authenticate in the browser →
from the Air: `ssh macmini`, then `macmini-connect`.

**dgx-spark:** unchanged existing flow (`tailscale up --ssh
--hostname=dgx-spark`); et now works after `chezmoi apply`.

**Air:** already signed in; nothing to do. On a rebuild the cask preinstalls
the app and sign-in is the only manual step.

## Verification

From the Air: `tailscale status` lists `macmini` and `dgx-spark` online;
`ssh macmini` and `ssh dgx-spark` succeed off-LAN; `macmini-connect` and
`dgx-spark-connect` open tmux -CC sessions. Reboot the mini to the login
screen and confirm it reappears on the tailnet without anyone logging in.

## Non-goals

Hetzner boxes stay off the tailnet and keep their tunnel entries. No reusable
tailnet auth keys (pre-auth credentials) in the repo — sign-in stays
interactive per device. No herdr verdict — aliases only.
