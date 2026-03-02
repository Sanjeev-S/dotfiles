# Notification Suppression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Suppress Claude Code ntfy notifications when the user is actively watching the terminal.

**Architecture:** Add an `is_user_watching` function to `notify.sh` that checks tmux pane focus (preferred) or macOS frontmost app. If watching, skip the curl to ntfy.sh. Fail-open: if detection fails, notify anyway.

**Tech Stack:** Bash, tmux format variables, osascript (macOS), stat/date (coreutils)

---

### Task 1: Add `is_user_watching` function with tmux detection

**Files:**
- Modify: `claude/hooks/notify.sh:1-10` (insert function before HOST assignment)

**Step 1: Add the function**

Insert between line 8 (`[ -z "${NTFY_TOPIC:-}" ] && exit 0`) and line 10 (`HOST=...`):

```bash
IDLE_THRESHOLD="${NOTIFY_IDLE_THRESHOLD:-300}"

is_user_watching() {
  # Strategy 1: tmux pane focus (works on any platform, including over SSH)
  if [ -n "${TMUX:-}" ]; then
    local pane_active window_active
    pane_active=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_active}' 2>/dev/null) || return 1
    window_active=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{window_active}' 2>/dev/null) || return 1

    # Pane not visible — not watching
    [[ "$pane_active" != "1" || "$window_active" != "1" ]] && return 1

    # Pane visible — check if user walked away (idle too long)
    local client_tty idle_seconds now mtime
    client_tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null) || return 0
    if [ -n "$client_tty" ] && [ -e "$client_tty" ]; then
      now=$(date +%s)
      if [ "$(uname -s)" = "Darwin" ]; then
        mtime=$(stat -f %m "$client_tty" 2>/dev/null) || return 0
      else
        mtime=$(stat -c %Y "$client_tty" 2>/dev/null) || return 0
      fi
      idle_seconds=$(( now - mtime ))
      [ "$idle_seconds" -gt "$IDLE_THRESHOLD" ] && return 1
    fi

    return 0  # pane active, user recently typed — watching
  fi

  # Strategy 2: macOS frontmost app check (no tmux)
  if [ "$(uname -s)" = "Darwin" ] && command -v osascript &>/dev/null; then
    local frontmost
    frontmost=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null) || return 1
    case "$frontmost" in
      iTerm2|iTerm|Warp|Terminal|Alacritty|kitty|WezTerm|Ghostty) return 0 ;;
    esac
    return 1
  fi

  # Fallback: can't detect — assume not watching (fail-open → notify)
  return 1
}
```

**Step 2: Verify syntax**

Run: `bash -n claude/hooks/notify.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add claude/hooks/notify.sh
git commit -m "feat: add is_user_watching function to notify.sh

Detects if the user is actively watching Claude's terminal:
- tmux: checks pane/window focus + client TTY idle time
- macOS: checks if a terminal app is frontmost
- Fallback: fail-open (assume not watching, notify)"
```

---

### Task 2: Wire up suppression in the case statement

**Files:**
- Modify: `claude/hooks/notify.sh:15-29` (the case statement)

**Step 1: Add the suppression check**

Replace the case statement with:

```bash
case "$tool_name" in
  Stop|AskUserQuestion)
    is_user_watching && exit 0

    if [ "$tool_name" = "Stop" ]; then
      curl -s -d "Claude finished on ${HOST}" \
        -H "Title: Claude Done" \
        -H "Tags: white_check_mark" \
        "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
    else
      curl -s -d "Claude needs your input on ${HOST}" \
        -H "Title: Claude Waiting" \
        -H "Priority: high" \
        -H "Tags: question" \
        "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
    fi
    ;;
esac
```

**Step 2: Verify syntax**

Run: `bash -n claude/hooks/notify.sh`
Expected: no output (clean parse)

**Step 3: Commit**

```bash
git add claude/hooks/notify.sh
git commit -m "feat: suppress notifications when user is watching

Both Stop and AskUserQuestion events are suppressed when the
is_user_watching check passes. Fail-open: if detection fails,
notifications still fire."
```

---

### Task 3: Manual verification on current machine (Linux + tmux)

**Step 1: Verify tmux detection works in this environment**

Run:
```bash
TMUX="$TMUX" TMUX_PANE="$TMUX_PANE" bash -c '
  source claude/hooks/notify.sh <<< "{\"tool_name\": \"test\"}"
' 2>&1 || true
```

Then test the function directly:
```bash
bash -c '
  IDLE_THRESHOLD=300
  is_user_watching() {
    if [ -n "${TMUX:-}" ]; then
      local pane_active window_active
      pane_active=$(tmux display-message -p -t "${TMUX_PANE:-}" "#{pane_active}" 2>/dev/null) || return 1
      window_active=$(tmux display-message -p -t "${TMUX_PANE:-}" "#{window_active}" 2>/dev/null) || return 1
      [[ "$pane_active" != "1" || "$window_active" != "1" ]] && return 1
      local client_tty idle_seconds now mtime
      client_tty=$(tmux display-message -p "#{client_tty}" 2>/dev/null) || return 0
      if [ -n "$client_tty" ] && [ -e "$client_tty" ]; then
        now=$(date +%s)
        mtime=$(stat -c %Y "$client_tty" 2>/dev/null) || return 0
        idle_seconds=$(( now - mtime ))
        echo "client_tty=$client_tty idle=${idle_seconds}s threshold=${IDLE_THRESHOLD}s"
        [ "$idle_seconds" -gt "$IDLE_THRESHOLD" ] && return 1
      fi
      return 0
    fi
    return 1
  }
  if is_user_watching; then
    echo "RESULT: user IS watching — notification would be SUPPRESSED"
  else
    echo "RESULT: user NOT watching — notification would be SENT"
  fi
'
```

Expected: "user IS watching" (since we're in the active tmux pane and recently typed)

**Step 2: Test with inactive pane**

Switch to a different tmux pane, then run the same test from above targeting the original pane. Expected: "user NOT watching" (pane is no longer active).

**Step 3: Verify full script end-to-end**

Run (with a dummy/test topic or with NTFY_TOPIC unset to verify silent exit):
```bash
echo '{"tool_name": "Stop"}' | NTFY_TOPIC="" bash claude/hooks/notify.sh
echo "Exit code: $?"
```

Expected: exits 0 silently (no topic → early exit, suppression logic never reached).

---

### Task 4: Update design doc status and final commit

**Files:**
- Modify: `docs/plans/2026-03-02-notification-suppression-design.md:3`

**Step 1: Update status**

Change `**Status:** Approved` to `**Status:** Implemented`

**Step 2: Commit**

```bash
git add docs/plans/2026-03-02-notification-suppression-design.md
git commit -m "docs: mark notification suppression design as implemented"
```
