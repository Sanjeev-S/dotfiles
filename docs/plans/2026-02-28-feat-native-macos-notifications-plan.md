---
title: "feat: Add native macOS notifications for Claude Code events"
type: feat
status: completed
date: 2026-02-28
origin: docs/brainstorms/2026-02-28-native-mac-notifications-brainstorm.md
---

# Add Native macOS Notifications for Claude Code Events

## Overview

Add a local ntfy subscriber on macOS that converts ntfy.sh push notifications into native Notification Center alerts via `terminal-notifier`. The server-side hook (`notify.sh`) stays unchanged — it still pushes to ntfy.sh. A LaunchAgent runs the subscriber at login.

**Pivot from original plan:** OSC 9 escape sequences were tested and do not work in iTerm2 (neither locally nor through tmux -CC mode). The approach was revised to keep ntfy as the transport and add a Mac-side subscriber.

(see brainstorm: docs/brainstorms/2026-02-28-native-mac-notifications-brainstorm.md)

## Acceptance Criteria

- [x] macOS Notification Center alert appears when Claude finishes (`Stop`)
- [x] macOS Notification Center alert appears when Claude needs input (`AskUserQuestion`)
- [x] Subscriber starts automatically at login via LaunchAgent
- [x] `bootstrap.sh` installs dependencies and loads LaunchAgent on macOS
- [x] ntfy topic removed from `bootstrap.sh` Linux summary
- [x] `notify.sh` variable quoting fix (security finding)
- [x] README.md and CLAUDE.md updated

## Changes Made

### New files
- `claude/hooks/ntfy-subscriber.sh` — subscribes to ntfy topic, fires `terminal-notifier`
- `claude/com.sanjeev.ntfy-subscriber.plist` — LaunchAgent for auto-start

### Modified files
- `bootstrap.sh` — added jq + terminal-notifier to macOS installs, added symlinks, LaunchAgent loading, removed ntfy topic from Linux summary
- `claude/hooks/notify.sh` — quoted `tool_name` variable assignment
- `README.md` — updated notifications section, added subscriber to tables
- `CLAUDE.md` — added new files to repo layout table

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-02-28-native-mac-notifications-brainstorm.md](../brainstorms/2026-02-28-native-mac-notifications-brainstorm.md)
