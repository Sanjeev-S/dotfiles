# `launchd` hourly timers across sleep

## Question

For the per-user `dotup` LaunchAgent, is replacing `StartInterval = 3600` with `StartCalendarInterval` at minute 0 still the recommended narrow fix when the intended behavior is one hourly opportunity plus catch-up after Mac sleep?

## Conclusion

Yes, with one important boundary: **the replacement is supported by Apple's documented timer semantics, but Apple does not document it as a repair for a wedged `StartInterval` service**. It should therefore be treated as the narrowest evidence-backed scheduling change and then validated by an actual calendar-triggered launch.

Use `StartCalendarInterval` with only `Minute = 0`, replacing—not supplementing—`StartInterval`:

```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

The missing calendar fields are wildcards, so this requests the top of every hour. Apple's current `launchd.plist(5)` man page says missed calendar firings during sleep are coalesced into one launch after wake, whereas a `StartInterval` firing during sleep is missed. The same distinction appears in Apple's archived scheduling guide. [Apple, “Scheduling Timed Jobs”](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)

The local source used for the current semantics was the Apple-shipped `man 5 launchd.plist` on macOS 15.6.1 (24G90), inspected 2026-08-23. Apple calls the `launchd` and `launchd.plist` man pages the best sources for `launchd` details. [Apple, “Creating Launch Daemons and Agents”](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

## Observed failure mechanism on this Mac

The immediate blocking mechanism is stronger than “the interval timer may have been missed during sleep”:

- `launchctl print gui/501` reported `on-demand count = 1`, while the dotup service reported `pended nondemand spawn = interval`.
- Read-only inspection of the Apple-shipped `/sbin/launchd` on this exact macOS build confirmed that an interval callback requests a non-demand `interval` spawn. While a domain's on-demand count is nonzero, that reason is parked on the service and retried only after the count returns to zero.
- Live `StartCalendarInterval` jobs in the same GUI domain were registered on the `com.apple.launchd.calendarinterval` event stream and continued to advance. On this build, that event path is admitted through the gate that parks the interval reason.

This establishes why “loaded and enabled” did not produce an interval launch and why the calendar path is a targeted workaround. It does **not** establish which component entered on-demand-only mode, why its count remained nonzero, or whether sleep caused it. The gate and event-path details are private implementation behavior rather than an Apple-supported API contract, so the public justification for the change remains Apple's documented calendar sleep/wake semantics.

## Confirmed semantics and tradeoffs

- `StartInterval = 3600` means every 3,600 seconds according to the installed man page. A firing is lost if the Mac is asleep, and is also lost if the job is still running at that instant.
- `StartCalendarInterval` uses cron-like calendar matching. With only `Minute = 0`, it is wall-clock anchored to each top of hour, not anchored 3,600 seconds after job load or the preceding run. Thus the two schedules are not equivalent in phase, and clock or time-zone changes can matter; Apple does not specify all discontinuity behavior.
- Missed calendar events during sleep are coalesced into one event, not replayed once per missed hour. That is a match for `dotup` because its own 24-hour success gate determines whether useful work is due.
- A calendar event missed while the Mac is powered off is not caught up; Apple says the job waits for the next designated calendar time. [Apple, “Effects of Sleeping and Powering Off”](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html#//apple_ref/doc/uid/10000172i-SW3-SW5)
- Do not leave both timer keys in the plist. The installed man page says `StartInterval` and `StartCalendarInterval` are evaluated independently, so keeping both creates two trigger streams and preserves the problematic interval path.
- The calendar trigger does **not** promise that the Mac is fully, interactively awake. In a February 2026 Apple Developer Forums reply, an Apple Developer Technical Support engineer said `launchd` makes no API guarantee about the power state in which a `StartCalendarInterval` job begins. The job can therefore encounter constrained or dark-wake conditions. [Apple DTS, “launchd StartCalendarInterval behavior changed”](https://developer.apple.com/forums/thread/815034)
- `dotup` performs network work. Apple warns that network availability cannot be modeled as a `launchd` dependency because interfaces can appear and disappear; the job itself must tolerate unavailability. `dotup` already preserves an old `last-success` on failure, allowing a later hourly calendar opportunity to retry, although a transient failure can still surface its failure banner. [Apple, “Network Availability”](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html#//apple_ref/doc/uid/10000172i-SW7-BCIEDDBJ)

## `RunAtLoad`

`RunAtLoad` is independent of the timer choice. The installed macOS 15.6.1 man page says it causes one launch when the job is loaded, defaults to false, and generally “should be avoided” because speculative launches can hurt boot/login.

For the narrow fix, **retain the existing `RunAtLoad = true`**:

- it preserves current behavior rather than expanding the change;
- it supplies one opportunity when the LaunchAgent is loaded after login or re-bootstrap;
- it partly covers the power-off gap that `StartCalendarInterval` itself does not catch up; and
- `dotup`'s 24-hour gate makes most extra load-time invocations cheap no-ops.

This is a deliberate exception to Apple's general advice, not a requirement of `StartCalendarInterval`. If running updater/network work during login is unwanted, removing `RunAtLoad` is a separate policy change; the first opportunity would then be the next top of hour.

## Recommendation and validation boundary

Change only the timer key/value in `private_Library/LaunchAgents/com.sanjeev.dotup.plist.tmpl`; leave `RunAtLoad` unchanged. The existing scheduler's included-plist hash should arrange the re-bootstrap when chezmoi applies the change.

Do not accept “loaded,” “enabled,” a successful manual `kickstart`, or a `RunAtLoad` run as proof. Acceptance requires:

1. a new run caused by a top-of-hour calendar firing while the Mac is awake; and
2. ideally, one controlled sleep-across-the-hour test showing a single catch-up after wake.

Because current Apple guidance does not promise a particular awake state and does not identify the observed stuck interval condition, failure of that test would require fresh `launchctl print` and unified-log evidence rather than another speculative plist change.

## Sources

- Apple-shipped `launchd.plist(5)` manual, macOS 15.6.1 (24G90), inspected locally 2026-08-23.
- Apple-shipped `/sbin/launchd` and live `launchctl print` state, macOS 15.6.1 (24G90), inspected read-only on 2026-08-23.
- [Apple Daemons and Services Programming Guide: Scheduling Timed Jobs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html), updated 2016-09-13.
- [Apple Daemons and Services Programming Guide: Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html), updated 2016-09-13.
- [Apple Developer Forums: Apple DTS response on `StartCalendarInterval` power-state guarantees](https://developer.apple.com/forums/thread/815034), February 2026.
