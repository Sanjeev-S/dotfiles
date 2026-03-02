# Notification Suppression When User Is Active

**Date:** 2026-03-02
**Status:** Approved

## Problem

Claude Code notifications fire on every `Stop` and `AskUserQuestion` event, even when the user is already looking at the terminal. This creates redundant noise.

## Solution

Add focus detection to `notify.sh` to suppress notifications when the user is actively watching Claude's terminal. Suppression happens at publish time — if watching, the `curl` to ntfy.sh is skipped entirely.

## Detection Strategy

**Platform-aware, fail-open.** If we can't determine focus, we notify (safe default).

### tmux (any platform, preferred)

When `$TMUX` is set:

1. Check if Claude's pane is the active pane AND its window is the active window via `tmux display-message -p -t "$TMUX_PANE"`.
2. If pane is not active → notify.
3. If pane is active, check TTY idle time on the tmux client's TTY (`#{client_tty}`). If idle > 5 minutes → notify (user walked away with pane focused).
4. If pane is active and user recently typed → suppress.

### macOS (no tmux)

When `$TMUX` is not set and running on macOS:

1. Use `osascript` to get the frontmost application name.
2. If it matches a known terminal app (iTerm2, iTerm, Warp, Terminal, Alacritty, kitty, WezTerm, Ghostty) → suppress.
3. Otherwise → notify.

### Fallback

No `$TMUX` and not macOS → always notify.

## Behavior

- Both `Stop` and `AskUserQuestion` events are suppressed equally when the user is watching.
- Walked-away threshold: 300 seconds (5 minutes), configurable via `NOTIFY_IDLE_THRESHOLD` env var.
- `stat` syntax differs by platform: `-f %m` on macOS, `-c %Y` on Linux.
- No new dependencies. Uses `osascript` (macOS built-in), `tmux`, `stat`, `date`.

## Architecture

```
Claude Code (PostToolUse: Stop|AskUserQuestion)
    ↓
notify.sh
    ├─ $TMUX set? → tmux pane focus + idle check
    ├─ macOS? → osascript frontmost app check
    ├─ neither? → fail-open (notify)
    └─ curl ntfy.sh (if not suppressed)
```

## Changes

Only `claude/hooks/notify.sh` is modified. No changes to:
- `claude/hooks/ntfy-subscriber.sh`
- `claude/com.sanjeev.ntfy-subscriber.plist`
- `claude/settings.json`
- `bootstrap.sh`

## Edge Cases

- Multiple Claude sessions: each hook invocation gets its own `$TMUX_PANE`, so detection is per-session.
- `osascript` failure: treated as "not focused" → notify.
- `tmux display-message` failure: treated as "not focused" → notify.
- `stat` failure on client TTY: treated as "active" → suppress (conservative since pane was confirmed active).
