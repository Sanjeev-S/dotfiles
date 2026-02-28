#!/usr/bin/env bash
# Subscribe to ntfy topic and show native macOS notifications via terminal-notifier.
# Intended to run as a LaunchAgent — launchd restarts on exit (KeepAlive).

export PATH="/opt/homebrew/bin:$PATH"

NTFY_TOPIC="sanjeev-claude-99e0b7e3e3ae"

curl -sN "https://ntfy.sh/${NTFY_TOPIC}/json" | while read -r line; do
  event="$(echo "$line" | jq -r '.event // empty')"
  [ "$event" != "message" ] && continue

  title="$(echo "$line" | jq -r '.title // "Claude"')"
  message="$(echo "$line" | jq -r '.message // empty')"
  [ -z "$message" ] && continue

  terminal-notifier -title "$title" -message "$message" -sound default -group "claude-notify"
done
