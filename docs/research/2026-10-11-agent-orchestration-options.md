# Agent-to-agent orchestration: Herdr APIs and the alternatives

## Question

What are the best ways for one coding agent (primarily Claude Code, secondarily Codex) to start another agent session, locally or on a dev box, and get that session's output back? How do Herdr's orchestration APIs compare?

Researched 2026-10-11 against primary sources (Herdr 0.9.3 binary + repo docs, Claude Code 2.1.296 docs, Codex 0.162 docs/source, protocol specs, orchestrator repos). Detailed per-area reports with every citation live beside this file in [`2026-10-11-agent-orchestration-options/`](2026-10-11-agent-orchestration-options/):

- [herdr.md](2026-10-11-agent-orchestration-options/herdr.md) — socket API, events, plugin API, version history
- [claude-code.md](2026-10-11-agent-orchestration-options/claude-code.md) — headless CLI, Agent SDK, subagents, teams, hooks, cloud, transcripts
- [other-clis.md](2026-10-11-agent-orchestration-options/other-clis.md) — Codex, Gemini, Cursor, OpenCode, Amp, Pi, Droid, Copilot, ACP
- [protocols-orchestrators.md](2026-10-11-agent-orchestration-options/protocols-orchestrators.md) — MCP, A2A, ACP, and 15 orchestrators

## Conclusion

**Herdr is a spawn-and-supervise layer, not an output channel.** Everything it returns about an agent's work is terminal text (`agent read` → `PaneReadResult.text`), and completion is *inferred* from the screen for Claude Code and Codex, not signalled. Its own skill file admits the supported way to get a faithful answer back is "ask the agent to write a Markdown file and reply with the path." So: use Herdr for what it is uniquely good at (a visible, human-interruptible pane, cross-machine via `--machine`, state waits), and get the *result* back through a structured side channel.

Ranked by fit for this setup (Herdr on Mac + dev boxes, Claude Code primary):

| Need | Best option | Why |
|---|---|---|
| Claude → Claude, same machine, no human needed | In-session `Agent` tool (background) + `SendMessage` resume; or `claude -p --output-format json [--json-schema]` | Structured result, `session_id` for resume, zero scraping. Already how this session's research ran. |
| Claude → already-running Claude session | Cross-session `ListAgents` / `SendMessage` with `notify_when_idle` | Local Unix socket, one-shot idle notice. `-p` workers must set `crossSessionInbound: accept`. |
| Claude → Codex (or any other CLI) | `codex exec --json -o last.txt [--output-schema]`; generically ACP over stdio | Codex has no MCP-server mode any more; `--output-schema` gives schema-constrained output. ACP is the only common denominator across 8 CLIs. |
| Worker must be **visible in Herdr** (so a human can see it block and step in) | `herdr pane split` → `herdr agent start … -- --session-id <uuid>` → `herdr agent prompt --wait` → read result via a Claude `Stop` hook keyed on that session id | Herdr gives the pane and the wait; the hook gives `last_assistant_message` without scraping. See the proposed pattern below. |
| Worker on a dev box, visible | Same, with the `herdr --machine <profile>` prefix | Forwards agent/pane/worktree commands over SSH to the remote server. No Anthropic relay. |
| Worker on a dev box, headless | `ssh box 'claude -p … --output-format json'` | Simplest structured cross-machine path. Invisible in Herdr. |

Do **not** build on: Herdr `agent read` as the primary result channel; Claude's transcript JSONL schema (docs: internal, changes any release); MCP sampling (deprecated 2026-07-28); A2A (no coding agent ships a server); Codex `mcp-server` (removed).

## Herdr's orchestration surface (0.9.3, protocol 22)

The CLI is a thin client over newline-delimited JSON on `HERDR_SOCKET_PATH`; every control command prints the JSON envelope. Live-verified this session from inside pane `w3:p1`.

Primitives:

- **Spawn a pane**: `pane split --current --direction right --cwd "$PWD" --no-focus` → `.result.pane.pane_id`. Or `workspace create`, `tab create`, `worktree create`, or declarative `layout.apply` (socket-only).
- **Start an agent**: `agent start <name> --kind claude|codex|… --pane <id> [-- <agent-args>]`. Returns only once Herdr detects the agent ready (30 s default). Native args pass through, so `-- --session-id <uuid>` works.
- **Prompt + wait atomically**: `agent prompt <name> "<text>" --wait --timeout <ms>`. Sends text + Enter as one submission, refuses a `blocked` agent with `agent_blocked`, returns `agent_prompt_stalled` if no `working|blocked` activity within 5 s. Wait tracks *state*, not the turn; an already-working agent can satisfy it on the previous turn.
- **Wait**: `agent wait <name> [--until blocked]`; `pane wait-output <id> --match|--regex` (checks existing output first).
- **Read**: `agent read <name> --source recent-unwrapped --lines N`. For idle alt-screen agents (Claude Code) Herdr scrolls the app to collect history since 0.8.0; returns `agent_not_idle` while working; "not every response can be recovered."
- **Events** (socket-only, no CLI): `events.subscribe` with per-pane `pane.agent_status_changed` / `pane.output_matched` / lifecycle types, streamed on one connection; `events.wait` one-shot. Verified: there is **no wildcard subscription**, each must name a `pane_id`; live-only since 0.9.0; slow readers get `events_lost` and must reconcile with `session.snapshot`.
- **Cross-machine**: `herdr --machine <label> agent prompt …` (0.9.1). IDs and names are per-server. Never falls back, never retries. Whether `events.subscribe` forwards: unverified.
- **Agent-side reporting**: `pane report-agent --state … --agent-session-id … --agent-session-path … [-- resume-argv]`. Hook-reported state overrides screen detection. Herdr's own Claude/Codex integrations report **session identity only**; lifecycle still comes from screen manifests.
- **Plugins**: "the entire CLI is the plugin API." Manifest-declared actions, event hooks (`worktree.created|opened` documented; agent-status hooks unverified), panes. Observed in the wild: `persiyanov.reviewr` subscribes to `pane.agent_status_changed` and injects text via raw `pane.send_text`.

Weaknesses that matter for orchestration:

1. Output is screen text; no structured channel, no per-prompt correlation id. `completion_seq` / `state_change_seq` only say "a new idle transition happened."
2. Claude/Codex completion is screen-inferred. Codex can sit in `unknown` so waits time out; unfamiliar prompts can read `idle` instead of `blocked`.
3. `timeout` / `agent_prompt_stalled` do not prove the prompt was not delivered. A paste while `blocked` is silently dropped; while `working` it lands as a pending paste.
4. Socket caps: 1 MiB per request, 5 s read window (large prompts via `pane.send_text` can be cut).
5. **Locally, no Herdr agent integrations are installed** (`herdr integration status`: all "not installed"), so `agent_session` is absent from `agent list` here. Installing the Claude and Codex integrations would at least give Herdr the session id/path for resume-after-restart.

## Claude Code's native surface (2.1.296)

Spawn → result channels, strongest first:

- **`Agent` tool** (in-session): background by default; result arrives as a `task_notification`; `agentId` in the result enables `SendMessage` resume. Fork type (`subagent_type: fork`) inherits context. Limits: depth 3, 20 concurrent.
- **`claude -p`**: `--output-format json` → `{result, session_id, structured_output, total_cost_usd, …}`; `--json-schema` for structured output; `--resume <id>` / `--session-id <uuid>` (pre-assign); `--bare` for scripted calls (no hooks, no inbox). Stays open until background subagents finish.
- **Agent SDK** (`@anthropic-ai/claude-agent-sdk` 0.3.296 / `claude-agent-sdk` 0.2.165): `query()` streams the same protocol; `agents` option defines subagents; `createSdkMcpServer` gives a child a "report back" tool; `SessionStore` for cross-host resume.
- **Cross-session messaging** (2.1.224+): per-session Unix socket; `SendMessage` + `notify_when_idle`; `-p` sessions *hold* inbound by default, set `crossSessionInbound: accept` for unattended workers.
- **Agent teams** (experimental, interactive only, one team per session): teammate idle notification carries the final answer; tmux/iTerm2 split display conflicts with multiplexers, so inside Herdr use `--teammate-mode in-process`.
- **Hooks**: `Stop` → `{session_id, last_assistant_message, transcript_path}`; `SubagentStop` adds `agent_id`, `agent_transcript_path`; `Notification` matchers `agent_completed|agent_needs_input`. Handler type `http` POSTs the payload to a URL with no script. Docs recommend `last_assistant_message` over parsing the transcript.
- **Agent view**: `claude --bg "<prompt>"` and `claude agents --json` (state `working|blocked|done|failed`, `sessionId`) is the documented way for one session to read another's status. Incompatible with `-p`.
- **Cloud**: `claude --cloud "<task>"`, `claude -p "<msg>" --cloud <id>` (fire-and-forget), routines fire API `POST /v1/claude_code/routines/{id}/fire` (returns session id, does not wait). No API to create an arbitrary cloud session. `claude mcp serve` exposes *tools*, not an agent-run tool.

## Other CLIs and the generic layer

- **Codex** (0.162): `codex exec --json "<p>" -o last.txt --output-schema s.json`; JSONL `thread.started{thread_id}` … `item.completed{agent_message}` … `turn.completed`. `codex exec resume <id>`. `codex app-server` (stdio JSON-RPC `thread/start`, `turn/start`, `turn/completed`, approval requests) is the canonical engine; Symphony and Multica drive it directly. `codex mcp-server` **removed**. `notify` hook emits `agent-turn-complete` with `last-assistant-message`.
- **Gemini** `gemini -p -o stream-json` (`result` event, session id on `init`), native `--acp`. **Cursor** `agent -p --output-format json`, native `agent acp`, Cloud Agents REST v1 with SSE. **OpenCode** `opencode run --format json --auto`, `opencode serve` REST+SSE, native `acp`. **Amp** `amp -x --stream-json` (Claude Code format clone). **Pi** `--mode rpc`. **Droid** `droid exec -o json`, native ACP. **Copilot** `--headless` + SDK, native `--acp` preview.
- **ACP (Agent Client Protocol)** is the only protocol all eight speak (native for 5, adapters for Codex, Amp, Pi, and Claude via `@agentclientprotocol/claude-agent-acp`). Loop: spawn subprocess → `initialize` → `session/new` → `session/prompt` → stream `session/update` → `stopReason`. Local stdio only; HTTP transport is a draft. **MCP** 2026-07-28 deprecated sampling and moved Tasks to an extension no client ships. **A2A** v1.0 is the right shape for cross-machine delegation (SSE, webhooks, 9 task states) but no coding agent ships a server.

## What the orchestrator ecosystem actually does

Two camps. tmux scrapers (claude-squad, agent-deck, Gas Town, AWS CAO, amux) poll `capture-pane` + regex, and their authors say so is fragile: Gas Town warns raw `send-keys` breaks Claude input; amux calls scraping "the fallback, not the long-term plan." Headless-JSON orchestrators (Vibe Kanban, Multica, Maestro, Paperclip, Symphony) get deterministic completion from `claude -p` stream-json `result` or Codex `turn/completed`, and they are the ones with real multi-machine support (Multica daemon per machine, agent-deck SSH remotes).

Herdr already appears as a pluggable backend in **AWS CAO** (`docs/herdr.md`: socket `working|idle|done|blocked` events instead of regex polling, marked Experimental) and **amux** (`CC_BACKEND=herdr`). That is evidence the market wants exactly Herdr's status-event layer above tmux, and that even those users still pull results through the agent's own channel, not the terminal.

Market churn to note: Vibe Kanban sunsetting (Apr 2026), Crystal deprecated, claude-squad quiet since Aug 2026. Active heavyweights: Paperclip, Multica, Symphony, Gas Town.

## Proposed pattern for this setup (not yet built or verified end-to-end)

Visible worker in Herdr, structured result, works locally and via `--machine`:

```bash
id=$(uuidgen | tr A-Z a-z)
p=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r .result.pane.pane_id)
herdr agent start worker --kind claude --pane "$p" -- --session-id "$id"
herdr agent prompt worker "<task>" --wait --timeout 900000
cat "$HOME/.local/state/agent-results/$id.md"   # written by a Stop hook
```

The `Stop` hook (`~/.claude/hooks/`, managed in `dot_claude/`) writes `last_assistant_message` to `~/.local/state/agent-results/<session_id>.md`. Pre-assigning `--session-id` makes correlation deterministic and avoids the transcript JSONL entirely. For a dev box, prefix `herdr --machine <label>` and read the file over SSH. Open questions: whether `--session-id` survives Herdr's `agent start` readiness detection unchanged, and whether `agent prompt --wait` returning `idle` reliably coincides with the Stop hook having flushed (hook runs before the prompt UI returns, so it should, but verify).

Cheaper first step regardless: `herdr integration install claude` and `codex` so Herdr knows each pane's session id and can resume agents after a server restart.

## Assumptions worth challenging

- *"Herdr orchestration APIs"* implies Herdr returns agent output. It returns screen text and state; the result channel has to come from the agent (hooks, `-p` JSON, ACP).
- *Headless is strictly better.* It is for data flow, but it is invisible in the Herdr dashboard, which was the reason for adopting Herdr (losing track of blocked agents). Pick per task: visible pane when a human may need to intervene, headless when not.
- *Codex is equivalent to Claude here.* It is not: Herdr cannot mark Codex finished from the screen alone, and Codex removed its MCP-server mode. Drive Codex through `codex exec --json` or app-server, not through a pane.
- *Agent teams replace all this.* Interactive-only, one team per session, no resume of in-process teammates, no cross-machine. Useful inside one session, not as the orchestration backbone.
