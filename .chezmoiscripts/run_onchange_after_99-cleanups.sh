#!/usr/bin/env bash
# One-time state migrations / cleanups. Re-runs whenever this file changes
# (run_onchange_), so append new guarded, idempotent cleanups below as the
# repo evolves. Runs last (99) and after file/symlink targets are applied.
set -uo pipefail

# 2026-06: mattpocock/skills used to be cloned INTO each agent's skills dir,
# which made Claude Code discover every skill twice (once via the repo's own
# SKILL.md tree, once via our symlinks). The clone now lives in
# ~/.local/share/mattpocock-skills and sync-skills symlinks into it. Remove the
# stale in-skills clones; sync-skills repoints the symlinks. Guarded on /.git
# so we only ever delete an actual clone.
for stale in "$HOME/.claude/skills/mattpocock-skills" "$HOME/.codex/skills/mattpocock-skills"; do
  if [ -d "$stale/.git" ]; then
    echo "==> [cleanup] removing stale in-skills clone: $stale"
    rm -rf "$stale"
  fi
done

# 2026-07: a stale .chezmoiignore entry (pre-rename bootstrap.sh) let chezmoi
# deploy bootstrap-mac.sh into $HOME on every machine. The ignore entry is
# fixed; sweep the stray copies here. (.chezmoiremove can't do it — ignored
# targets are exempt from removal too.)
if [ -f "$HOME/bootstrap-mac.sh" ]; then
  echo "==> [cleanup] removing stray ~/bootstrap-mac.sh"
  rm -f "$HOME/bootstrap-mac.sh"
fi
