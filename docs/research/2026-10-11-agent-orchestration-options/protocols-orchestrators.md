# Cross-agent protocols and multi-agent orchestrators (as of 2026-10-11)

Scope: how one coding agent can start another agent session and collect its output. Primary sources only (specs, official docs, repos). Star counts, push dates and release tags were read from the GitHub API on 2026-10-11. Items I could not confirm from a primary source are marked **UNVERIFIED**.

---

## Part A — Protocols

### A1. MCP (Model Context Protocol), agent-as-server

**What it standardizes.** JSON-RPC 2.0 between a *host/client* (LLM app) and *servers* that expose tools, resources and prompts; clients may expose elicitation to servers. Current spec revision is `2026-07-28`. <https://modelcontextprotocol.io/specification/latest>

**Transport.** stdio and Streamable HTTP. The 2026-07-28 revision made MCP stateless: it removed `initialize`/`notifications/initialized`, removed `Mcp-Session-Id`, added `server/discover`, replaced the GET/SSE channel with `subscriptions/listen`, and removed SSE resumability. Every request carries protocol version and client capabilities in `_meta`. <https://modelcontextprotocol.io/specification/latest/changelog>

**Agent-to-agent relevance.**
- *Sampling is deprecated.* SEP-2577 deprecates Roots, Sampling and Logging (12-month window); migration advice is "integrate directly with LLM provider APIs instead of Sampling". So server-initiated model calls are no longer the sanctioned agent-to-agent path. <https://modelcontextprotocol.io/specification/latest/changelog>
- *Server-initiated requests (incl. elicitation) are now Multi Round-Trip Requests (MRTR):* the server returns `resultType: "input_required"` with `inputRequests`; the client retries the original request with `inputResponses`. All results carry `resultType` (`complete` | `input_required`). <https://modelcontextprotocol.io/specification/latest/changelog>
- *Tasks* moved out of core into the official extension `io.modelcontextprotocol/tasks` (repo `modelcontextprotocol/ext-tasks`, latest tag v0.2.2, 2026-09-30). Server returns `CreateTaskResult` (`resultType: "task"`, `taskId`, `ttlMs`, `pollIntervalMs`); client polls `tasks/get`; `tasks/update` supplies mid-flight input when status is `input_required`; `tasks/cancel` is cooperative; states `working | input_required | completed | failed | cancelled`; optional `notifications/tasks` via `subscriptions/listen`. The blocking `tasks/result` and `tasks/list` were removed. <https://modelcontextprotocol.io/extensions/tasks/overview> · <https://github.com/modelcontextprotocol/ext-tasks>
- The community client matrix does not yet list any client as supporting the Tasks extension (matrix covers MCP Apps, OAuth CC, Enterprise Auth, Skills). <https://modelcontextprotocol.io/extensions/client-matrix>

**Claude Code as MCP server.** `claude mcp serve` runs Claude Code as a *stdio* MCP server exposing Claude Code's tools (file read/edit etc.) to any MCP client; the docs' example client is Claude Desktop. Caveat from the docs: the MCP *client* is responsible for confirming tool calls; Claude Code's own permission prompts don't apply in this mode. It exposes tools, not a "run a whole agent turn and return the answer" primitive. <https://code.claude.com/docs/en/mcp>

**Claude Code as MCP client (relevant for driving an agent-server).** Long MCP tool calls auto-background after 2 min (`CLAUDE_CODE_MCP_AUTO_BACKGROUND_MS`, v2.1.212+) and the result arrives as a task notification; non-interactive runs need `CLAUDE_AUTO_BACKGROUND_TASKS=1`. Elicitation: form and URL modes are shown as dialogs; on 2026-07-28 connections Claude Code declares `elicitation: {form: {}, url: {}}`; an `Elicitation` hook can auto-answer. No sampling support is documented. <https://code.claude.com/docs/en/mcp>

**Codex as MCP server — removed.** OpenAI's Codex SDK page states: "The standalone `codex mcp-server` has been removed" and points integrators to the Codex App Server. The current `codex mcp` subcommand only manages *external* servers (`list|get|add|remove|login|logout`). <https://learn.chatgpt.com/docs/codex-sdk> · <https://github.com/openai/codex/blob/main/codex-rs/cli/src/mcp_cmd.rs> · <https://github.com/openai/codex/blob/main/codex-rs/cli/src/main.rs>

**Codex App Server (the replacement).** `codex app-server` speaks newline-delimited JSON-RPC over stdio (default); `--listen ws://127.0.0.1:4500` (experimental/unsupported) or `--listen unix://PATH`. Handshake `initialize` then `initialized`. Methods: `thread/start`, `thread/resume`, `thread/fork`, `thread/list`, `turn/start`, `turn/steer`, `turn/interrupt`. Notifications: `thread/started`, `turn/started`, `item/started`, `item/completed`, `turn/completed` (status `completed | interrupted | failed`). Server-initiated requests: `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, `item/tool/requestUserInput`, `item/tool/call`, `mcpServer/elicitation/request`. Schema: `codex app-server generate-ts|generate-json-schema`. Docs say CI/automation should use the Codex SDK instead. <https://learn.chatgpt.com/docs/app-server>
- Codex SDK: TypeScript `@openai/codex-sdk` and Python `openai-codex`; `startThread()` → `thread.run()` → `finalResponse`; `resumeThread(id)`. Python SDK "controls the local Codex app-server over JSON-RPC". <https://learn.chatgpt.com/docs/codex-sdk>
- Headless: `codex exec "<prompt>"` prints only the final message to stdout; `--json` gives JSONL events `thread.started`, `turn.started`, `turn.completed` (with `usage`), `turn.failed`, `item.*`, `error`; `-o/--output-last-message <path>`; `--output-schema`; `codex exec resume --last|<SESSION_ID>`. <https://learn.chatgpt.com/docs/non-interactive-mode>
- Codex `notify = [..]` config: "Command invoked for notifications; receives a JSON payload from Codex" (payload fields not documented on the reference page I read — **UNVERIFIED**). Codex also has `hooks` (`Stop`, `SessionEnd`, `SessionStart`, `PreToolUse`, ... behind `features.hooks = true`). <https://learn.chatgpt.com/docs/config-file/config-reference>

**Claude Code headless (the equivalent on the Claude side).** `claude -p` with `--output-format json|stream-json`; final `result` line carries result text, `session_id`, `total_cost_usd`, `permission_denials`; `--input-format stream-json` for multi-turn over stdin; `--resume <id>`/`--continue`; `--bare` recommended for scripted calls; exit 0/non-zero; SIGTERM → exit 143. Subagent messages carry `parent_tool_use_id`. <https://code.claude.com/docs/en/headless>

**Maturity.** Core MCP: stable, Linux-Foundation-hosted (Agentic AI Foundation). Tasks: official extension, v0.2.x, no clients in the public matrix yet. Agent-as-MCP-server: Claude Code supports it (tool-level only); Codex removed it.

---

### A2. A2A (Agent2Agent)

**What it standardizes.** Discovery and task delegation between "opaque" agents: an **Agent Card** JSON at `https://{domain}/.well-known/agent-card.json` (renamed from `agent.json` in 0.3) describing identity, `skills`, `capabilities` (`streaming`, `pushNotifications`, `extendedAgentCard`), `securitySchemes`, and in v1.0 an ordered `supportedInterfaces` list, each with `protocolBinding` (`JSONRPC` | `GRPC` | `HTTP+JSON`), `url`, `protocolVersion`. <https://a2a-protocol.org/latest/specification/> · <https://aaif.io/blog/a2a-v1-0-a-builder-s-guide-part-1-discovery-tasks-and-clients>

**Transport / bindings.** JSON-RPC 2.0 over HTTP (method names PascalCase in v1.0: `SendMessage`, `SendStreamingMessage`, `GetTask`, `ListTasks`, `CancelTask`, `SubscribeToTask`, `GetExtendedAgentCard`, `Create/Get/List/DeleteTaskPushNotificationConfig`), gRPC, and HTTP+JSON/REST (`POST /message:send`, `POST /message:stream`, `GET /tasks/{id}`, `POST /tasks/{id}:cancel`, `POST /tasks/{id}:subscribe`, ...). Custom bindings allowed. Clients send `A2A-Version: 1.0`. <https://a2a-protocol.org/latest/specification/>

**Task start and results.** `SendMessage` creates/continues a Task; blocks by default until terminal or interrupted unless `returnImmediately: true`. Task states: `SUBMITTED`, `WORKING`, `INPUT_REQUIRED`, `AUTH_REQUIRED`, `COMPLETED`, `FAILED`, `CANCELED`, `REJECTED` (+`UNSPECIFIED`). Progress via (a) polling `GetTask`, (b) `SendStreamingMessage`/`SubscribeToTask` returning `text/event-stream` SSE where each event wraps a `StreamResponse` (Task | Message | status update | artifact update), stream closes on terminal state, (c) push notifications: agent HTTP-POSTs `StreamResponse` payloads to a client-registered webhook. <https://a2a-protocol.org/latest/specification/> · <https://aaif.io/blog/a2a-v1-0-a-builder-s-guide-part-1-discovery-tasks-and-clients>

**SDKs.** Official: `a2aproject/a2a-python` (`a2a-sdk`), `a2a-js` (`@a2a-js/sdk`), `a2a-java`, `a2a-go`, `a2a-dotnet`, `a2a-rs`. Official `a2a` CLI announced 2026-10-01 (discover card, send message, stream reply). <https://github.com/a2aproject/A2A> · <https://a2a-protocol.org/latest/blog/>

**Governance / adoption / maturity.** Created by Google (Apr 2025), donated to the Linux Foundation (Jun 2025); IBM's ACP merged in Aug 2025; v1.0.0 released 2026-03-12, v1.0.1 2026-05-28; accepted into the Agentic AI Foundation (Growth Stage) 2026-08-27. TSC: AWS, Cisco, Google, IBM Research, Microsoft, Salesforce, SAP, ServiceNow. Framework mentions: ADK, LangGraph, CrewAI, Semantic Kernel, BeeAI/Agent Stack. 26.1k stars, Apache-2.0. <https://a2a-protocol.org/latest/> · <https://github.com/a2aproject/A2A> · <https://github.com/i-am-bee/acp> (archived 2025-08-27: "ACP is now part of A2A")

**Fit for coding-agent orchestration.** No mainstream terminal coding agent (Claude Code, Codex, Gemini CLI) ships an A2A server. A2A is the right shape for cross-machine task delegation (HTTP, webhooks, task IDs), but you would have to wrap the CLI yourself.

---

### A3. ACP — Agent Client Protocol (agentclientprotocol.com)

**What it standardizes.** Editor/IDE ("Client") ↔ coding agent ("Agent") communication, LSP-style. Re-uses MCP JSON types where possible, adds coding-UX types (diffs, tool calls, plans). Created by Zed (announced 2025-08-27, built with Google; Gemini CLI was the reference agent; Claude Code support added in beta 2025-09-03). Apache-2.0. Now under the `agentclientprotocol` GitHub org. <https://zed.dev/blog/bring-your-own-agent-to-zed> · <https://agentclientprotocol.com/overview/introduction> · <https://github.com/agentclientprotocol/agent-client-protocol>

**Transport.** Agents run as subprocesses of the client over **stdio**, UTF-8 newline-delimited JSON-RPC 2.0; stdout reserved for protocol, stderr for logs; shutdown = close stdin + terminate. Streamable HTTP transport is a "draft proposal in progress"; custom transports permitted. <https://agentclientprotocol.com/protocol/transports>

**Lifecycle / methods.** `initialize` (protocolVersion is a single integer, currently `1`; capability negotiation: client `fs.readTextFile/writeTextFile`, `terminal`, `elicitation`, `session.notices`...; agent `loadSession`, `promptCapabilities`, `mcpCapabilities`, `session.delete`...) → optional `authenticate` → `session/new` or `session/load` → `session/prompt` (array of content blocks). Agent streams `session/update` notifications with `sessionUpdate` ∈ {`user_message_chunk`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `available_commands_update`, `current_mode_update`, `config_option_update`, `session_info_update`, `usage_update`, `notice`, `compaction_update`, `compaction_summary_chunk`}. Agent may call client methods `session/request_permission`, `fs/read_text_file`, `fs/write_text_file`, `terminal/create|output|release|wait_for_exit|kill`, `elicitation/create`. **Turn completion** = the `session/prompt` response with `stopReason` ∈ {`end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`}; `session/cancel` is a notification. <https://agentclientprotocol.com/protocol/overview> · <https://agentclientprotocol.com/protocol/initialization> · <https://agentclientprotocol.com/protocol/prompt-turn>

**SDKs.** Rust crate `agent-client-protocol` (+ `agent-client-protocol-schema`), TypeScript `@agentclientprotocol/sdk`, Python SDK, Kotlin (`acp-kotlin`), Java. Latest release v1.11.0 / schema-v1.25.0 (2026-10-09). 4.4k stars. <https://github.com/agentclientprotocol/agent-client-protocol>

**Agents implementing ACP (official registry, 42 listed).** Claude Agent via `claude-agent-acp` adapter (wraps the Claude Agent SDK; npm `@agentclientprotocol/claude-agent-acp`, v0.89.1 2026-10-10, 2.6k stars; supports nested subagent transcripts, terminals, slash commands, client MCP servers); Codex CLI via `codex-acp` adapter (starts the Codex App Server and translates; npm `@agentclientprotocol/codex-acp`, v2.2.2 2026-10-10; old `zed-industries/codex-acp` archived 2026-07-22); Gemini CLI native (`gemini --experimental-acp`, marked experimental); OpenCode native (`opencode acp`, stdio JSON-RPC); Goose (listed in registry; docs page now 404 — command **UNVERIFIED**); also Cursor, GitHub Copilot (public preview), Kiro CLI, Junie, Augment, Cline, Qwen Code, Kimi CLI, Mistral Vibe, OpenHands, Factory Droid, Hermes Agent, Docker cagent, Pi (adapter), Bub (adapter), and more. <https://agentclientprotocol.com/overview/agents> · <https://github.com/agentclientprotocol/claude-agent-acp> · <https://github.com/agentclientprotocol/codex-acp> · <https://github.com/zed-industries/codex-acp> · <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md> · <https://opencode.ai/docs/acp/>

**Clients.** Zed, JetBrains (AI Assistant `acp.json`), Neovim (CodeCompanion, avante, agentic.nvim, hermes.nvim), Emacs (agent-shell), VS Code extensions, Sublime, Qt Creator, Obsidian plugins, Unity, Chrome extensions, Pulsar, Visual Studio (Poolside). <https://agentclientprotocol.com/overview/clients>

**Maturity / fit.** Protocol v1 stable with frequent releases; broadest real adoption of any agent-facing protocol among terminal coding agents. Designed for one *editor* driving one *agent* subprocess on the same machine; no built-in cross-machine story (HTTP transport is draft). For an orchestrator, ACP gives a clean "spawn subprocess → `session/new` → `session/prompt` → stream `session/update` → `stopReason`" loop with structured permission requests, which is strictly better than scraping a TUI.

---

### A4. Other current protocols / mechanisms

**AG-UI (CopilotKit).** Event-based protocol for the *agent ↔ user-facing app* layer (streamed text, tool-call handoffs to the frontend, shared state as event-sourced diffs, interrupts, custom events) over HTTP/WebSockets. Explicitly positions itself as complementary to MCP (tools) and A2A (agent↔agent). First-party integrations: Microsoft Agent Framework, Google ADK, AWS Strands/Bedrock AgentCore, Mastra, Pydantic AI, Agno, LlamaIndex, AG2; community: Claude Agent SDK, Claude Managed Agents SDK. SDKs in Kotlin, Go, Dart, Java, Rust, Ruby, C++, .NET. Not an agent-spawning protocol. <https://docs.ag-ui.com/introduction>

**IBM/BeeAI ACP (Agent Communication Protocol).** Archived 2025-08-27; README banner: "ACP is now part of A2A under the Linux Foundation". BeeAI's successor "Agent Stack" exposes all agents as A2A. Not a live option. <https://github.com/i-am-bee/acp> · <https://github.com/i-am-bee/beeai-platform>

**OpenAI Agents SDK handoffs.** In-SDK delegation: a handoff is exposed to the model as a tool `transfer_to_<agent>`; `handoff(agent, on_handoff, input_type, input_filter, is_enabled, nest_handoff_history)`; `Agent.as_tool(...)` is the agents-as-tools alternative. Handoffs "stay within a single run" (library-level, not a wire protocol). <https://openai.github.io/openai-agents-python/handoffs/>

**Anthropic Claude Managed Agents (beta, header `managed-agents-2026-04-01`).** Server-hosted harness: Agent (model+prompt+tools+MCP+skills) + Environment (Anthropic cloud sandbox or self-hosted sandbox) + Session + Events. Start a session, send user events, "Claude autonomously runs tools and streams back results through server-sent events (SSE)"; event history persisted and fetchable; steer/interrupt mid-run; scheduled deployments. Reachable via SDKs, `ant` CLI, or REST. Not ZDR/HIPAA eligible. <https://platform.claude.com/docs/en/managed-agents/overview>

**Claude Agent SDK.** Python/TypeScript library that runs the Claude Code binary (same tools, agent loop, hooks, subagents, sessions resume/fork). Non-Python/TS callers should "run the CLI as a subprocess with `-p` and `--output-format json`". Note branding rule: third parties may not present SDK agents as "Claude Code". <https://code.claude.com/docs/en/agent-sdk/overview>

**Claude Code native multi-session features (first-party, relevant to Herdr).**
- *Hooks*: 33 events incl. `Stop` (payload includes `last_assistant_message`), `StopFailure`, `SubagentStop`, `TaskCompleted`, `TeammateIdle`, `Notification` (matchers `idle_prompt`, `permission_prompt`, `agent_completed`, `agent_needs_input`, `elicitation_dialog`), `SessionEnd`; handler types `command`, `http`, `mcp_tool`, `prompt`, `agent`. An HTTP `Stop` hook is a documented way to push turn-complete events to an orchestrator. <https://code.claude.com/docs/en/hooks>
- *Agent teams* (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): lead + teammates, file mailboxes at `~/.claude/teams/{team}/inboxes/*.json`, shared task list with file locking; display modes in-process or split panes via tmux / iTerm2 (`it2`); idle teammates notify the lead with their final answer; one team per session, no nested teams, no resume of in-process teammates, not available under `-p`. <https://code.claude.com/docs/en/agent-teams>
- *Cross-session messaging* (v2.1.224+): `ListAgents`/`SendMessage` between your sessions; same-machine over a per-session Unix socket (`CLAUDE_CODE_MESSAGING_SOCKET`, `/tmp/cc-socks-<uid>`), scripts/hooks can post lines into the socket; `notify_when_idle` gives one notice when another local session goes idle (12h cap); other machines/cloud sessions reached *through Anthropic servers* via Remote Control (claude.ai login required). <https://code.claude.com/docs/en/cross-session-messaging>
- *Cloud sessions*: `claude --cloud "task"` starts a cloud VM session; `claude -p "msg" --cloud <session-id>` queues a follow-up and exits (`--output-format json` → `{ok, session_id, url}`); `--teleport <id>` pulls the session back. <https://code.claude.com/docs/en/claude-code-on-the-web>
- *Remote Control*: steer a local session from claude.ai/mobile; requires claude.ai subscription login, not API keys; `claude remote-control` server mode with `--spawn/--capacity`. <https://code.claude.com/docs/en/remote-control>

---

## Part B — Orchestrators / multiplexers for terminal coding agents

Baseline first, then tools. Stars/pushed from GitHub API 2026-10-11.

### B0. The tmux baseline Herdr improves on

`tmux send-keys` (keystroke injection; `-l` literal), `capture-pane -p [-S start -E end]` (dump visible pane or scrollback to stdout), `pipe-pane -O cmd` (stream pane output to a process), `wait-for channel` / `wait-for -S channel` (block until signalled; `-L/-U` lock/unlock), and control mode `tmux -C/-CC` (`%output`, `%begin/%end/%error`, `%exit`, `%pause/%continue` notifications). <https://man.openbsd.org/tmux.1>
Observed weaknesses, as stated by tool authors: tmux "has no concept of agent state", so orchestrators "poll terminal output and match regex patterns to detect when an agent is idle" (AWS CAO, which compares tmux vs herdr side by side: polling `capture-pane` + regex vs native `working|idle|done|blocked` socket events). <https://github.com/awslabs/cli-agent-orchestrator/blob/main/docs/herdr.md> Gas Town warns "Never use raw `tmux send-keys` — it doesn't handle Claude's input correctly" and wraps it in `gt nudge` (literal mode + debounce + separate Enter). <https://github.com/gastownhall/gastown/blob/main/docs/reference.md>

### B1. claude-squad (smtg-ai) — 8.6k★, AGPL-3.0, last push 2026-08-20
- Spawn: tmux session per agent + git worktree per task; default Claude Code, also Codex, Gemini, Aider, any CLI via `-p`.
- Completion: terminal scraping. `statusMonitor` hashes `tmux capture-pane -p -e -J` output each tick; `HasUpdated()` detects change and `hasPrompt` by substring match (e.g. "No, and tell Claude what to do differently", "(Y)es/(N)o/(D)on't ask again", "Yes, allow once"); `--autoyes` taps Enter.
- Output: preview/diff tabs; commit/push keys. No cross-machine. Activity slowed (no push since Aug 2026).
- <https://github.com/smtg-ai/claude-squad> · <https://github.com/smtg-ai/claude-squad/blob/main/session/tmux/tmux.go>

### B2. agent-deck (asheshgoplani) — 1.1k★, MIT, last push 2026-10-10
- Spawn: tmux (optional dedicated server `tmux -L agent-deck`); Claude, Gemini, OpenCode, Codex, Copilot, Cursor, Hermes, pi, etc.
- Completion: "smart polling" classifies Running/Waiting/Idle/Error; uses tool hooks where they exist (Codex notify hook; pi extension turn events) and falls back to reading the pane; README says Codex status "cannot converge reliably" without its hook. `agent-deck notify-daemon` nudges a parent session when a child transitions to waiting/error/idle (parent linkage `--parent`).
- Output: copy last response; cost/usage from Claude hooks + transcripts.
- Cross-machine: yes over SSH (`remote add|sessions|attach|drain|update`); parent links cannot span machines, so `remote drain` pulls completions into a local inbox.
- <https://github.com/asheshgoplani/agent-deck>

### B3. Conductor (conductor.build) — closed-source macOS app, v0.90.0 (2026-10-02)
- Runs Claude Code, Codex, Cursor, OpenCode in parallel "isolated workspaces" (branch, files, terminal, diff). Changelog mentions an SDK ("0.36.3 ... SDK Memory Leaks"), "Big Terminal Mode", Conductor Cloud (0.78.0, 2026-07-30), an API and background tasks (0.77.0), Conductor for iOS (0.90.0).
- Spawn mechanism, completion detection and notification internals: **UNVERIFIED** (not documented on public pages).
- <https://conductor.build/> · <https://conductor.build/docs> · <https://conductor.build/changelog>

### B4. Crystal (stravu) — 3.1k★, MIT — DEPRECATED
- Desktop app running Codex and Claude Code sessions in parallel git worktrees. README: deprecated Feb 2026, replaced by Nimbalyst. Last push 2026-02-26. Internals not documented on the page (**UNVERIFIED**).
- <https://github.com/stravu/crystal>

### B5. Vibe Kanban (BloopAI) — 28.3k★, Apache-2.0 — SUNSETTING
- Kanban → workspace (branch, terminal, dev server) per task; executors for Claude Code, Codex, Gemini CLI, Copilot, Amp, Cursor, OpenCode, Droid, CCR, Qwen Code.
- Spawn/completion: headless CLI with JSON stream. Claude executor runs `claude -p --verbose --output-format=stream-json --input-format=stream-json`, extracts `session_id` from the stream, resumes with `--resume <id>` (and `--resume-session-at`).
- Status: bloop shut down 2026-04-10; repo continues community-maintained, remote services removed after 30 days, moving to fully local. Self-hosted cloud/tunnel mode existed (`VK_SHARED_API_BASE`, `VK_TUNNEL`).
- <https://github.com/BloopAI/vibe-kanban> · <https://github.com/BloopAI/vibe-kanban/blob/main/crates/executors/src/executors/claude.rs> · <https://www.vibekanban.com/blog/shutdown>

### B6. CCManager (kbwo) — 1.3k★, MIT, last push 2026-10-10
- Spawn: PTY-based (no tmux; `src/services/bunTerminal.ts`), one PTY per worktree session; Claude Code, Gemini, Codex, Cursor Agent, Copilot CLI, Cline, OpenCode, Kimi, MCode. Auto-appends `--teammate-mode in-process` to `claude` to avoid conflict with Agent Teams split panes.
- Completion: per-assistant "state detection strategies" (`src/services/stateDetector/`) classify Idle/Busy/Waiting from terminal output; **Status Change Hooks** run user commands on transitions (notifications, logging).
- Output: not preserved across restarts. Cross-machine: devcontainer only (`--devc-up-command/--devc-exec-command`), no SSH.
- <https://github.com/kbwo/ccmanager>

### B7. Gas Town (Steve Yegge; gastownhall/gastown) — 18.3k★, MIT, last push 2026-10-08
- Model: Mayor (coordinator), Polecats (workers, persistent identity / ephemeral sessions), Rigs (repo containers), Witness (per-rig lifecycle monitor: watches, nudges, recycles stuck polecats), Deacon (patrols), Refinery (merge queue), Beads (git-backed issue tracker), Convoys. Presets for Claude, Gemini, Codex, Kiro, Cursor, Auggie, Amp, OpenCode, Copilot, Pi, OMP.
- Spawn: tmux required for `gt up` and all tmux-backed roles; `gt sling <bead> <rig> [--agent codex]` assigns work; Claude Code sessions get managed `--settings` hook files (`~/.gt/hooks-base.json` + role overrides).
- Completion: worker runs `gt done` (pushes branch, files merge-request bead, clears hook, sets state `done`, exits session); lifecycle states Idle→Working→Done, plus Stalled/Zombie handled by Witness. Messaging via `gt nudge` (wraps send-keys with literal mode + debounce + Enter) and mail.
- Cross-machine: "Wasteland" federation via DoltHub (shared Dolt DB, Phase 1 "wild-west"); multi-host rig execution not documented (**UNVERIFIED**).
- <https://github.com/gastownhall/gastown> · <https://github.com/gastownhall/gastown/blob/main/docs/HOOKS.md> · <https://github.com/gastownhall/gastown/blob/main/docs/concepts/polecat-lifecycle.md> · <https://github.com/gastownhall/gastown/blob/main/docs/reference.md> · <https://github.com/gastownhall/gastown/blob/main/docs/WASTELAND.md>

### B8. OpenAI Symphony — 27.6k★, Apache-2.0, "experimental ... low-key engineering preview", last push 2026-09-15
- Polls an issue tracker (default 30 s; Linear in the demo), dispatches up to `max_concurrent_agents` (default 10) by priority.
- Spawn: `codex app-server` via `bash -lc` in a per-issue workspace, speaking the app-server protocol over stdio; first turn gets the rendered `WORKFLOW.md` prompt, later turns reuse the thread; `session_id = <thread_id>-<turn_id>`.
- Completion: turn ends on completion/failure/cancel signal, silence timeout (`turn_timeout_ms`), or subprocess exit; worker refetches the issue and starts another turn until `max_turns` (20) or the tracker state leaves "active". Stall kill after `stall_timeout_ms` (300 s) without events. Tracker state, not the agent, is the source of truth for "done".
- Cross-machine: single host assumed (local FS workspaces, local hooks). Reference impl in Elixir.
- <https://github.com/openai/symphony> · <https://github.com/openai/symphony/blob/main/SPEC.md>

### B9. Paperclip (paperclipai) — 100.1k★, MIT, last push 2026-10-11
- "Company" layer: org charts, tasks, budgets, approvals; Node server + React UI, local mode with embedded Postgres.
- Spawn: adapters — CLI (`claude_local`, `codex_local`, gemini, kimi, cursor, OpenCode, Pi, Hermes...), HTTP/webhook (OpenClaw), custom process, external packages. `claude_local` runs Claude Code CLI headless with `dangerouslySkipPermissions` default true, `maxTurnsPerRun` 300, persists `session_id` and resumes with `--resume`, auto-rotates poisoned sessions.
- Completion: heartbeat model — agents wake via DB-backed queue for assigned work/follow-ups/timers; a run ends when the CLI process finishes; review/approval stages gate task completion.
- Output: run logs, usage records, adapter session state, task comments/documents; activity log.
- Cross-machine: remote execution targets (sandbox/SSH) and sandbox providers (e2b, Cloudflare, Daytona, Modal, Novita, K8s) are described/roadmapped; Tailscale bind for remote access.
- <https://github.com/paperclipai/paperclip> · <https://github.com/paperclipai/paperclip/blob/master/docs/adapters/claude-local.md>

### B10. Ralph / ralph-loop style
- Original: Geoffrey Huntley, 2025-07-14: `while :; do cat PROMPT.md | claude-code ; done` — no exit condition; one task per fresh context; human decides when to stop. <https://ghuntley.com/ralph/>
- Anthropic's `ralph-wiggum` plugin: `/ralph-loop "<prompt>" --max-iterations N --completion-promise "TEXT"`; a **Stop hook** blocks exit and re-feeds the same prompt; completion = exact string match on the promise (e.g. `<promise>COMPLETE</promise>`); `--max-iterations` is the safety net. In-session, single machine. <https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum>

### B11. Maestro (RunMaestro) — 3.4k★, AGPL-3.0, last push 2026-10-11
- Cross-platform desktop "Agent Orchestration Command Center"; Claude Code, Codex, OpenCode, Factory Droid (+ Copilot-CLI, Qwen3 Coder, Oh My Pi beta).
- Spawn: headless CLIs — Claude via `claude --print` (stream-json; code comments confirm `--print` stream-json runs emit a single `result` message at the end), Codex via `codex exec`, Droid via `droid exec -o stream-json`.
- Completion: the stream-json `result` message / process exit; liveness tracked on `data|thinking-chunk|tool-execution|usage` events to avoid wall-clock kills (`agent-liveness.ts`). Queued messages sent "after the current turn completes via `--resume`".
- Output: session history, cost dashboards. Remote: built-in web server + Cloudflare tunnel, `maestro-cli`; single host.
- <https://github.com/RunMaestro/Maestro> · <https://github.com/RunMaestro/Maestro/blob/main/src/main/utils/agent-liveness.ts> · <https://docs.runmaestro.ai/provider-notes.md>

### B12. Mux → Xum (coder/xum) — 2.1k★, AGPL-3.0, last push 2026-10-11
- Renamed from Mux to Xum (trademark). Desktop app with its *own* agent loop ("inspired by Claude Code") over multiple models (Anthropic, OpenAI, xAI, Ollama, OpenRouter) — it does **not** wrap Claude Code/Codex CLIs.
- Workspaces: Local, git Worktree, **SSH** remote execution; "server mode" for mobile. Completion: agents report status in the sidebar (mechanism is in-process, no scraping). Docker/Coder runtimes not mentioned on the current README.
- <https://github.com/coder/xum>

### B13. Multica (multica-ai) — 52.5k★, "Multica License" (Apache-2.0 + conditions), last push 2026-10-11
- Issue-tracker-style workspace; Go backend + Postgres, Next.js web, Electron desktop, Expo iOS; an **agent daemon** on each dev machine connects over WebSocket and drives 26 installed CLIs.
- Spawn: Claude via `claude ... --verbose --output-format stream-json` with stdin kept open; Codex via **app-server** (`turn/started`, `turn/interrupt`, `turn/completed` referenced in `agent.go`); resume by session ID with fallback notices.
- Completion: Claude `result` message in the stream (`sawResult`, `finalResultText`, `resultIsError`); app-server `turn/completed`; watchdogs on handshake/turn timeouts. Agent moves the issue to review when done.
- Cross-machine: yes — multiple machines registered as "runtimes"; execution log replay per run.
- <https://github.com/multica-ai/multica> · <https://github.com/multica-ai/multica/blob/main/server/pkg/agent/agent.go> · <https://github.com/multica-ai/multica/blob/main/server/pkg/agent/claude.go>

### B14. Herdr-adjacent / competitors found
- **AWS Labs CLI Agent Orchestrator (CAO)** — 1.4k★, Apache-2.0, last push 2026-10-11. `cao-server` (FastAPI) + `cao-mcp-server` giving a supervisor agent handoff/assign tools; providers Kiro (default), Claude Code, Codex, Antigravity, Hermes, Kimi, MiniMax, Copilot, OpenCode, OMP, Cursor, Grok Build. Default backend tmux: watchdog polls `capture-pane` every 5 s + regex (Codex run with `--no-alt-screen` so scrollback is scrapable; patterns like `IDLE_PROMPT_STRICT_PATTERN`, `ASSISTANT_PREFIX_PATTERN`). **Alternate backend: herdr** ("terminal-native agent runtime and multiplexer designed specifically for AI coding agents") — Unix socket status events `working|idle|done|blocked`, event-driven inbox delivery, marked Experimental vs tmux "stable default". HTTP API `/terminals/{id}` status polling (`completed|error|waiting_user_answer`). Multi-host: EKS example (supervisor + worker fleet). <https://github.com/awslabs/cli-agent-orchestrator> · <https://github.com/awslabs/cli-agent-orchestrator/blob/main/docs/herdr.md> · <https://github.com/awslabs/cli-agent-orchestrator/blob/main/docs/codex-cli.md>
- **amux (mixpeek)** — 525★, "MIT + Commons Clause" per README (About says MIT), single Rust binary, SQLite, last push 2026-10-11. Parallel Claude Code/Codex/Gemini/OpenCode/Ollama workers, board, schedules, loops, watchdog (auto-compact, restart, replay). Backend: tmux default (3.2+); **herdr as alternative backend** (`AMUX_HERDR_SESSION`, `CC_BACKEND=herdr`; not CI-covered). README: terminal scraping is "the fallback, not the long-term plan"; planned structured `AgentProtocol`. Remote control of one host via Tailscale/tunnel + iOS app; no multi-host workers. <https://github.com/mixpeek/amux>
- **maniple (ex claude-team, Martian-Engineering)** — 49★, MIT. MCP server letting one Claude Code session spawn/manage Claude Code or Codex sessions in tmux (primary) or iTerm2 panes; idle via "stop-hook markers"; reads agents' JSONL session files for `read_worker_logs` / `examine_worker` / `poll_worker_changes`; worktrees. Local only. <https://github.com/Martian-Engineering/maniple>
- **orch (jeffdhooton)** — 0★, MIT, Go tmux orchestrator for Claude Code with roles/messages/dashboard; last push 2026-04-14. <https://github.com/jeffdhooton/orch>
- Anthropic first-party: Agent Teams + cross-session messaging + hooks (A4 above) now cover much of the local-multi-session case; cross-machine only via Anthropic-relayed Remote Control.

---

## Comparison table

### Protocols

| Protocol | Standardizes | Transport | Start task | Results / streaming | Who implements (coding agents) | Maturity (2026-10) |
|---|---|---|---|---|---|---|
| MCP 2026-07-28 | host↔tool server | stdio, Streamable HTTP (stateless) | `tools/call`; Tasks ext → `CreateTaskResult` | sync result; Tasks: poll `tasks/get`, `tasks/update` for input, `notifications/tasks`; MRTR for elicitation; sampling deprecated | Claude Code `claude mcp serve` (tools only); Codex `mcp-server` **removed** | Core stable (AAIF); Tasks ext v0.2.x, no clients in matrix |
| A2A v1.0.1 | agent↔agent delegation | JSON-RPC/HTTP, gRPC, HTTP+JSON; SSE; webhooks | `SendMessage` (blocking or `returnImmediately`) | Task states ×9; `GetTask` poll, `SendStreamingMessage`/`SubscribeToTask` SSE, push webhooks | SDKs py/js/java/go/.net/rs; no terminal coding agent ships a server | v1.0 frozen 2026-03-12; AAIF Growth Stage 2026-08-27 |
| ACP v1 (schema 1.25) | editor↔coding agent | stdio NDJSON JSON-RPC (HTTP draft) | `session/new` → `session/prompt` | `session/update` chunks/tool calls/plans; done = `stopReason`; `session/request_permission` | Claude (adapter), Codex (adapter over app-server), Gemini CLI, OpenCode, Cursor, Copilot, Kiro, Goose, 42 listed | Active, weekly releases; local-only by design |
| Codex App Server | Codex-specific client API | stdio NDJSON (WS experimental, unix socket) | `thread/start` → `turn/start` | `item/*`, `turn/completed`, approval requests | Codex only; used by Symphony, Multica, codex-acp, Codex SDK | Experimental label but canonical |
| Claude Code `-p` stream-json | Claude-specific | subprocess stdio | `claude -p --output-format stream-json [--input-format stream-json]` | NDJSON events, final `result` w/ `session_id` | Claude only; used by Vibe Kanban, Multica, Maestro, Paperclip | Stable, documented |
| AG-UI | agent↔frontend events | HTTP/WebSocket | run events | token/tool/state-delta events | CopilotKit + frameworks | Active; not for spawning agents |
| OpenAI Agents SDK handoffs | in-process delegation | none (library) | `transfer_to_<agent>` tool | same run | OpenAI SDK users | Stable library feature |
| Claude Managed Agents | hosted agent sessions | REST + SSE | create session, send event | SSE events, persisted history | Anthropic | Beta (`managed-agents-2026-04-01`) |

### Orchestrators

| Tool | Spawn | Completion detection | Output collection | Cross-machine | Status |
|---|---|---|---|---|---|
| tmux baseline | `send-keys` | poll `capture-pane` + regex; `wait-for` channels; `pipe-pane`; `-CC %output` | scrollback | manual SSH | — |
| claude-squad | tmux + worktrees | pane hash diff + prompt substrings | preview/diff | no | 8.6k★, slow (Aug 2026) |
| agent-deck | tmux | polling + Codex/pi hooks, pane fallback; notify-daemon → parent | copy keys, transcripts | SSH remotes, `remote drain` | 1.1k★ active |
| Conductor | UNVERIFIED (SDK mentioned) | UNVERIFIED | diff/PR UI | Conductor Cloud | closed, v0.90.0 |
| Crystal | UNVERIFIED | UNVERIFIED | — | no | deprecated → Nimbalyst |
| Vibe Kanban | `claude -p` stream-json; per-agent executors | stream `result` / exit | normalized log stream | self-host cloud/tunnel | sunsetting (Apr 2026) |
| CCManager | PTY (no tmux) | per-CLI output state detector; status hooks | none persisted | devcontainer only | 1.3k★ active |
| Gas Town | tmux + managed hooks; `gt sling` | `gt done` + beads state; Witness nudges | branch/MR beads | Wasteland (DoltHub) federation | 18.3k★ active |
| Symphony | `codex app-server` stdio | app-server turn end / stall timeout; tracker state | tracker + PR | single host | 27.6k★ experimental |
| Paperclip | CLI adapters (`claude -p`, `--resume`) | process end per heartbeat; approval stages | run logs, tasks, docs | sandbox/SSH targets | 100k★ active |
| Ralph / ralph-loop | bash loop / Stop hook | none / promise string + max iters | files + git | no | technique |
| Maestro | `claude --print` stream-json, `codex exec` | `result` msg / exit; liveness events | session history | web UI + tunnel | 3.4k★ active |
| Xum (ex Mux) | own agent loop (no CLIs) | in-process | rich UI | SSH workspaces | 2.1k★ active |
| Multica | daemon per machine; `claude` stream-json, Codex app-server | `result` / `turn/completed`; watchdogs | exec log replay | yes, multi-runtime | 52.5k★ active |
| AWS CAO | tmux (regex poll) **or herdr** (socket events) | regex idle patterns; herdr `idle/done/blocked` | HTTP API, MCP handoff | EKS example | 1.4k★ active |
| amux | tmux **or herdr** | scraping fallback; planned AgentProtocol | ledger rows, API logs | single host, remote UI | 525★ active |
| maniple | tmux/iTerm2 via MCP | stop-hook markers + JSONL | JSONL readers | no | 49★ |
| Claude Agent Teams | in-process or tmux/iTerm2 panes | idle notification to lead; `TeammateIdle`/`TaskCompleted` hooks | mailbox JSON | no (cross-session msg via Anthropic relay) | experimental |

---

## Unverified / not found
- Conductor and Crystal internal spawn/completion mechanisms (closed or undocumented).
- Codex `notify` JSON payload field names (reference page only says "receives a JSON payload").
- Goose's ACP server command (registry lists it; docs URL 404 today).
- Gas Town multi-host rig execution (federation documented; per-rig remote execution not).
- Whether any MCP client has shipped the Tasks extension (matrix shows none).
