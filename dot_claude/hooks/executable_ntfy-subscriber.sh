#!/usr/bin/env bash
# Subscribe to ntfy topic and show native macOS notifications via terminal-notifier.
# Intended to run as a LaunchAgent — launchd restarts on exit (KeepAlive).

export PATH="/opt/homebrew/bin:$PATH"

# Source secrets (LaunchAgent doesn't go through .zshrc)
[ -f "$HOME/.config/dotfiles/secrets.sh" ] && source "$HOME/.config/dotfiles/secrets.sh"

if [ -z "${NTFY_TOPIC:-}" ]; then
  echo "ERROR: NTFY_TOPIC not set. Run bootstrap.sh with op CLI and OP_SERVICE_ACCOUNT_TOKEN." >&2
  sleep 30
  exit 1
fi

curl -sN "https://ntfy.sh/${NTFY_TOPIC}/json" | while read -r line; do
  event="$(echo "$line" | jq -r '.event // empty')"
  [ "$event" != "message" ] && continue

  title="$(echo "$line" | jq -r '.title // "Claude"')"
  message="$(echo "$line" | jq -r '.message // empty')"
  [ -z "$message" ] && continue

  terminal-notifier -title "$title" -message "$message" -sound default -group "claude-notify"
done
