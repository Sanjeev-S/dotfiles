#!/usr/bin/env bash
# Claude Code ntfy notification hook

NTFY_TOPIC="sanjeev-claude-99e0b7e3e3ae"
HOST="$(hostname -s)"

read -r input
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

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
