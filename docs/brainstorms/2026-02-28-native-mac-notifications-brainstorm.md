---
date: 2026-02-28
topic: native-mac-notifications
---

# Native macOS Notifications from Remote Claude Code

## What We're Building

Replace the ntfy.sh-based notification system with native macOS system notifications using iTerm2's OSC 9 escape sequences. When Claude Code finishes or needs input on a remote Hetzner server, the hook script emits an escape code through the existing ET+tmux connection, and iTerm2 renders it as a native macOS Notification Center alert.

This eliminates the ntfy dependency entirely — no external service, no HTTP calls, no phone app. Just escape codes flowing through the terminal connection that's already open.

## Why This Approach

**Approaches considered:**

1. **OSC escape sequences via tmux/ET (chosen)** — Zero dependencies. Uses the existing ET+tmux+iTerm2 stack. The notification flows through the same connection the user is already using.
2. **SSH reverse tunnel + local listener** — More reliable (works when disconnected) but adds a local daemon and tunnel management. Over-engineered for the use case.
3. **SSH callback to Mac** — Simple concept but requires inbound SSH to Mac, adds latency per notification, and has NAT/firewall issues.

**Why OSC 9:** The user is always at their Mac when working, so the "notifications lost when disconnected" trade-off is acceptable. The simplicity of zero additional infrastructure outweighs the robustness of the alternatives.

## Key Decisions

- **Drop ntfy entirely:** No phone notifications needed. Mac-only.
- **Use OSC 9 escape sequences:** iTerm2 natively supports `\e]9;message\007` for macOS notifications.
- **Same hook events:** Keep `Stop` and `AskUserQuestion` as the only triggers.
- **Same message content:** "Claude finished on {HOST}" and "Claude needs your input on {HOST}" — no additional context needed.
- **tmux passthrough required:** Since the shell runs inside tmux, the escape sequence needs tmux's passthrough wrapper (`\ePtmux;...\e\\`) to reach iTerm2.
- **Remove ntfy topic from repo:** Eliminates the security concern of the hardcoded ntfy topic.

## Open Questions

- None — approach is straightforward.

## Next Steps

-> `/workflows:plan` for implementation details
