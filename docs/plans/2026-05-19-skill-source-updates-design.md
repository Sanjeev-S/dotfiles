# Skill source updates — design

**Date:** 2026-05-19
**Status:** Approved

## Problem

Four external skill/plugin sources are installed once during `chezmoi apply` bootstrap and then never refreshed:

| Source | Install mechanism | Today's update story |
|---|---|---|
| `superpowers` plugin | `claude plugin install superpowers@superpowers-marketplace` | Never re-runs after first install |
| `compound-engineering` plugin | `claude plugin install compound-engineering@compound-engineering-plugin` | Never re-runs after first install |
| `gstack` git repo at `~/.claude/skills/gstack` | `git clone` + `./setup` build | `git pull` only re-runs if the install script's content hash changes |
| `mattpocock-skills` git repo at `~/.claude/skills/mattpocock-skills` | `git clone` + symlink loop | Same staleness gap as gstack |

Concrete cost: matt's `handoff` skill landed upstream on 2026-05-13 and was invisible for four days until the install script was edited for an unrelated reason. The pattern will keep happening.

## Goal

Refresh all four sources on a predictable cadence (default: daily), with per-source failure isolation, surfacing failures via the existing `dotup` zsh banner.

## Non-goals

- Per-source cadence (everything goes on the same schedule).
- Forcing Claude Code to reload upgraded plugins (deferred activation on next Claude restart is acceptable).
- Update story for the dotfiles repo itself (already covered by `dotup` → `chezmoi update --force`).

## Design

### Architecture

```
dotup (existing, daily, 24h guard)
  ├─ chezmoi update --force          (existing)
  ├─ secrets-refresh                  (existing)
  ├─ sync-skills                      ← NEW
  ├─ claude install                   (existing)
  └─ codex install                    (existing)
```

Files changed:

| File | Change |
|---|---|
| `dot_local/bin/executable_sync-skills` | **NEW** — unified updater for all four sources |
| `.chezmoiscripts/run_once_after_03-install-claude.sh.tmpl` | Remove gstack `./setup` call and matt symlink loop; end by calling `sync-skills` |
| `dot_local/bin/executable_dotup` | Add `run_step sync-skills` between `secrets` and `claude` |

### `sync-skills` internals

Same `run_step` + `failed[]` pattern as `dotup` itself. Each sub-step is independent: a flaky git pull does not block plugin updates, and vice versa.

Step order:

1. `claude plugin marketplace update` — refresh catalogs (cheap, recommended even though `plugin update` does not strictly require it).
2. `claude plugin update superpowers@superpowers-marketplace`
3. `claude plugin update compound-engineering@compound-engineering-plugin`
4. `git -C ~/.claude/skills/gstack pull --ff-only --quiet`
5. `~/.claude/skills/gstack/setup -q --no-team` — only runs if step 4 succeeded. Already idempotent: `./setup` re-builds the browse binary only when source files are newer than the binary.
6. `git -C ~/.claude/skills/mattpocock-skills pull --ff-only --quiet`
7. Opt-in symlink loop over matt's `engineering/` and `productivity/` — runs regardless of step 6's outcome, since new symlinks for previously-unlinked skills should still be created from an older clone.

### Atomicity

No temp-file swap pattern (unlike `secrets-refresh`). Each operation is already atomic at its layer:

- `git pull --ff-only` either fast-forwards or leaves the working tree unchanged.
- `claude plugin update` either lands the new binary on disk or leaves the prior version in place.
- `gstack/setup` either rebuilds successfully or leaves the prior `browse` binary intact.

A failed sub-step records into `failed[]` but does not roll back; the world simply stays at the version it was before.

### Tool guards

`sync-skills` checks `command -v` for `claude`, `git`, and `bun` before invoking each. A missing tool produces a one-line skip notice and is **not** counted as a failure. This matches the existing install script's `command -v bun` guard at line 32.

### Exit code

- `0` if every attempted sub-step succeeded (or no-op'd cleanly, or was skipped due to a missing tool).
- `1` if any attempted sub-step failed. `dotup`'s `run_step skills` then captures the failure, appends `"skills"` to `failed_csv`, and the existing zsh banner surfaces it.

### `install-claude.sh.tmpl` changes

Diff from current:

- **REMOVE** lines 32-36 (gstack `./setup` invocation).
- **REMOVE** lines 48-62 (matt symlink loop).
- **ADD** at the end: `"$HOME/.local/bin/sync-skills" || true`.

On a first-install machine most `sync-skills` sub-steps no-op (plugins fresh from `claude plugin install`, repos fresh from `git clone`), but the gstack build and the matt symlink loop do real first-install work. The trailing `|| true` prevents a `sync-skills` failure from aborting the bootstrap apply — the per-step failures are still logged.

## Edge cases

1. **Plugin restart deferral.** `claude plugin update` updates the on-disk plugin immediately but defers activation until the next Claude Code restart. Documented in the script as a one-line comment. No implementation impact.
2. **gstack build break upstream.** `git pull` succeeds, `./setup` fails. Browse binary stays at the prior version. Step 5 reports failure, banner shows, user investigates.
3. **First-install path ordering.** `install-claude` is `run_once_after_03`, which runs after PATH has `~/.local/bin` (set by `dot_zshenv.tmpl:11`) and after bun is in PATH (set at line 7 of the install script). `sync-skills` will find all tools it needs.
4. **Network failure on a single source.** Each step is independent; banner names which source failed.
5. **All-source failure (e.g., no network).** Every step records into `failed[]`; the banner shows `skills` failed; `dotup` continues to other steps.

## Out of scope / future work

- Per-source cadence (e.g., weekly for gstack rebuilds, daily for plugin updates).
- Notifying the user when an installed plugin needs a Claude Code restart to activate.
- A `--force` flag on `sync-skills` mirroring `dotup --force`.
- Telemetry for "how often did each source actually receive an update?"

## References

- [`dot_local/bin/executable_dotup`](../../dot_local/bin/executable_dotup) — `run_step` and `failed[]` pattern reused by `sync-skills`.
- [`dot_local/bin/executable_secrets-refresh`](../../dot_local/bin/executable_secrets-refresh) — sibling helper, same dispatch-from-dotup pattern.
- [`.chezmoiscripts/run_once_after_03-install-claude.sh.tmpl`](../../.chezmoiscripts/run_once_after_03-install-claude.sh.tmpl) — current installer, to be slimmed.
- [`docs/adr/0001-dotup-scheduling-architecture.md`](../adr/0001-dotup-scheduling-architecture.md) — existing failure-banner contract.
