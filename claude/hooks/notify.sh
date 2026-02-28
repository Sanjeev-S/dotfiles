#!/usr/bin/env bash
# Claude Code ntfy notification hook

# Source secrets if NTFY_TOPIC not already in environment
[ -z "${NTFY_TOPIC:-}" ] && [ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"

# Exit silently if topic unavailable — notifications are best-effort
[ -z "${NTFY_TOPIC:-}" ] && exit 0

HOST="$(hostname -s)"

read -r input
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"

case "$tool_name" in
  Stop)
    curl -s -d "Claude finished on ${HOST}" \
      -H "Title: Claude Done" \
      -H "Tags: white_check_mark" \
      "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
    ;;
  AskUserQuestion)
    curl -s -d "Claude needs your input on ${HOST}" \
      -H "Title: Claude Waiting" \
      -H "Priority: high" \
      -H "Tags: question" \
      "https://ntfy.sh/${NTFY_TOPIC}" > /dev/null
    ;;
esac
