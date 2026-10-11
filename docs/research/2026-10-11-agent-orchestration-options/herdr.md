# Herdr agent-orchestration surface (v0.9.3, socket protocol 22)

Research note: how one coding agent running in a Herdr pane can start another agent, prompt it, wait for it, and get its output back. Primary sources only; third-party blogs excluded. Anything not confirmed in a primary source is marked **UNVERIFIED**.

## Sources

Local (captured 2026-10-11 from the installed 0.9.3 binary):

- `[skill]` `herdr --skill` output (captured 2026-10-11) (`herdr --skill`)
- `[schema]` `herdr api schema --json` output (`herdr api schema --json`; `protocol: 22`, `schema_version: 1`)
- `[help]` `herdr <group>` help output plus `herdr agent`, `herdr pane`, `herdr plugin`, `herdr api`, `herdr --help` output captured in this session
- `[reviewr-notes]` `/Users/sanjeevsuresh/.config/herdr/plugins/github/persiyanov.reviewr-e87b654a74f8/docs/herdr-api-notes.md` (third-party plugin author's notes, but read from Herdr source and verified live; treated as secondary-but-concrete)
- `[reviewr-manifest]` `/Users/sanjeevsuresh/.config/herdr/plugins/github/persiyanov.reviewr-e87b654a74f8/herdr-plugin.toml`
- `[fv-manifest]` `/Users/sanjeevsuresh/.config/herdr/plugins/github/herdr-file-viewer-c993314e2614/herdr-plugin.toml` and `scripts/open-file-viewer.sh`

Online (official, repo `herdrdev/herdr`, tag v0.9.3 docs):

- `[doc:socket]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/socket-api.mdx
- `[doc:automation]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/agent-automation.mdx
- `[doc:add-support]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/add-herdr-support.mdx
- `[doc:integrations]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/integrations.mdx
- `[doc:agents]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/agents.mdx
- `[doc:machines]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/connecting-machines.mdx
- `[doc:cli]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/cli-reference.mdx
- `[doc:plugins]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/docs/next/website/src/content/docs/plugins.mdx (also https://herdr.dev/ja/docs/preview/plugins/)
- `[changelog]` https://raw.githubusercontent.com/herdrdev/herdr/v0.9.3/CHANGELOG.md ; https://github.com/herdrdev/herdr/releases
- `[repo]` https://github.com/herdrdev/herdr (Rust source public, Apache-2.0 per LICENSE file; README: agents "spawn panes, prompt each other, and wait until another agent is genuinely blocked")
- `[guide]` https://herdr.dev/agent-guide.md ; index https://herdr.dev/llms.txt

Note: the docsearch/blog claim that Herdr is AGPL-3.0 is contradicted by the repo LICENSE (Apache-2.0) `[repo]`; third-party pages not used further.

## 0. Model

- Topology: workspace (`w1`) > tab (`w1:t1`) > pane (`w1:p1`); every pane is a real PTY. Agent commands address "the recognized coding agent currently occupying a pane" by unique live name (`[a-z][a-z0-9_-]{0,31}`) or pane ID. `[skill]`
- Lifecycle states: `idle | working | blocked | done | unknown` (`AgentStatus`). `idle` and `done` both mean ready for input; `done` = idle-but-not-yet-"seen"; reads do not mark seen, focus does. `blocked` = recognized approval/question UI. `unknown` = agent present but unclassified; "does not prove completion". `[skill]` `[schema]`
- Transport: newline-delimited JSON over `HERDR_SOCKET_PATH` (Unix socket; named pipe on Windows). Request `{"id","method","params"}`; success `{"id","result":{"type":...}}`; error `{"id","error":{"code","message"}}`. One request per connection except long-lived methods (`events.subscribe`). 1 MiB request-line cap, 5 s initial-request read window. `[doc:socket]` `[reviewr-notes]`
- The CLI is a thin client over the same socket; every control command prints the JSON envelope; errors go to stderr as JSON with exit 1. `[skill]` `[doc:socket]`
- Caller context injected into every pane: `HERDR_ENV=1`, `HERDR_PANE_ID`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`, `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`. The skill requires `test "$HERDR_ENV" = 1` before issuing control commands. `[skill]` `[doc:add-support]`
- Nested Herdr launches are blocked by design (an agent inside a pane cannot start its own Herdr). `[guide]`

## 1. Orchestration primitives (exact shapes)

All param/result shapes below are from `[schema]` (`schemas.request.$defs.*`, `schemas.success_response.$defs.ResponseResult`). CLI forms from `[help]`.

### 1.1 Spawn a pane (layout)

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus   # -> .result.pane.pane_id
```
JSON: `pane.split` `PaneSplitParams {direction: "right"|"down" (req), target_pane_id?, workspace_id?, ratio?, cwd?, env{}, focus=false, right_click="herdr"}`.
Alternatives: `workspace.create`, `tab.create`, `worktree.create` (git worktree + workspace). `agent start` "never creates, splits, or moves layout"; the pane must be an idle interactive shell. `[skill]`

Declarative: `layout.apply` `LayoutApplyParams {root: LayoutNode (req), workspace_id?, tab_id?, tab_label?, focus=false}`; `LayoutNode` = `{type:"pane", command?: string[], cwd?, env{}, label?, pane_id?}` | `{type:"split", direction, ratio, first, second}`. Returns `layout_apply {layout: LayoutDescription}`. `layout.export {tab_id?, pane_id?}` returns the same tree. Semantics: creates a fresh tab, "does not preserve live PTYs, scrollback, or running processes"; `command` is an argv run in the pane. `[schema]` `[doc:socket]` Introduced 0.7.0 as a "plugin host API". `[changelog]` No `herdr layout` CLI subcommand exists in 0.9.3 (`herdr layout` -> "unknown command") `[help]`; socket-only.

### 1.2 Start an agent

```bash
herdr agent start reviewer --kind codex --pane w1:p3 [--timeout MS] [-- <agent-args...>]
```
JSON: `agent.start` `AgentStartParams {name, kind, pane_id (all req), args: string[], timeout_ms?: 3000<x<=300000}` -> `agent_started {agent: AgentInfo, argv: string[]}`. `[schema]`
Kinds (0.9.3): `pi|claude|codex|gemini|cursor|devin|agy|cline|omp|mastracode|opencode|copilot|kimi|kiro|droid|amp|grok|hermes|kilo|qodercli|qwen|letta|maki|muse`. `[help]`
Returns only after Herdr detects the expected agent in that pane and considers it ready; default 30 s; if blocked during startup returns error `agent_not_ready` immediately but keeps the name usable for `read`/`send-keys`. `[skill]` `[doc:automation]`

### 1.3 Prompt (optionally wait in the same request)

```bash
herdr agent prompt reviewer "Review the diff; report only actionable findings." --wait --timeout 120000 [--until STATUS]...
```
JSON: `agent.prompt` `AgentPromptParams {target, text (req), wait?: {until: AgentStatus[], timeout_ms?}}` -> `agent_prompted {agent: AgentInfo}`. `[schema]`
Semantics `[skill]` `[doc:automation]` `[doc:socket]`:
- Sends text + encoded Enter as one ordered submission, honoring bracketed-paste mode; success means both were written, "that alone does not prove the agent started a turn".
- Refuses with `agent_blocked` (no bytes sent) if target is already `blocked`.
- `--wait` default settle set = `idle|done|blocked`. For a prompt sent from a non-working state, Herdr requires observed `working` or `blocked` within 5 s, else error `agent_prompt_stalled`; caller `timeout` error if its deadline expires first (deadline includes submission). No timeout = indefinite wait after activity.
- Wait tracks lifecycle state, not a turn: "if the agent is already working, completion of the active turn may satisfy it."
- Combining prompt+wait in one request exists specifically to avoid the race between submit and subscribe. `[doc:socket]`

### 1.4 Wait

```bash
herdr agent wait reviewer [--until blocked]... [--timeout 120000]
```
JSON: `agent.wait` `AgentWaitParams {target (req), until: AgentStatus[], timeout_ms?}` -> `agent_info {agent: AgentInfo}`. Returns immediately if status already matches; "server-owned and event-driven", pins the resolved pane occupant so a replacement process cannot satisfy it. `[schema]` `[doc:socket]` `[doc:automation]`
`AgentInfo` fields relevant to completion detection: `agent_status`, `state_change_seq` (default 0), `completion_seq?` ("The current idle transition completed work, independently of who has viewed it"; equals that transition's `state_change_seq`; not set by startup/session changes; may be absent on older servers), `interactive_ready`, `launch_pending`, `screen_detection_skipped`, `agent_session {source, agent, kind: id|path, value}`, `revision`, `tokens{}`, `state_labels{}`. `[schema]` `[doc:automation]`

Raw-output wait (no lifecycle interpretation):
```bash
herdr pane wait-output w1:p3 (--match TEXT | --regex RUST_RE) [--source visible|recent|recent-unwrapped] [--lines N] [--timeout MS]
```
JSON: `pane.wait_for_output` `PaneWaitForOutputParams {pane_id, source, match: OutputMatch (req), lines?, strip_ansi=true, timeout_ms?}` -> `output_matched {pane_id, revision, matched_line?, read: PaneReadResult}`. Checks the current snapshot first (pre-existing output matches), then polls. `[schema]` `[skill]` `[doc:cli]`

### 1.5 Read

```bash
herdr agent read reviewer --source recent-unwrapped --lines 120 [--format text|ansi]
herdr pane read  w1:p3   --source recent-unwrapped --lines 120
```
JSON: `agent.read` `AgentReadParams {target, source (req), lines?, format: text|ansi = text, strip_ansi=true}`; `pane.read` same with `pane_id`. Both return `pane_read {read: PaneReadResult {pane_id, workspace_id, tab_id, source, format, text, revision, truncated}}` (there is no separate `agent_read` type in the schema; docs say text is at `.result.read.text`). `[schema]` `[doc:automation]`
`ReadSource`: `visible` (viewport), `recent` (recent rows incl. soft wraps), `recent_unwrapped` (wraps joined; "prefer it for logs and transcripts"), `detection` (plain-text bottom-buffer snapshot used by agent detection; CLI exposes it only on `agent read`). `[schema]` `[skill]` `[help]`

### 1.6 Keys / raw input

`agent.send_keys {target, keys: string[]}` with logical keys (`esc`, `ctrl+c`, `enter`...), validated before any byte is written. `pane.send_text {pane_id, text}` writes raw bytes with "no bracketing, no newline conversion, no Enter"; `pane.send_keys`; `pane.send_input`; `herdr pane run <id> <cmd>` = text + Enter atomically. `[schema]` `[skill]` `[reviewr-notes]`

### 1.7 Discover

`agent.list` -> `agent_list {agents: AgentInfo[]}` (only panes hosting recognized agents) ; `agent.get {target}` ; `pane.list {workspace_id?}` ; `pane.process_info` (foreground argv, cwd) ; `session.snapshot` (whole tree, for reconciling after events). `[schema]` `[reviewr-notes]`
`agent.explain {target}` returns the detection evidence (manifest source, matched rule, region) for debugging misclassified state. `[help]` `[doc:cli]`

### 1.8 Cross-machine

```bash
herdr --machine <label-or-id> agent list
herdr --machine <label-or-id> agent prompt <remote-name> "..." --wait --timeout 120000
```
- Global prefix, added 0.9.1; routes `workspace`, `worktree`, `tab`, `pane`, `notification`, most `agent` subcommands, `api snapshot`, `status server`, API-backed `plugin` commands to the saved SSH profile's remote server, no TUI needed. Not forwarded: local config, session management, install/update, interactive attach. `[doc:machines]` `[doc:cli]` `[changelog]`
- Selector = enabled saved profile ID or unique case-sensitive label (not an arbitrary SSH host). Cannot combine with `--session`/`--remote`. Never falls back to Local; never auto-retries ("A connection failure does not prove a mutation was not applied"). Remote server must already be running and API-compatible. `[skill]` `[doc:machines]`
- IDs and agent names are per-server: two machines can both have `w1:p1`/`reviewer`; inherited `HERDR_*` IDs and `--current` do not identify remote panes. Selecting a machine in the TUI does not retarget CLI commands in existing panes. `[skill]`
- Remote worktree paths must be absolute/`~`-prefixed; plugin link paths absolute. `[skill]`
- `herdr machine list|status|reconnect|add|...` manage profiles only (not a cross-machine pane inventory). `[help]`
- Whether `events.subscribe` is forwarded through `--machine` is not stated anywhere I found: **UNVERIFIED**.

### 1.9 Minimal orchestration loop (CLI)

```bash
test "${HERDR_ENV:-}" = 1 || exit 1
P=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r .result.pane.pane_id)
herdr agent start worker --kind claude --pane "$P" >/dev/null
herdr agent prompt worker "Do X. When finished, print DONE-X on its own line." --wait --timeout 600000 \
  || { herdr agent get worker; herdr agent read worker --source recent-unwrapped --lines 200; exit 1; }
herdr agent read worker --source recent-unwrapped --lines 300 | jq -r .result.read.text
```
Every step above is composed from `[skill]` recommendations; `[skill]` also says: inspect `agent get`/`agent read` before sending anything after `blocked`/timeout/stalled, and "do not blindly submit it again".

## 2. Getting output back: mechanisms and weaknesses

What Herdr gives you is terminal text, not a structured response.

- **Mechanism:** `agent.read`/`pane.read` return a text snapshot (`PaneReadResult.text`), with `truncated: true` if older rows were omitted (added 0.8.0). `--lines N` pulls from screen + host scrollback. `[schema]` `[changelog]` `[skill]`
- **Alternate-screen problem:** Claude Code, OpenCode and similar full-screen TUIs keep their transcript in the alternate screen; "Alternate-screen rows do not enter ordinary host scrollback." `[skill]` `[doc:automation]`
- **Mitigation (0.8.0+):** for an *idle, recognized* agent at the bottom of its transcript, `recent`/`recent-unwrapped` reads asking for more than the visible screen make Herdr scroll the app itself (collect application-owned history) and then restore the viewport. Not done for `visible`, `detection`, ANSI reads, waits, manually scrolled agents, direct attachments, or apps ignoring mouse-wheel. `agent read --lines N` needing this history returns `agent_not_idle` while the agent is working/blocked/unknown. "not every application or response can be recovered this way." `[doc:automation]` `[skill]` `[changelog]` 0.9.1 fixed header/scrollbar artifacts in these reads. `[changelog]`
- **Documented fallback:** ask the agent to write its answer as Markdown to a temp dir and reply with only the path, then read the file on the same machine; explicitly "use this only as a fallback; do not request file output in the initial prompt." `[skill]` `[doc:automation]`
- **Completion is inferred, not signalled.** State comes from screen manifests for Claude Code/Codex (hook integrations for these report *session identity only*, not lifecycle) `[doc:integrations]`; locally no integrations are installed at all (`herdr integration status`: all "not installed"), so Claude/Codex state here is pure screen detection. Caveats from `[doc:agents]`: Codex "cannot be marked finished from the screen alone" and may sit in `unknown` so idle-waits time out; other known agents fall back to `idle` when no rule matches (`default_known_agent_idle_fallback`), so unfamiliar prompt shapes can read `idle` instead of `blocked`; `blocked` detection is strict (known approval/question UI only).
- **Turn vs state.** Waits observe state, not turns; an agent already `working` can satisfy a wait on the previous turn's completion. `completion_seq`/`state_change_seq` let a caller detect "a new idle transition since I last looked" but there is no per-prompt correlation ID. `[skill]` `[doc:automation]` `[schema]`
- **Delivery ambiguity.** `agent_prompt_stalled`/`timeout` "does not prove the prompt was never delivered"; read before retrying to avoid double submission. Observed with Claude Code (reviewr author): a paste while `blocked` is silently dropped; while `working` it lands as `[Pasted text #N]` and waits. `[skill]` `[reviewr-notes]`
- **Two-step races.** No atomic "send if ready": status read and write are separate calls (`agent.prompt` does refuse `blocked` atomically, but not `working`). `[reviewr-notes]` `[doc:socket]`
- **Size/time caps on the socket:** 1 MiB per request line; 5 s read window for the request (large `pane.send_text` prompts can be cut off). `[reviewr-notes]` (read from Herdr source; not stated in official docs: **UNVERIFIED** against docs, verified against source by that author.)
- No structured agent output channel, no JSON transcript access, and no `events.wait`-style "turn finished" event exists; the closest is `pane_agent_status_changed` plus `completion_seq`.

## 3. Events and subscriptions (schema detail)

Socket-only in 0.9.3: `herdr events` is "unknown command" `[help]`; no CLI wrapper documented `[doc:cli]`. Methods: `events.subscribe`, `events.wait`, `pane.wait_for_output`. `[schema]`

### 3.1 `events.subscribe`

`EventsSubscribeParams {subscriptions: Subscription[]}`. First reply `{"result":{"type":"subscription_started"}}`, then pushed lines `{"event": SubscriptionEventKind, "data": ...}` on the same open connection. `[schema]` `[doc:socket]`

`Subscription` variants (`type` const): lifecycle `workspace.created|updated|metadata_updated|renamed|moved|reordered|closed|focused`, `worktree.created|opened|removed`, `tab.created|closed|focused|renamed|moved`, `pane.created|closed|updated|focused|moved|exited|agent_detected`, `layout.updated`; plus three parameterized ones:
- `pane.output_matched {pane_id, source: ReadSource, match: OutputMatch, lines?, strip_ansi=true}` -> payload `PaneOutputMatchedEvent {pane_id, matched_line, read: PaneReadResult}`.
- `pane.agent_status_changed {pane_id, agent_status?: AgentStatus|null}` -> `PaneAgentStatusChangedEvent {pane_id, workspace_id, agent_status, agent?, display_agent?, title?, state_labels{}}`. Omit `agent_status` to get every transition; set it to filter to one target state.
- `pane.scroll_changed {pane_id}` -> `PaneScrollChangedEvent`.
Only those three appear in `subscription_event.SubscriptionEventKind`; lifecycle subscriptions deliver `EventEnvelope {event: EventKind, data: EventData}` with full `WorkspaceInfo`/`TabInfo`/`PaneInfo`/`PaneLayoutSnapshot` payloads (the schema splits these into `event` vs `subscription_event` documents). `[schema]`

`OutputMatch` = `{type:"substring", value}` | `{type:"regex", value}` (Rust regex). `[schema]`

Semantics `[doc:socket]` `[changelog]`:
- All entries validated up front; a non-existent pane fails the whole request and closes the connection.
- Live only since 0.9.0: "do not replay events retained before that point" — subscribe *before* taking `session.snapshot`.
- Drained in bounded batches, ordered within a subscription entry only (not across entries, not vs a snapshot).
- Backpressure: a slow reader gets `{"id":<original>, "error":{"code":"events_lost"}}` and that connection is closed (0.9.2). Recovery = resubscribe, wait for `subscription_started`, reconcile with `session.snapshot`. "Treat events as invalidation signals."
- Real-world use: reviewr subscribes `pane.agent_status_changed` per member agent to track turn boundaries, handles `events_lost` as a gap, and reconciles via `session.snapshot`. `[reviewr-notes]` and `src/herdr_socket.rs` in the same checkout.

### 3.2 `events.wait`

`EventsWaitParams {match_event: EventMatch (req), timeout_ms?}` -> `wait_matched {event: EventEnvelope}`. One-shot blocking wait for a single matching lifecycle event. `EventMatch` variants (`event` const + filters): `workspace_created {workspace_id?}`, `workspace_updated|closed|moved|focused {workspace_id}`, `workspace_renamed {workspace_id, label?}`, `tab_created {tab_id?, workspace_id?}`, `tab_closed|moved|focused {tab_id}`, `tab_renamed {tab_id, label?}`, `pane_created {pane_id?, workspace_id?}`, `pane_closed|focused|moved|exited {pane_id}`, `pane_output_changed {pane_id, min_revision?}`, `pane_agent_detected {pane_id, agent?}`, `pane_agent_status_changed {pane_id, agent_status (req)}`. `[schema]`
What it allows: block until "pane X becomes `blocked`" or "pane X exited" or "pane X output revision >= N" without maintaining a stream. Semantics beyond the schema are undocumented in `[doc:socket]` (only listed). Timeout error code presumably `timeout` as for agent waits: **UNVERIFIED**. Note `pane_agent_status_changed` in `EventMatch` requires a specific `agent_status`, whereas the subscription form makes it optional.

### 3.3 `pane.wait_for_output`

See 1.4. Difference from a `pane.output_matched` subscription: single request/response, checks existing output first, `timeout_ms`.

### 3.4 Agent view (sidebar filter, not orchestration)

`agent.view.set {source, label?, filter?: AgentViewFilter (all/any/not/eq/in over fields status|workspace_id|tab_id|pane_id|agent|seen|state_change_seq), sort[]}` / `agent.view.clear`. Controls the TUI's agent list; useful for a controller plugin to surface "my workers". `[schema]` Not documented in the fetched docs: purpose beyond the schema is **UNVERIFIED**.

## 4. Agent-side reporting protocol (`pane report-agent`)

How an agent (or a hook you install) tells Herdr its state instead of being screen-scraped. `[doc:add-support]` `[schema]` `[help]`

```bash
herdr pane report-agent "$HERDR_PANE_ID" --source my-integration --agent myagent --state working|idle|blocked|unknown \
  [--message TEXT] [--seq N] [--agent-session-id ID] [--agent-session-path PATH] [-- <resume-argv...>]
herdr pane report-agent-session "$HERDR_PANE_ID" --source ID --agent LABEL [--seq N] [--agent-session-id ID] ...
herdr pane release-agent        "$HERDR_PANE_ID" --source ID --agent LABEL [--seq N]
herdr pane report-metadata      "$HERDR_PANE_ID" --source ID [--title T] [--display-agent T] [--state-label STATUS=TEXT] [--token NAME=VALUE] [--ttl-ms N]
```
JSON: `pane.report_agent` `PaneReportAgentParams {pane_id, source, agent, state: idle|working|blocked|unknown (req), message?, seq?, agent_session_id?, agent_session_path?, resume_argv?: string[]}`; `pane.report_agent_session`; `pane.release_agent {pane_id, source, agent, seq?}`; `pane.report_metadata {pane_id, source, title?, display_agent?, state_labels{}, tokens{<=16, names ^[A-Za-z0-9_-]{1,32}$}, ttl_ms 1..86400000, applies_to_source?, seq?}`; `pane.clear_agent_authority {pane_id, source?, seq?}`. `[schema]`
Rules: `source` must be stable, unique, not start with `herdr:`; `seq` must strictly increase (a timestamp is suggested) or the report is ignored; reports should be sent in background with a short timeout; `release-agent` only when the agent really quits (fallback: Herdr clears state when the pane returns to a shell prompt). While a source reports state, Herdr uses it "instead of reading the screen". `resume_argv` (0.9.2; docs say "Herdr 0.10.0 or later" for resume commands, a version mismatch with the 0.9.2 changelog: **UNVERIFIED** which is right) lets Herdr relaunch the session after restart; errors `resume_not_accepted`, `invalid_resume_argv`. `[doc:add-support]` `[doc:integrations]` `[changelog]`
`tokens` on panes/workspaces (`report-metadata`, `workspace report-metadata`) are free-form key/value strings visible in `PaneInfo.tokens`/`AgentInfo.tokens` and sidebar; they are a sanctioned side-channel an orchestrator could use to tag workers (e.g. `task=123`), but they are display metadata, not restored after server restart. `[schema]` `[doc:socket]`

Built-in `herdr integration install <agent>` writes hook files (e.g. Claude: `~/.claude/hooks/herdr-agent-state.sh` + `SessionStart` entries in `settings.json`). For Claude, Codex, Copilot, Droid, Qoder, Qwen, Letta, Cursor, Grok, Antigravity, Hermes the hook reports *session identity only*; lifecycle still comes from screen manifests. Pi, OMP, Kimi, OpenCode, Kilo, MastraCode report lifecycle via hooks. `[doc:integrations]` Local status: none installed. `[help]`

## 5. Plugin API as it relates to orchestration

- A plugin = directory + `herdr-plugin.toml` (`id`, `name`, `version`, `min_herdr_version`, `platforms`, optional `[[build]]`, `[[startup]]`, `[[actions]]`, `[[events]]`, `[[panes]]`, `[[link_handlers]]`). Commands are argv arrays (no shell), run with plugin root as cwd, concurrently on their own threads with no per-plugin queue. `[doc:plugins]` `[reviewr-notes]`
- "The entire CLI is the plugin API. There is no separate SDK or restricted command set." Plugins get `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_ENV=1`, `HERDR_PLUGIN_ID/ROOT/CONFIG_DIR/STATE_DIR`, `HERDR_PLUGIN_CONTEXT_JSON`, plus `HERDR_WORKSPACE_ID/TAB_ID/PANE_ID` when available; event hooks get `HERDR_PLUGIN_EVENT` and `HERDR_PLUGIN_EVENT_JSON`. So a plugin can do everything in sections 1-3 (start/prompt/wait/read agents, subscribe). `[doc:plugins]`
- Trigger surfaces: (a) `[[actions]]` with `contexts` in `global|workspace|tab|pane|selection` (`PluginActionContext`), invoked by keybinding (`[[keys.command]] type="plugin_action" command="<plugin_id>.<action_id>"`) or `plugin.action.invoke {action_id, plugin_id?, context?: PluginInvocationContext}` -> `plugin_action_invoked {action, context, log}` (returns before the action finishes; exit/stdout land in `plugin.log.list`). `PluginInvocationContext` carries `workspace_id/label/cwd`, `tab_id/label`, `focused_pane_id/cwd/agent/status`, `selected_text`, `clicked_url`, `link_handler_id`, `invocation_source`, `correlation_id`, `worktree{}`. Context is resolved from the *focused* workspace, not the caller's pane. `[schema]` `[reviewr-notes]` (b) `[[events]] on="<event>"` hooks: documented examples are only `worktree.created`/`worktree.opened`; the full allowed `on` list is not published (`PluginManifestEventHook.on` is a free string in the schema): **UNVERIFIED** whether `pane.agent_status_changed` is accepted as a manifest hook (the example plugin `agent-telegram-notify` "sends a Telegram message when an agent reaches a configured status", suggesting agent-status hooks or a subscription; manifest not fetched). https://github.com/ogulcancelik/herdr-plugin-examples (c) `[[startup]]` one-shot after session restore (not supervised daemons). (d) `[[link_handlers]]` regex on clicked URLs. `[doc:plugins]`
- Plugin panes: `plugin.pane.open {plugin_id, entrypoint (req), placement: overlay|popup|split|tab|zoomed, direction, target_pane_id, workspace_id, cwd, env, width/height (popup), focus}` -> `plugin_pane_opened {plugin_pane: {plugin_id, entrypoint, pane: PaneInfo}}`; `popup` has no pane ID and is unreachable via pane/agent APIs. `[schema]` `[doc:plugins]` `[doc:cli]`
- Limits (v1): no runtime action registration, no non-terminal UI, no storage API, no sandboxing (runs as your user with full CLI access), no `plugin update`. `[doc:plugins]`
- Observed plugins: `herdr-file-viewer` (smarzban, v1.17.0): actions only, shells out to `pane list`, `plugin pane open --placement split`, `pane zoom`, `pane close`; no agent interaction. `[fv-manifest]` `persiyanov.reviewr` (v0.46.0, min 0.9.3): actions `open|toggle|close` (contexts `pane`,`workspace`), event hooks on `worktree.created|opened`, split pane; finds agents via `agent list` filtered by `HERDR_WORKSPACE_ID`, tracks turns by subscribing `pane.agent_status_changed` + `session.snapshot`, and delivers review comments to the agent with a raw `pane.send_text` bracketed paste (no Enter) followed by `agent focus`, refusing only a `blocked` agent. It is a concrete "plugin writes into an agent's input" example, and it deliberately leaves submission to the human. `[reviewr-manifest]` `[reviewr-notes]`
- `command.invoke {command_id (opaque "endpoint-issued command identifier from the client-shell projection"), pane_id?, tab_id?, workspace_id?, selection?}` exists in the schema but is undocumented and has no CLI (`herdr command` -> unknown). It appears to be the TUI's internal path for user-configured `[[keys.command]]`/popup commands: **UNVERIFIED**. `[schema]` `[help]` `[doc:socket]`
- Roadmap: no public roadmap found in README, docs or changelog; no "sub-agent" orchestration feature beyond what is above. Changelog mentions sub-agents only for OpenCode detection ("panes stay working or blocked while their subagents run", 0.9.2). `[repo]` `[changelog]`

## 6. Version history of the relevant surface

| Version (date) | Change | Source |
|---|---|---|
| 0.2.0 (2026-03-30) | Socket event subscriptions (lifecycle, pane output matches, agent state) and output waits | `[changelog]` |
| 0.5.10 (2026-05-17) | Socket methods for listing/reading/sending/waiting/starting agent terminals | `[changelog]` |
| 0.6.3 (2026-05-27) | `pane.report_metadata` | `[changelog]` |
| 0.6.9 (2026-06-10) | `agent explain` | `[changelog]` |
| 0.7.0 (2026-06-15) | Plugin v1 (link/list/enable/disable, actions, event hooks, plugin panes, link handlers), `layout.export/apply` | `[changelog]` |
| 0.7.3 / 0.7.4 | `done`/seen semantics; popup panes | `[changelog]` |
| 0.7.5 (2026-07-21) | Live-agent CLI facade: named `start`, atomic `prompt`, logical `send-keys`, server-owned `wait`; `agent_prompt_stalled` after 5 s; unique live names | `[changelog]` |
| 0.8.0 (2026-08-03) | Automatic text-history reads for idle alternate-screen agents; `truncated` flag | `[changelog]` |
| 0.8.2 (2026-08-19) | `agent prompt` refuses `blocked` (`agent_blocked`); marketplace | `[changelog]` |
| 0.9.0 (2026-09-07) | Multi-machine management; subscriptions start live (no replay); prompt success only after text+Enter; `--wait` requires observed activity | `[changelog]` |
| 0.9.1 (2026-09-16) | `herdr --machine` API forwarding; alt-screen history read fixes | `[changelog]` |
| 0.9.2 (2026-09-29) | `resume_argv` self-reported resume; `events_lost` instead of silent drops; errors keep request id | `[changelog]` |
| 0.9.3 (2026-09-29) | Hotfix (Escape-based shortcuts); nothing orchestration-related | `[changelog]` |

## 7. Error codes seen (for a controller's branching)

`agent_blocked`, `agent_not_ready`, `agent_not_idle`, `agent_prompt_stalled`, `timeout`, `events_lost`, `not_found`/`pane_not_found`, `invalid_params`, `plugin_disabled`, `plugin_pane_not_found`, `popup_not_open`, `workspace_group_close_required`, `platform_unsupported`, `invalid_resume_argv`, `resume_not_accepted`. `ErrorBody` is `{code, message}` only; codes are not enumerated in the schema. `[doc:socket]` `[doc:automation]` `[skill]` `[reviewr-notes]` `[schema]`

## 8. Bottom line for "agent starts agent, gets output back"

Herdr gives a controller: a real pane to spawn into, a validated `agent.start`, an atomic `agent.prompt` with built-in settle-wait, event-driven `agent.wait`/`events.subscribe`/`events.wait`, and text reads with best-effort alt-screen history recovery, all usable across SSH machines via `--machine`. What it does not give: a structured response channel, per-prompt correlation, or a reliable "turn finished" signal for screen-detected agents (Claude Code, Codex). The documented, supported pattern for faithful output transfer is still "write a Markdown file and tell me the path" or a sentinel line matched by `pane.wait_for_output`/`pane.output_matched`.
