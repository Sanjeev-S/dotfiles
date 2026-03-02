#!/usr/bin/env bash
# Claude Code ntfy notification hook

# Source secrets if NTFY_TOPIC not already in environment
[ -z "${NTFY_TOPIC:-}" ] && [ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"

# Exit silently if topic unavailable — notifications are best-effort
[ -z "${NTFY_TOPIC:-}" ] && exit 0

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

HOST="$(hostname -s)"

read -r input
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"

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
