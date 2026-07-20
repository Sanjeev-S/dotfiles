# Tailscale Dev-Box Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Mac mini (`mac-dev`) and `dgx-spark` reachable over the tailnet with one-command connect aliases, everything reproducible from this repo except the per-device `tailscale up` sign-in.

**Architecture:** Spec is `docs/plans/2026-07-20-tailscale-dev-box-access-design.md`. Install-layer changes go in `.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl`, service-layer (daemons, Remote Login) in `.chezmoiscripts/run_once_after_05-configure-dev-server.sh.tmpl`, access config in `private_dot_ssh/config` + `dot_aliases.tmpl`, runbooks in `README.md`.

**Tech Stack:** chezmoi Go templates, bash, Homebrew, Tailscale (open-source `tailscaled` on mac-dev per ADR 0004; GUI cask on mac-personal), Eternal Terminal.

## Global Constraints

- No tailnet credential in the repo, ever. Auth is a manual `tailscale up` per device.
- All scripts idempotent: guard with `command -v`, file-existence, or state checks before mutating.
- Per-machine differences only via `{{ .machine_type }}` gates (`mac-personal`, `mac-dev`, `linux-dev`, `dgx-spark`).
- Vocabulary per `CONTEXT.md`: "machine type" (not profile), "dev box" (not agent box/server).
- This repo root IS the chezmoi source dir; deployed files use chezmoi naming (`dot_`, `private_`, `.tmpl`).

**Template render check used by every task** (chezmoi has no data-override flag, so use a scratch config per machine type; scratchpad dir per session env):

```bash
SCRATCH=/private/tmp/claude-501/-Users-sanjeevsuresh-dotfiles/2b5c4a6a-fbdb-4a86-aea3-9bc755606b20/scratchpad
render() {  # render <machine_type> <template-file>
  printf 'sourceDir = "%s"\n[data]\nmachine_type = "%s"\nop_token = ""\nemail = "x"\n' \
    "$HOME/dotfiles" "$1" > "$SCRATCH/cm-$1.toml"
  chezmoi --config "$SCRATCH/cm-$1.toml" execute-template < "$2"
}
```

---

### Task 1: Install-layer — Tailscale on macs, et on dgx-spark

**Files:**
- Modify: `.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl:4-13` (darwin brew block) and `:33` (et gate)

**Interfaces:**
- Produces: `mac-dev` boxes have `tailscale`/`tailscaled` binaries at `$(brew --prefix)/bin/`; `dgx-spark` has the `et` apt package. Task 2's daemon registration depends on both.

- [ ] **Step 1: Add machine-type-gated Tailscale installs to the darwin block**

In `.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl`, after the `brew install --cask 1password-cli` line (line 12), insert:

```
{{ if eq .machine_type "mac-dev" -}}
# Open-source tailscaled as a boot-time system daemon — deliberately NOT the GUI
# app, which only runs inside a logged-in user session. Registration happens in
# the dev-server script; auth stays a manual `tailscale up`. See ADR 0004.
brew install tailscale
{{ else -}}
# GUI app for the interactive laptop. --adopt takes over a hand-installed copy.
brew install --cask --adopt tailscale-app
{{ end -}}
```

- [ ] **Step 2: Widen the et install gate to include dgx-spark**

Same file, line 33: change

```
{{ if eq .machine_type "linux-dev" -}}
```

to

```
{{ if or (eq .machine_type "linux-dev") (eq .machine_type "dgx-spark") -}}
```

(Today `dgx-spark` never installs `et` at all — the connect aliases in Task 3 would silently fail without this.)

- [ ] **Step 3: Verify all four renders are valid bash and gate correctly**

Using the `render` helper from Global Constraints:

```bash
F=.chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl
for t in mac-personal mac-dev linux-dev dgx-spark; do render "$t" "$F" | bash -n || echo "FAIL $t"; done
render mac-dev "$F" | grep -c "brew install tailscale"        # expect 1
render mac-personal "$F" | grep -c "cask --adopt tailscale-app"  # expect 1
render mac-dev "$F" | grep -c "tailscale-app"                 # expect 0
render dgx-spark "$F" | grep -c "apt-get install -y et"       # expect 1
render linux-dev "$F" | grep -c "apt-get install -y et"       # expect 1
```

Expected: no `bash -n` errors, counts as annotated (`grep -c` returning 0 exits 1 — that's the pass condition for the third check).

- [ ] **Step 4: Commit**

```bash
git add .chezmoiscripts/run_onchange_before_02-install-packages.sh.tmpl
git commit -m "feat(install): tailscale for mac machine types, et for dgx-spark"
```

---

### Task 2: Service-layer — daemon registration, Remote Login, et daemon

**Files:**
- Modify: `.chezmoiscripts/run_once_after_05-configure-dev-server.sh.tmpl` (mac-dev branch lines 4-12, dgx-spark branch lines 18-33)

**Interfaces:**
- Consumes: binaries installed by Task 1 (`tailscaled` via brew on mac-dev, `et` apt package on dgx-spark).
- Produces: on mac-dev, `/Library/LaunchDaemons/com.tailscale.tailscaled.plist` loaded at boot and sshd listening; on dgx-spark, `et` systemd unit enabled. Task 3's ssh config and aliases depend on these.
- Note: `run_once_` scripts re-run when their content hash changes, so editing this file makes chezmoi re-run it on the already-bootstrapped mini — that is the intended delivery mechanism.

- [ ] **Step 1: Extend the mac-dev branch**

In the `{{ if and (eq .chezmoi.os "darwin") (eq .machine_type "mac-dev") -}}` branch, after the `sudo brew services start et` line, add:

```bash
echo "==> Registering Tailscale system daemon..."
if [ ! -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist ]; then
  sudo "$(brew --prefix)/bin/tailscaled" install-system-daemon
fi

echo "==> Enabling Remote Login (sshd)..."
# systemsetup may need Full Disk Access for the calling terminal on recent
# macOS; if this errors, flip it in System Settings > General > Sharing.
if ! sudo systemsetup -getremotelogin | grep -q ": On"; then
  sudo systemsetup -setremotelogin on
fi
```

- [ ] **Step 2: Extend the dgx-spark branch**

In the `{{ else if and (eq .chezmoi.os "linux") (eq .machine_type "dgx-spark") -}}` branch, after the Wi-Fi `nmcli` block, add:

```bash
echo "==> Starting Eternal Terminal daemon..."
sudo systemctl enable --now et
```

- [ ] **Step 3: Verify renders**

```bash
F=.chezmoiscripts/run_once_after_05-configure-dev-server.sh.tmpl
for t in mac-personal mac-dev linux-dev dgx-spark; do render "$t" "$F" | bash -n || echo "FAIL $t"; done
render mac-dev "$F" | grep -c "install-system-daemon"   # expect 1
render mac-dev "$F" | grep -c "setremotelogin"          # expect 1 (set line only; the guard uses -getremotelogin)
render dgx-spark "$F" | grep -c "enable --now et"       # expect 1
render mac-personal "$F" | grep -c "tailscaled"         # expect 0 (exit 1 = pass)
```

Expected: no `bash -n` errors; counts as annotated.

- [ ] **Step 4: Commit**

```bash
git add .chezmoiscripts/run_once_after_05-configure-dev-server.sh.tmpl
git commit -m "feat(dev-server): tailscaled system daemon + Remote Login on mac-dev, et daemon on dgx-spark"
```

---

### Task 3: Access config — MagicDNS ssh names + connect/herdr aliases

**Files:**
- Modify: `private_dot_ssh/config:4-6` (macmini stanza)
- Modify: `dot_aliases.tmpl:8` (macmini-connect) and after line 18 (herdr block)

**Interfaces:**
- Consumes: services from Task 2; tailnet device names `macmini` (set at re-auth, runbook in Task 4) and `dgx-spark` (existing README flow).
- Produces: `ssh macmini`, `ssh dgx-spark`, and shell commands `macmini-connect`, `dgx-spark-connect`, `dgx-spark-herdr`, `dgx-spark-herdr-native` working from any tailnet device.

- [ ] **Step 1: Point the macmini ssh stanza at its MagicDNS name**

In `private_dot_ssh/config` change:

```
Host macmini
    HostName sanjeevs-mac-mini
    User sanjeevsuresh
```

to:

```
Host macmini
    HostName macmini
    User sanjeevsuresh
```

(No tunnel entries for tailnet boxes — the tailnet is flat; `dgx-spark` stanza is already correct.)

- [ ] **Step 2: Retarget macmini-connect and add the dgx-spark aliases**

In `dot_aliases.tmpl` change line 8:

```
alias macmini-connect="et sanjeevsuresh@sanjeevs-mac-mini -c 'tmux -CC new-session -A -s main'"
```

to:

```
alias macmini-connect="et sanjeevsuresh@macmini -c 'tmux -CC new-session -A -s main'"
alias dgx-spark-connect="et sanjeevsuresh@dgx-spark -c 'tmux -CC new-session -A -s main'"
```

Then, after `alias hetzner-16g-herdr-native="herdr --remote hetzner-16g"` (line 18), add:

```
# Spark herdr needs no tunnel: tailnet boxes get flat network access.
alias dgx-spark-herdr="et sanjeevsuresh@dgx-spark -c 'herdr'"
alias dgx-spark-herdr-native="herdr --remote dgx-spark"
```

(Plain aliases, not functions — the hetzner herdr *function* exists only to manage its tunnel's background pid.)

- [ ] **Step 3: Verify**

```bash
for t in mac-personal mac-dev linux-dev dgx-spark; do render "$t" dot_aliases.tmpl | zsh -n || echo "FAIL $t"; done
render mac-personal dot_aliases.tmpl | grep -c "dgx-spark-"   # expect 3
grep -c "sanjeevs-mac-mini" private_dot_ssh/config dot_aliases.tmpl  # expect 0 in both (exit 1 = pass)
```

- [ ] **Step 4: Commit**

```bash
git add private_dot_ssh/config dot_aliases.tmpl
git commit -m "feat(access): MagicDNS ssh names, dgx-spark connect + herdr aliases"
```

---

### Task 4: README — Mac mini runbook, wording, inventory row

**Files:**
- Modify: `README.md:103-136`

**Interfaces:**
- Consumes: everything above; the runbook narrates the manual rollout of Tasks 1-3 on the mini.

- [ ] **Step 1: Insert a Mac mini section before the DGX Spark section (README.md:105)**

```markdown
## Mac mini (mac-dev)

Tailscale runs as the open-source `tailscaled` system daemon — not the GUI app —
so the box is on the tailnet from boot with nobody logged in (ADR 0004).
Bring-up or recovery:

    # On the mini (first time: remove any GUI Tailscale.app after signing out of it)
    chezmoi update        # installs tailscale formula, registers daemon,
                          # enables Remote Login, starts et
    sudo tailscale up --hostname=macmini

    # From any signed-in device
    ssh macmini
    macmini-connect       # et + tmux -CC

If `systemsetup -setremotelogin on` errors (Full Disk Access), enable Remote
Login in System Settings > General > Sharing instead.
```

- [ ] **Step 2: Reword the last DGX paragraph to CONTEXT.md vocabulary**

Change (README.md:133-136):

```
The `dgx-spark` profile treats the machine as a disposable agent box: it grants the
```

to:

```
The `dgx-spark` machine type treats the box's contents as disposable: it grants the
```

(Rest of the sentence unchanged. "machine type", not "profile"; no "agent box".)

- [ ] **Step 3: Add Tailscale to the What's included table**

After the `| Eternal Terminal | ... |` row (README.md:52), add:

```
| Tailscale | Mesh VPN reaching the dev boxes (manual sign-in per device) | Both |
```

- [ ] **Step 4: Verify and commit**

```bash
grep -c "disposable agent box" README.md   # expect 0 (exit 1 = pass)
grep -c "hostname=macmini" README.md       # expect 1
git add README.md
git commit -m "docs(readme): mac mini runbook, tailscale row, dev-box wording"
```

---

### Task 5: Rollout on the Air + manual machine steps

**Files:** none (execution only)

- [ ] **Step 1: Apply on this machine (mac-personal)**

```bash
chezmoi diff          # review: expect ssh config + aliases changes, cask install
chezmoi apply
```

Expected: `brew install --cask --adopt tailscale-app` adopts the existing app (no second copy); `~/.ssh/config` and `~/.aliases` update.

- [ ] **Step 2: Verify locally**

```bash
grep -A1 "Host macmini" ~/.ssh/config     # HostName macmini
zsh -ic 'type dgx-spark-connect'          # alias defined
tailscale status                          # Air still signed in
```

- [ ] **Step 3: Manual steps (user, on each box — not agent-executable)**

1. **Mini:** sign out of + quit GUI Tailscale app, delete `/Applications/Tailscale.app`, then run the README Mac mini runbook. Old `sanjeevs-mac-mini` device can be removed in the admin console after `macmini` appears.
2. **Spark:** existing README DGX flow (`sudo tailscale up --ssh --hostname=dgx-spark` after `chezmoi update` picks up et).
3. **Acceptance (from the Air, off home LAN if possible):** `tailscale status` shows both boxes online; `ssh macmini`, `ssh dgx-spark`, `macmini-connect`, `dgx-spark-connect` all work; reboot the mini to the login screen and confirm it returns to the tailnet.
