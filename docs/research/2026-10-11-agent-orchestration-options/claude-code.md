# Claude Code: every official way one agent starts another and gets the result back

Researched 2026-10-11 against primary sources only (code.claude.com/docs, platform.claude.com/docs, anthropics GitHub repos, npm/PyPI registries). Versions current at research time:

| Component | Version | Source |
|---|---|---|
| Claude Code CLI (`@anthropic-ai/claude-code`, native binary) | **2.1.296** (released 2026-10-09) | https://code.claude.com/docs/en/changelog , `npm view @anthropic-ai/claude-code version`, local `claude --version` |
| TypeScript Agent SDK `@anthropic-ai/claude-agent-sdk` | **0.3.296** (SDK minor.patch tracks the bundled CLI: 0.3.N bundles Claude Code 2.1.N) | npm registry; https://github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md |
| Python Agent SDK `claude-agent-sdk` | **0.2.165** | PyPI; https://github.com/anthropics/claude-agent-sdk-python/blob/main/CHANGELOG.md |
| GitHub Action `anthropics/claude-code-action` | `@v1` | https://code.claude.com/docs/en/github-actions |

Note: `platform.claude.com/docs/en/agent-sdk/*` now 307-redirects to `code.claude.com/docs/en/agent-sdk/*`. Cite the code.claude.com URLs.

---

## 0. Summary matrix: spawn channel vs. result channel

| Spawn mechanism | Result comes back as | Blocking? | Needs claude.ai login? |
|---|---|---|---|
| `claude -p ... --output-format json` subprocess | `result` JSON on stdout (`result`, `structured_output`, `session_id`, `total_cost_usd`); exit code | Yes (process exit) | No (API key or OAuth) |
| `claude -p --output-format stream-json` | NDJSON stream; last line is `type:"result"` | Streams | No |
| Agent SDK `query()` (TS/Py) | `SDKResultMessage` / `ResultMessage` in the async iterator | Streams | No (API key required for 3rd-party products) |
| In-session `Agent` tool (subagent) | Tool result text (+ `agentId:` trailer); background runs deliver a `task_notification` later | Foreground blocks; background doesn't | No |
| `Agent` tool `subagent_type: "fork"` | Same as subagent; inherits full conversation | Background by default | No |
| `SendMessage` to a finished subagent (resume) | New completion notification | No | No |
| Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | Idle notification to lead carrying teammate's final answer; shared task list; mailbox JSON | No | No (interactive only) |
| `Workflow` tool (dynamic workflows) | `WorkflowOutput` immediately, then `task_notification` with consolidated result | No | No |
| Cross-session `SendMessage`/`ListAgents` to another local `claude` process | Plain-text reply message; `notify_when_idle` one-shot notice | No | No (local); yes for cloud/other machines |
| `claude --bg "<prompt>"` (agent view background session) | `claude agents --json` state (`done`/`failed`), `claude logs <id>`, transcript via `--resume` | No | No |
| `claude --cloud "<task>"` / claude.ai/code | Session URL; PR; `claude --teleport <id>` pulls transcript locally | No | Yes |
| Routines `POST /v1/claude_code/routines/{trig_id}/fire` | `{claude_code_session_id, claude_code_session_url}`; does NOT wait for completion | No | Yes (per-routine bearer token) |
| `anthropics/claude-code-action@v1` | Action output `structured_output` (JSON string); PR/issue comments | Job completes | No |
| `claude mcp serve` | Exposes Claude Code's *tools* (Read/Edit/Bash...) over MCP stdio, **not** a "run an agent" tool | n/a | No |
| Hooks (`Stop`, `SubagentStop`, `SessionEnd`, `Notification`, `TaskCompleted`...) | Side-channel: `last_assistant_message`, `transcript_path`, `agent_transcript_path` pushed to a command/HTTP endpoint | n/a | No |
| Transcript JSONL `~/.claude/projects/<slug>/<session-id>.jsonl` | Raw file read (format explicitly unstable) | n/a | No |

---

## 1. Headless CLI (`claude -p`)

Primary: https://code.claude.com/docs/en/headless and https://code.claude.com/docs/en/cli-reference

### Core flags

| Flag | Behavior |
|---|---|
| `-p`, `--print` | Non-interactive run; reads prompt from argument and/or stdin (stdin capped at 10 MB). Exit 0 on success, non-zero on failure; failures inside the run are printed as the result on stdout, invalid flags go to stderr. SIGTERM -> exit **143**, runs `SessionEnd` hooks only. |
| `--output-format text\|json\|stream-json` | `json` = single object with `result`, `session_id`, cost metadata, `structured_output`. `stream-json` = NDJSON; last line is the `result` message. |
| `--input-format text\|stream-json` | `stream-json` lets the caller feed `{"type":"user","message":{"role":"user","content":...},"parent_tool_use_id":null}` lines on stdin (multi-turn in one process). |
| `--json-schema '<schema>'` | Structured output (print mode only, use with `--output-format json`). Result in `structured_output`. Invalid schema -> `Error: --json-schema is not a valid JSON Schema` (v2.1.205+). JSON Schema draft-07; `format` keyword accepted but not enforced. |
| `--resume <id\|name\|/abs/path.jsonl>`, `-r` | Resume by session UUID, name, or absolute transcript path. Searches current project + worktrees, then every project on the machine (v2.1.223+). |
| `--continue`, `-c` | Most recent conversation in cwd. `claude -p --continue` includes `-p`/SDK/`/loop` sessions (interactive `--continue` skips them). |
| `--session-id <uuid>` | Pre-assign the session UUID. |
| `--fork-session` | With `--resume`/`--continue`: new session ID, copy of history. |
| `--append-system-prompt`, `--append-system-prompt-file`, `--system-prompt`, `--system-prompt-file`, `--system-prompt-snapshot off` | System prompt control. Prompt is recorded on first request and reused on resume until compaction unless `--system-prompt-snapshot off`. `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` line splits cacheable/static vs dynamic (v2.1.275+). |
| `--append-subagent-system-prompt[-file]` | Appended to every subagent (not forks). `-p` only (v2.1.205+/v2.1.261+). |
| `--allowedTools` / `--allowed-tools` | Permission-rule syntax, e.g. `"Bash(git diff *)" "Read"`. Auto mode drops a bare `Bash` allow. |
| `--disallowedTools` | Bare name removes tool from context; scoped rule denies matching calls. |
| `--tools` | Restrict built-in tool set (`""`, `"default"`, or names). Doesn't affect MCP tools. |
| `--permission-mode default\|acceptEdits\|plan\|auto\|dontAsk\|bypassPermissions\|manual` | `dontAsk` denies anything that would prompt (good for CI). |
| `--permission-prompts host\|none` | `none`: deny instead of waiting on the SDK host / `--permission-prompt-tool` (v2.1.259+). Denials appear as `permission_denied` system messages and `permission_denials` on the result. |
| `--permission-prompt-tool <mcp_tool>` | MCP tool that answers permission prompts in `-p` mode. |
| `--dangerously-skip-permissions` | == `--permission-mode bypassPermissions`. |
| `--max-turns N` | Error exit when reached. |
| `--max-budget-usd N` | Client-side cost cap; subagent spend counts; stops background subagents at cap (v2.1.217+). |
| `--agents '<json>'` or path (v2.1.281+) | Session-only subagent definitions (see §3). |
| `--agent <name>` | Run the main session *as* a given subagent definition. |
| `--mcp-config <file\|json>`, `--strict-mcp-config` | With `-p`, waits for servers up to `MCP_TIMEOUT` (30 s). |
| `--bare` | Skips hooks/skills/agents/plugins/MCP/CLAUDE.md/auto-memory; no OAuth (needs `ANTHROPIC_API_KEY`). Recommended for scripted calls; will become `-p` default. Sets `CLAUDE_CODE_SIMPLE`. Bare sessions **do not bind a cross-session inbox socket**. |
| `--verbose`, `--include-partial-messages`, `--include-hook-events`, `--forward-subagent-text`, `--replay-user-messages`, `--prompt-suggestions` | Stream-json enrichers. `--forward-subagent-text` emits subagent `assistant`/`user` messages with `parent_tool_use_id` set at every nesting depth (v2.1.219+). |
| `--no-session-persistence` | Don't write the transcript (print mode). |
| `--exclude-dynamic-system-prompt-sections` | Better prompt-cache reuse across users. |
| `--worktree`/`-w`, `--tmux`, `--name`/`-n`, `--effort`, `--model`, `--fallback-model`, `--settings`, `--setting-sources`, `--add-dir`, `--plugin-dir`, `--plugin-url` | Environment shaping. |
| `--bg` / `--background` | **Rejected with `-p`.** Starts an agent-view background session (see §5.4). |
| `--cloud "<task>"` / `claude -p "<msg>" --cloud <session_id>` | Create a cloud session / queue a message into one (see §5.2). `--remote` is deprecated alias. |
| `--teleport [<id>]` | Pull a cloud session into the terminal. |
| `--environment ccpool_...`, `--ref <branch>` | Dispatch to a self-hosted cloud environment. |

### `result` message (json / last stream-json line)

Fields (from TS `SDKResultMessage` / Python `ResultMessage`; https://code.claude.com/docs/en/agent-sdk/typescript , https://code.claude.com/docs/en/agent-sdk/python):

- `type: "result"`, `subtype`: `"success"` | `"error_max_turns"` | `"error_during_execution"` | `"error_max_budget_usd"` | `"error_max_structured_output_retries"`
- `result` (final text, success arm) or `errors: string[]` (error arm)
- `session_id`, `uuid`, `is_error`, `num_turns`, `duration_ms`, `duration_api_ms`
- `total_cost_usd` (client-side estimate; with `--continue`/`--resume` includes earlier runs), `usage`, `modelUsage` / `model_usage` (per-model breakdown)
- `structured_output` (when `--json-schema`/`outputFormat` used; can be absent on `success` -> treat as failure)
- `permission_denials`, `stop_reason`, `terminal_reason` (`completed`, `max_turns`, `tool_deferred`, `aborted_streaming`, `aborted_tools`, `hook_stopped`, `budget_exhausted`, `api_error`, `turn_setup_failed`, ...), `deferred_tool_use`, `api_error_status`, `origin`

Shell patterns:

```bash
session_id=$(claude -p "Start a review" --output-format json | jq -r '.session_id')
claude -p "Continue that review" --resume "$session_id" --output-format json | jq -r '.result'
claude -p "Extract names" --output-format json --json-schema '{"type":"object",...}' | jq '.structured_output'
claude -p "Explain" --output-format stream-json --verbose --include-partial-messages \
  | jq -rj 'select(.type=="stream_event" and .event.delta.type?=="text_delta") | .event.delta.text'
```

### Other stream-json events worth knowing

- `system/init` (first event): `session_id`, `tools`, `mcp_servers[{name,status}]`, `mcp_server_errors`, `plugins`, `plugin_errors`, `model`, `permissionMode`, `agents`, `slash_commands`, `skills`, `capabilities[]` (e.g. `interrupt_receipt_v1`).
- `system/api_retry`, `system/plugin_install`, `system/permission_denied`, `hook_started`/`hook_progress`/`hook_response` (with `--include-hook-events`).
- `system/task_started`, `system/task_progress`, `system/task_notification` (`task_id`, `tool_use_id`, `status: completed|failed|stopped`, `output_file`, `summary`, `usage`), `system/background_tasks_changed` — this is how background subagent completion surfaces (see §3).
- Subagent messages carry `parent_tool_use_id` = the `Agent` tool_use id (main conversation = `null`).

### Background work at exit

A `-p` run stays open after the final turn waiting for background subagents/workflows (their result is part of the output), background Bash, Monitor watches, `/loop` wakeups; 10-minute idle cap via `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` (0 = unbounded). https://code.claude.com/docs/en/headless#background-tasks-at-exit

---

## 2. Claude Agent SDK (TypeScript + Python)

Primary: https://code.claude.com/docs/en/agent-sdk/overview , .../typescript , .../python , .../sessions , .../structured-outputs , .../subagents , .../custom-tools , .../hooks , .../permissions , .../streaming-input

The SDK spawns the bundled Claude Code binary (`@anthropic-ai/claude-agent-sdk-darwin-arm64` etc. as optional deps; `pathToClaudeCodeExecutable` / `cli_path` to override) and speaks the same stream-json protocol as `claude -p --input-format stream-json --output-format stream-json`. Licensing note: third parties may not offer claude.ai login through SDK products; use API keys.

### Packages

```bash
npm install @anthropic-ai/claude-agent-sdk      # 0.3.296
pip install claude-agent-sdk                     # 0.2.165
```

### `query()`

TS: `query({ prompt: string | AsyncIterable<SDKUserMessage>, options?: Options }): Query` where `Query extends AsyncGenerator<SDKMessage, void>`.
Py: `async def query(*, prompt: str | AsyncIterable[dict], options: ClaudeAgentOptions | None, transport=None) -> AsyncIterator[Message]`; plus `ClaudeSDKClient` (holds the session: `connect()`, `query(prompt, session_id="default")`, `receive_response()` (until a `ResultMessage`), `receive_messages()`, `interrupt()`, `set_permission_mode()`, `set_model()`, `stop_task(task_id)`, `rewind_files()`, `get_mcp_status()`, `get_context_usage()`, `disconnect()`).

Single-shot `query()` **throws/raises after yielding an error result** (`error_max_turns` etc.) — capture `session_id` inside the loop before the exception.

### Key options (TS name / Python name)

- Session: `resume` / `resume`, `continue` / `continue_conversation`, `forkSession` / `fork_session`, `sessionId` / `session_id`, `resumeSessionAt` / `resume_session_at`, `resumeDropsTurn`, `persistSession` (TS only; Py: `env={"CLAUDE_CODE_SKIP_PROMPT_HISTORY":...}`), `sessionStore` / `session_store` (+ `sessionStoreFlush`) for mirroring transcripts to S3/Redis/Postgres and resuming on other hosts.
- Permissions: `permissionMode` / `permission_mode` (`default|acceptEdits|bypassPermissions|plan|dontAsk|auto`), `allowedTools` / `allowed_tools`, `disallowedTools` / `disallowed_tools`, `tools`, `canUseTool` / `can_use_tool`, `permissionPromptToolName` / `permission_prompt_tool_name`, `permissionPrompts: 'host'|'none'` (TS), `allowDangerouslySkipPermissions`.
- Agents/tools: `agents` (Record<string, AgentDefinition>), `agent`, `mcpServers` / `mcp_servers`, `strictMcpConfig`, `hooks`, `plugins`, `skills`, `settingSources` / `setting_sources` (`user|project|local`; default = all), `settings`, `managedSettings`.
- Output/limits: `outputFormat` / `output_format` (`{type:"json_schema", schema}`), `maxTurns` / `max_turns`, `maxBudgetUsd` / `max_budget_usd`, `includePartialMessages`, `includeHookEvents`, `forwardSubagentText`, `agentProgressSummaries`, `taskBudget` (alpha).
- Process: `cwd`, `env` (TS **replaces** subprocess env — spread `process.env`; Py merges), `executable`, `extraArgs` (pass arbitrary CLI flags), `stderr`, `spawnClaudeCodeProcess`, `loadTimeoutMs`.
- Prompting: `systemPrompt` (string | `{type:'preset', preset:'claude_code', append}`), `model`, `fallbackModel`, `effort`, `thinking`, `betas`, `title`.

### Query control methods (TS, streaming-input mode only)

`interrupt()`, `setPermissionMode()`, `setModel()`, `streamInput()`, `stopTask(taskId)`, `applyFlagSettings()`, `rewindFiles()`, `supportedAgents()`, `mcpServerStatus()`, `getContextUsage()`, `close()`.

### Capturing the result / session

```ts
for await (const m of query({ prompt, options })) {
  if (m.type === "system" && m.subtype === "init") sessionId = m.session_id;
  if (m.type === "result") { sessionId = m.session_id; if (m.subtype === "success") out = m.result; so = m.structured_output; }
}
// later: query({ prompt: "...", options: { resume: sessionId } })
// fork:   query({ prompt, options: { resume: sessionId, forkSession: true } })
```

Python: `ResultMessage.session_id`, `.result`, `.structured_output`, `.total_cost_usd`, `.subtype`; init session id nested in `SystemMessage.data`.

Session enumeration/reading from code: TS `listSessions()`, `getSessionMessages()`, `getSessionInfo()`, `renameSession()`, `tagSession()`; Py `list_sessions()`, `get_session_messages()`, `get_session_info()`, `rename_session()`, `tag_session()`. Transcripts under `~/.claude/projects/<encoded-cwd>/*.jsonl` (or `$CLAUDE_CONFIG_DIR/projects/`; `CLAUDE_CODE_PROJECT_DIR_NAME` to pin the slug, TS >= 0.3.234 / Py >= 0.2.140).

The experimental V2 `createSession()` API was **removed in TS SDK 0.3.142**; use `query()`.

### Streaming input mode

Pass an `AsyncIterable<SDKUserMessage>` as `prompt`. Message shape: `{ type: "user", message: { role: "user", content: string | ContentBlock[] }, parent_tool_use_id: null, session_id?, priority?: "now"|"next"|"later", origin?: {kind:"human"} }`. Required for images, interrupts, `setPermissionMode`, queued messages. Single-message mode supports `continue`/`resume` only. https://code.claude.com/docs/en/agent-sdk/streaming-input

### `canUseTool`

```ts
type CanUseTool = (toolName, input, { signal, suggestions?, blockedPath?, mcpServer?, decisionReason?, defaultToNo?, suppressAlwaysAllowRule?, toolUseID, agentID?, requestId })
  => Promise<{behavior:"allow", updatedInput?, updatedPermissions?} | {behavior:"deny", message, interrupt?} | null>;
```
Called only when nothing earlier resolves (hooks -> deny rules -> ask rules -> mode -> allow rules -> callback). Shadowed by `bypassPermissions` or bare `allowedTools` entries (TS emits `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED` warning). `dontAsk` never calls it. Background subagents forward their prompts to `canUseTool` (TS >= 0.3.186). Py: `can_use_tool(tool_name, input_data, ToolPermissionContext) -> PermissionResultAllow | PermissionResultDeny`. https://code.claude.com/docs/en/agent-sdk/permissions

### Custom tools (in-process MCP)

TS: `tool(name, description, zodShape, handler, { annotations?, alwaysLoad? })` + `createSdkMcpServer({ name, version, tools })`; pass as `mcpServers: { weather: server }`; allow with `allowedTools: ["mcp__weather__get_temperature"]` or `mcp__weather__*`.
Py: `@tool(name, description, schema_dict_or_json_schema, annotations=ToolAnnotations(...))` + `create_sdk_mcp_server(name, version, tools)`; `mcp_servers={"weather": server}`. Handler returns `{content:[...], structuredContent?, isError?}` (Py: `is_error`; Py decorator forwards only `content`/`is_error`). This is the cleanest way for a parent to give a child agent a "report back" tool. https://code.claude.com/docs/en/agent-sdk/custom-tools

### Subagents via `agents` option

```ts
agents: { "code-reviewer": { description, prompt, tools?, disallowedTools?, model?, effort?, maxTurns?, background?, skills?, memory?, mcpServers?, permissionMode?, omitClaudeMd? (TS >= 0.3.271), initialPrompt? } }
```
Python `AgentDefinition(description, prompt, tools, disallowedTools, model, skills, memory, mcpServers, initialPrompt, maxTurns, background, effort, permissionMode)` — **camelCase field names** in Python. Programmatic agents override filesystem agents of the same name. Subagents run in background by default (v2.1.198+); `background: true` forces it. Detect delegation: `tool_use` block `name === "Agent"` (older: `"Task"`; `system:init` still lists `Task`). Subagent messages carry `parent_tool_use_id` and (TS >= 0.3.292) `agent_id` == the task's `task_id`. Completed Agent tool result includes text `agentId: <id>`; resume by `query({ prompt: "Resume agent <id> ...", options: { resume: sessionId, agents } })`. Explore/Plan are one-shot (no `agentId`). Caps: `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default 3), `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (default 20), `maxBudgetUsd`. `CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1` removes built-ins. https://code.claude.com/docs/en/agent-sdk/subagents

### Hooks in the SDK

`hooks: { PreToolUse: [{ matcher?: "Write|Edit", hooks: [cb], timeout? }] }` (Py: `HookMatcher(matcher=, hooks=[], timeout=)`). Callback `(input, toolUseID, { signal }) => output`. Events: TS supports the full list (see §4); **Python supports only** `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit`, `Stop`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PermissionRequest`, `Notification` — `SessionStart`/`SessionEnd` are TS-only as callbacks (Python can still run them as settings-file command hooks via `setting_sources=["project"]`). Async side-effect return: `{ async: true, asyncTimeout }` (Py `async_`). `SubagentStop` input in SDK: `agent_id`, `agent_transcript_path`, `stop_hook_active`, `last_assistant_message`. `PreToolUse` `permissionDecision: "defer"` ends the turn with `stop_reason: "tool_deferred"` for later resumption. https://code.claude.com/docs/en/agent-sdk/hooks

### Structured outputs

`outputFormat: { type: "json_schema", schema }` / `output_format={"type":"json_schema","schema":...}`. Draft-07 (Zod: `z.toJSONSchema(S, { target: "draft-7" })`; Pydantic `.model_json_schema()`). Result in `message.structured_output`; failure subtype `error_max_structured_output_retries`; `MAX_STRUCTURED_OUTPUT_RETRIES` env tunes retries (also for workflow `agent()` schemas). https://code.claude.com/docs/en/agent-sdk/structured-outputs

### Workflow tool from the SDK

Available TS SDK >= 0.3.149; include `Workflow` in `allowedTools`. Input `{ script? | name? | scriptPath?, args?, resumeFromRunId? }`. Output `{ status: "async_launched"|"remote_launched", taskId, taskType?, workflowName?, runId?, summary?, transcriptDir?, scriptPath?, sessionUrl?, warning?, error? }` — returns immediately; final result arrives as a `task_notification`. Check `error` (syntax-check failure still reports `async_launched`). https://code.claude.com/docs/en/agent-sdk/typescript#workflow

---

## 3. In-session subagents, forks, SendMessage, agent teams, workflows

Primary: https://code.claude.com/docs/en/sub-agents , https://code.claude.com/docs/en/tools-reference , https://code.claude.com/docs/en/agent-teams , https://code.claude.com/docs/en/workflows , https://code.claude.com/docs/en/cross-session-messaging

### 3.1 `Agent` tool (renamed from `Task` in v2.1.63; `Task` still an alias)

Parameters Claude passes: `prompt`, `description`, `subagent_type` (required unless a `general-purpose` agent exists; error `subagent_type is required`), `model` (per-invocation override), `run_in_background` (removed when fork mode is on — all run in background), `name` (makes the agent addressable by `SendMessage`; with agent teams enabled a named call launches a *teammate*), `isolation: "worktree"`, `effort` (v2.1.292+).

Model resolution: per-call `model` -> definition `model` -> `CLAUDE_CODE_SUBAGENT_MODEL` -> main model; `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` overrides (v2.1.257+).

**Result shape** (`AgentOutput`, TS reference):
- `status: "completed"`: `agentId`, `agentType?`, `content: [{type:"text", text}]`, `resolvedModel?`, `modelsUsed?`, `totalToolUseCount`, `totalDurationMs`, `totalTokens`, `usage`, `toolStats?`, `prompt`, `worktreePath?`, `worktreeBranch?`.
- `status: "async_launched"`: `agentId`, `description`, `prompt`, `outputFile`, `canReadOutputFile?` — background launch; completion arrives later as a `task_notification` (status `completed|failed|stopped`, `output_file`, `summary`, `usage`). Claude Code prepends a "no human input occurred" notice; detect via `origin.kind === "task-notification"`.
- `status: "remote_launched"`: `taskId`, `sessionUrl`, `outputFile` — dispatched to a cloud session.

Final reports are scanned (v2.1.210+): control-tag imitations get a backslash, `[harness: subagent output matched instruction-shaped pattern(s): ...]` marker may be prepended; nothing removed. `maxTurns` hit -> result marked partial, resumable. In auto mode, non-fork local subagents get the `SubagentHandback` tool (v2.1.271+) whose report the classifier reviews before delivery.

Restrict spawnable types: `tools: Agent(worker, researcher), Read, Bash` in frontmatter; deny with `permissions.deny: ["Agent(Explore)"]`. Nesting depth default 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), concurrency default 20 (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, error `Concurrent subagent limit reached`). Tools never given to subagents: `Agent` (at depth limit), `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode` (unless `permissionMode: plan`), `ScheduleWakeup`, `WaitForMcpServers`, `Workflow`, `EndConversation`. Background subagents get a reduced set incl. `SendMessage`.

### 3.2 `.claude/agents/*.md` frontmatter

Locations by priority: managed settings > `--agents` flag > `.claude/agents/` > `~/.claude/agents/` > plugin `agents/`. Fields: `name` (required, <=256 chars, no `:`), `description` (required), `tools`, `disallowedTools`, `model` (`sonnet|opus|haiku|fable|<full id>|inherit`), `effort` (`low|medium|high|xhigh|max`), `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory` (`user|project|local`), `background: true`, `isolation: worktree`, `color`, `omitClaudeMd`, `initialPrompt`, `autoCompactWindow` (v2.1.296+), `experimental: {cacheTtl: 5m|1h}`. Plugin agents ignore `hooks`, `mcpServers`, `permissionMode`. `--agents` JSON uses `prompt` in place of the body. Files are hot-reloaded within seconds (not new directories).

Built-ins: `Explore` (read-only, one-shot), `Plan` (read-only, one-shot), `general-purpose`, `claude`, `statusline-setup`, `claude-code-guide`. `CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS=1`.

### 3.3 Background subagents and completion

Default background (v2.1.198+); `Ctrl+B` backgrounds a running one; `/tasks` lists/stops (`x`); `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` forces foreground. Results arrive "inside a completion notification, marked as an automated event" in a later turn. In `-p`, the run stays open until background subagents complete. `TaskStop` tool stops by task id, agent id or name (`{message, task_id, task_type, command?}`). Background subagent permission prompts surface in the main session (SDK: forwarded to `canUseTool`).

### 3.4 Fork subagent

`subagent_type: "fork"`: inherits entire conversation (system prompt, tools, model, history), shares parent prompt cache, only its final result returns. User-invokable via `/subtask <task>` (v2.1.212+; was `/fork` 2.1.161–2.1.211). Fork mode on by default in interactive sessions, **off in `-p` and SDK**; `CLAUDE_CODE_FORK_SUBAGENT=1` enables there, `0` disables everywhere; deny with `Agent(fork)`. Forks cannot spawn forks; forks don't get the named-agents list; teams: a named call that is a fork does *not* become a teammate.

### 3.5 Resume via `SendMessage`

Completed subagents return an agent ID; Claude resumes with `SendMessage` (`to` = agent ID or `name`, `message`, optional `summary` <=200 chars, `notify_when_idle` for cross-session). Resumed subagents keep full history; always run in background (`is_backgrounded: true`). Doesn't require agent teams. Transcripts: `~/.claude/projects/<project>/<sessionId>/subagents/agent-<agentId>.jsonl`. Subject to `cleanupPeriodDays`.

### 3.6 Agent teams (experimental)

Enable: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (env or `settings.json` `env`). **Interactive sessions only** — in `-p`/SDK a named subagent runs as an ordinary subagent. Lead spawns teammates via `Agent` tool with `name`. Teammate reports back through team messages (not an Agent tool result): "when a teammate finishes and stops, it automatically notifies the lead and includes its final answer in the notification". Tools: `SendMessage` (to teammate by name), `TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate` (shared task list with dependencies and file-lock claiming; only on models in the Task-tool availability list or with `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`), `ListAgents`. There is **no documented `TeamCreate`/`TeamDelete` tool**; teams are created implicitly, one per session. State: `~/.claude/teams/session-<first8ofSessionId>/config.json` (`members[]` with `name`, agent id, agent type `team-lead`), inboxes `~/.claude/teams/<team>/inboxes/<agent>.json`, tasks `~/.claude/tasks/<team>/` (persist; team config removed at session end). Display: `teammateMode` / `--teammate-mode in-process|auto|tmux|iterm2`. Hooks: `TeammateIdle`, `TaskCreated`, `TaskCompleted`. Limits: no resume of in-process teammates, no nested teams, one team per session, lead fixed, no background subagents from in-process teammates.

### 3.7 Workflow tool (dynamic workflows)

JS script Claude writes (`export const meta = {name, description}` + body using `agent(prompt, {schema?, label?, stallMs?})`, `pipeline(list, fn)`, `parallel(...)`, `phase()`, `log()`, `args`). Runs in background; `/workflows` view; saved to `.claude/workflows/` or `~/.claude/workflows/`, invoked as `/<name>`; plugin-namespaced `/plugin:name`. Bundled: `/deep-research`. Trigger: `ultracode` keyword (only from human-origin input, not `-p`), `/effort ultracode`, or `claude --effort ultracode`. In `-p`/SDK no approval prompt — allow via `Workflow` / `Workflow(<name>)` rule, auto mode, bypass, PreToolUse hook, or `canUseTool`. Limits: 16 concurrent agents default (`CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS` 1–256), 4,096 items per `parallel()`/`pipeline()`, 1,000 agents/run; `Date.now()`/`Math.random()` throw (determinism for resume). Resume via `resumeFromRunId`. Disable: `disableWorkflows: true`, `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` (v2.1.296+).

### 3.8 Cross-session messaging (`ListAgents` + `SendMessage`)

v2.1.224+ (macOS/Linux/WSL2), v2.1.234+ (Windows). On by default. Claude uses `ListAgents` then `SendMessage`; user runs `/list-agents` (`/peers`), `@session-name` mentions (v2.1.232+). Transport: per-session Unix socket (`/tmp/cc-socks-<uid>`, path in `CLAUDE_CODE_MESSAGING_SOCKET`, token `CLAUDE_CODE_MESSAGING_TOKEN`; a script/hook can post `{"type":"auth","token":...}` then message lines to its own session's socket) — local only, never via Anthropic; cloud/other-machine sessions via Remote Control. `-p` sessions bind an inbox (not `--bare`). Inbound control: `crossSessionInbound: accept|hold|refuse` (default by permission-mode class; `-p` holds expire after `dialogExpiry`, default 5 min — set `accept` in `--settings` for unattended workers). `notify_when_idle` gives a one-shot idle/exit notice (12 h max) with a one-line status. Limits: plain text, ~1M chars, burst limits, 50-message queue. Deny with `permissions.deny: ["SendMessage","ListAgents"]`; `isolatePeerMachines: true` prompts before cross-machine sends.

---

## 4. Hooks for completion signaling

Primary: https://code.claude.com/docs/en/hooks (and SDK variant https://code.claude.com/docs/en/agent-sdk/hooks)

### Event names (exact)

`SessionStart`, `Setup`, `SessionEnd`, `UserPromptSubmit`, `UserPromptExpansion`, `Stop`, `StopFailure`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `TeammateIdle`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Notification`, `MessageDisplay`, `Elicitation`, `ElicitationResult`, `ConfigChange`, `InstructionsLoaded`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`.

### Common input (stdin JSON for `command`, POST body for `http`)

`session_id`, `prompt_id`, `transcript_path` (written async; may lag), `cwd`, `scratchpad_dir` (v2.1.257+), `permission_mode`, `effort: {level}`, `hook_event_name`; plus `agent_id`, `agent_type` when inside a subagent/teammate/`--agent` session.

### Completion-relevant events and payloads

**`Stop`** (main agent finished a turn; matcher ignored):
```json
{"session_id":"abc123","transcript_path":"~/.claude/projects/.../<id>.jsonl","cwd":"/...","permission_mode":"default",
 "hook_event_name":"Stop","stop_hook_active":true,
 "last_assistant_message":"I've completed the refactoring...",
 "background_tasks":[{"id":"task-001","type":"shell","status":"running","description":"tail logs","command":"tail -f ..."}],
 "session_crons":[{"id":"cron-001","schedule":"0 9 * * 1-5","recurring":true,"prompt":"check the build"}]}
```
Output: `{"decision":"block","reason":"..."}` or exit 2 keeps Claude working (cap 8 consecutive, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`; check `stop_hook_active` to avoid loops); `hookSpecificOutput.additionalContext` for non-blocking guidance. Docs recommend `last_assistant_message` over parsing the transcript.

**`StopFailure`** (turn ended in API error): `error` (matcher field: `rate_limit|overloaded|authentication_failed|oauth_org_not_allowed|account_on_hold|billing_error|invalid_request|model_not_found|server_error|max_output_tokens|cloud_credential_error|unknown`), `error_details?`, `last_assistant_message`. No decision control.

**`SubagentStop`** (matcher = agent type):
```json
{"session_id":"abc123","transcript_path":"~/.claude/projects/.../abc123.jsonl","cwd":"/...","permission_mode":"default",
 "hook_event_name":"SubagentStop","stop_hook_active":false,"agent_id":"def456","agent_type":"Explore",
 "agent_transcript_path":"~/.claude/projects/.../abc123/subagents/agent-def456.jsonl",
 "last_assistant_message":"Analysis complete. Found 3 potential issues...","background_tasks":[],"session_crons":[]}
```
`decision: "block"`/exit 2 keeps the subagent running with `reason` as its next instruction. Docs: "To feed results back to the parent session, use PostToolUse on the `Agent` tool."

**`SubagentStart`**: `agent_id`, `agent_type`; `hookSpecificOutput.additionalContext` injected into the subagent's first turn.

**`SessionEnd`**: `reason` (matcher) ∈ `clear | resume | logout | prompt_input_exit | other` (`bypass_permissions_disabled` removed v2.1.234). No decision control; default **1.5 s** budget (per-hook `timeout` raises up to 60 s; `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`). Runs on SIGTERM of a `-p` run. Use to archive `transcript_path`.

**`Notification`**: `message`, `title?`, `notification_type` (matcher) ∈ `permission_prompt | idle_prompt | auth_success | elicitation_dialog | elicitation_url_dialog | elicitation_complete | elicitation_response | agent_needs_input | agent_completed | quota_auto_resume_fired | quota_auto_resume_stale | quota_auto_resume_disabled`. `agent_completed` / `agent_needs_input` fire for agent-view background sessions. Cannot block.

**`TaskCreated` / `TaskCompleted`**: `task_id`, `task_subject`, `task_description?`, `teammate_name?`, `team_name` (deprecated), `agent_id?` (v2.1.290+). Exit 2 blocks creation / keeps task open with stderr as feedback; `{"continue":false,"stopReason":...}` stops a teammate (only when a teammate turn-end triggered it).

**`TeammateIdle`**: `teammate_name`, `team_name`, `agent_id?`. Exit 2 = feedback and keep working; `continue:false` stops.

**`PostToolUse` matcher `Agent`**: receives `tool_name`, `tool_input` (the Agent call), `tool_use_id`, and `tool_response` — the documented way to intercept a subagent's returned report in the parent.

### Hook types and delivery

- `command`: shell; stdin JSON; exit 0 (+ optional JSON stdout), exit 2 = block (stderr = reason), other = non-blocking error. Options: `timeout` (default 600 s; 30 s on `UserPromptSubmit`/`PreModelSwitch`/`PostModelSwitch`; 10 s `MessageDisplay`), `matcher`, `if` (permission-rule filter, tool events only), `once`, `onFailure: "block"` (v2.1.295+), `async: true` (non-blocking; `timeout` not enforced; results delivered next turn; **killed at `-p` teardown with outcome `cancelled`** — detach a process if it must outlive the run), `asyncRewake` (background, but exit 2 wakes Claude immediately even when idle; `timeout` still enforced).
- `http`: `{ "type":"http", "url", "headers"?, "allowedEnvVars"?, "timeout"?, "onFailure"? }`. POSTs the hook input JSON (`Content-Type: application/json`). 2xx + JSON body = parsed as hook output; non-2xx/connection failure = non-blocking. **This is the direct "post the result elsewhere" channel**: an `http` hook on `Stop`/`SubagentStop`/`SessionEnd` ships `last_assistant_message`/`transcript_path` to your endpoint with no script.
- `mcp_tool`: `{ "type":"mcp_tool", "server", "tool", "input"? }` with `${tool_input.file_path}` substitution.
- `prompt` (single model call, default 30 s) and `agent` (subagent with tools, default 60 s; `{ok:true|false, reason}`) — decision hooks, not signaling.
- Universal output fields: `continue`, `stopReason`, `systemMessage`, `terminalSequence`, `suppressOutput`; `hookSpecificOutput` requires `hookEventName`.
- `--include-hook-events` emits `hook_started`/`hook_progress`/`hook_response` in stream-json; `Notification`, `SessionEnd`, `PreCompact`, `PostCompact` never emit `hook_started`.
- Hooks live in `settings.json` (`user`/`project`/`local`/managed), subagent frontmatter `hooks:`, skill frontmatter, plugins. SDK callbacks via `options.hooks`. `--bare` disables settings-file hooks.

---

## 5. External surfaces: MCP server, Remote Control, cloud sessions, routines, agent view, GitHub Actions

### 5.1 `claude mcp serve`

https://code.claude.com/docs/en/mcp — Starts a **stdio MCP server exposing Claude Code's tools** (file read/edit, Bash, etc.) to any MCP client; prints nothing. Client config example: `{"mcpServers":{"claude-code":{"type":"stdio","command":"claude","args":["mcp","serve"],"env":{}}}}`. The client is responsible for tool-call confirmation. **It does not expose a "run a Claude agent turn" tool** — it is a tool server, not an agent server; to drive the agent loop from MCP you wrap `claude -p` or the SDK yourself (or the SDK's in-process `createSdkMcpServer`). v2.1.295 fixed background Bash results not naming the output file.

Connecting to other MCP servers: `claude mcp add --transport http|sse|stdio <name> ... [--scope local|project|user] [--env K=V] [--header ...]`, `claude mcp add-json`, `.mcp.json` (project scope, `${VAR}` expansion), `--mcp-config <file|json>` (+ `--strict-mcp-config`), `claude mcp login|logout <name>`, tool names `mcp__<server>__<tool>` (plugins: `mcp__plugin_<plugin>_<server>__<tool>`). Tool search defers MCP tool schemas by default (`ENABLE_TOOL_SEARCH`, `alwaysLoad`). `--permission-prompt-tool <mcp_tool>` routes permission prompts to an MCP tool in `-p` mode (cannot approve `requiresUserInteraction` tools).

### 5.2 Cloud sessions (claude.ai/code) and `--cloud` / `--teleport`

https://code.claude.com/docs/en/claude-code-on-the-web

- `claude --cloud "<task>"`: creates a new cloud session for the current repo's GitHub remote at current branch (uploads a bundle if no remote/GitHub App; `CCR_FORCE_BUNDLE=1`). Each call = independent parallel session. Requires claude.ai login (Pro/Max/Team/Enterprise); org policy `allow_remote_sessions`; not on Bedrock/Vertex/Foundry. `--environment ccpool_<id> [--ref <branch>]` targets a self-hosted environment.
- `claude -p "<message>" --cloud <session_id|cse_...|claude.ai/code URL>`: **queues one message into an existing cloud session and exits without waiting**. `--output-format json` -> `{ok, session_id, url}` or `{ok:false, session_id, error}`. `stream-json` unsupported here. Error `Attaching to an existing cloud session is not enabled for your account` if you omit `-p`.
- `claude --teleport [<session-id>]` / `/teleport` / `/tp`: pulls a cloud session's branch + full conversation into a local terminal copy (needs clean git state, same repo, pushed branch, same account). Distinct from `--resume`.
- Results from cloud sessions: PR on GitHub, session page at `https://claude.ai/code/<session_id>`, or teleport. Auto-fix PR mode (`/autofix-pr`). Cross-session `SendMessage` can reach a cloud session from a Remote-Control-connected local session. Agent tool `status: "remote_launched"` with `sessionUrl` is how a local Claude dispatches a subagent to the cloud.
- **No public REST API for creating an arbitrary cloud session** is documented; the only HTTP entry point is the routine fire endpoint (§5.3). Agent SDK overview points to **Managed Agents** (platform.claude.com/docs/en/managed-agents) as the Anthropic-hosted, API-driven alternative.

### 5.3 Routines (`/schedule`) and the fire API

https://code.claude.com/docs/en/routines and https://platform.claude.com/docs/en/api/claude-code/routines-fire

- Routine = saved prompt + repos + connectors + environment, runs as a cloud session. Triggers: schedule (cron presets, 1 h min interval, one-off), API, GitHub (`pull_request.*`, `release.*` with filters). Created at claude.ai/code/routines, Desktop, or CLI `/schedule ...` (alias `/routines`; `/schedule list|update|run`; backed by the `RemoteTrigger` tool). API trigger tokens only via web UI.
- **Fire endpoint** (experimental, claude.ai accounts only, not in SDKs):
  ```
  POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire     # routine_id is prefixed trig_
  Authorization: Bearer sk-ant-oat01-...     (per-routine token, shown once; Regenerate revokes old)
  anthropic-version: 2023-06-01              (required; anthropic-beta: experimental-cc-routine-2026-04-01 optional now)
  Content-Type: application/json
  {"text": "<=65,536 chars, freeform, arrives wrapped in <routine-fire-payload> as untrusted data"}
  ```
  200 -> `{"type":"routine_fire","claude_code_session_id":"session_...","claude_code_session_url":"https://claude.ai/code/session_..."}`. **Returns at session creation; does not stream or wait.** No idempotency key. Errors: 400 (bad version/too long/paused), 401, 403, 404, 429 (`Retry-After`; 30/h per routine, 100/h per account), 500, 503. Result retrieval: open the session URL, `claude --teleport`, or `/schedule why did my ... do nothing` (reads run logs, v2.1.227+). Run status green = no infra error, not task success.

### 5.4 Agent view / background sessions (`--bg`)

https://code.claude.com/docs/en/agent-view

- `claude --bg "<prompt>" [--name X] [--agent <def>] [--resume <id>] [--fork-session]` starts a supervised background session and prints the short id + `claude agents|attach|logs|stop <id>`. Incompatible with `-p`. `--bg --exec '<cmd>'` runs a shell job.
- Supervisor daemon (`claude daemon status|logs|run|stop --any [--keep-workers]`), files `~/.claude/daemon.log`, `~/.claude/daemon/roster.json`, `~/.claude/jobs/<id>/state.json`; `CLAUDE_JOB_DIR` set per session.
- **`claude agents --json [--all] [--cwd <path>]`** = documented scripting interface: `[{cwd, kind: interactive|background, startedAt, id, state: working|blocked|done|failed|stopped, pid, status: busy|waiting|idle, waitingFor, sessionId (full UUID for --resume), name}]`. Docs explicitly say another Claude session supervising background work can read this. No documented tool for one session to *dispatch* into agent view other than `claude --bg` via Bash.
- Result retrieval: `claude logs <id|name>`, `claude attach`, `claude --resume <sessionId>` (transcript), peek panel; `Notification` hook types `agent_completed` / `agent_needs_input`. `claude -p --resume <running-bg-session> "prompt"` at a TTY sends the prompt and attaches; with piped IO or output flags it exits 1 instead.

### 5.5 Remote Control

https://code.claude.com/docs/en/remote-control

- `claude remote-control [--name "..."] [--spawn same-dir|worktree|session] [--capacity N (default 32)] [--permission-mode ...] [--continue | --session-id <id>] [--[no-]create-session-in-dir] [--chrome] [--debug]` = server mode: registers with Anthropic API, polls for work, serves up to N sessions created from claude.ai/code or the mobile app. `claude --remote-control|--rc ["name"]` = interactive session also reachable remotely; `/remote-control` (`/rc`) mid-session. Outbound HTTPS only. Requires claude.ai subscription auth, `api.anthropic.com` (no gateway/Bedrock). `--continue`/`--session-id` re-serve sessions for ~4 h after stop.
- **No programmatic API** to create or drive a Remote Control session is documented; the relay is claude.ai/mobile UI. It is, however, the transport that lets cross-session `SendMessage` reach other machines and cloud sessions, and lets `claude --teleport` work.

### 5.6 GitHub Actions `anthropics/claude-code-action@v1`

https://code.claude.com/docs/en/github-actions and https://github.com/anthropics/claude-code-action/blob/main/docs/usage.md

- Inputs: `prompt` (omit = interactive `@claude` mode; present = automation mode), `claude_args` (any CLI flags: `--max-turns`, `--model`, `--allowedTools`, `--mcp-config`, `--json-schema`, `--append-system-prompt`), `anthropic_api_key` | `claude_code_oauth_token` (`claude setup-token`) | OIDC federation (`anthropic_federation_rule_id`, `anthropic_organization_id`, `anthropic_service_account_id`, `anthropic_workspace_id`), `github_token`, `settings`, `trigger_phrase`, `track_progress`, `use_sticky_comment`, `plugin_marketplaces`, `plugins`, `allowed_bots`, `allowed_non_write_users`, `use_bedrock|use_vertex|use_foundry`, `branch_prefix`, `base_branch`, `use_commit_signing`.
- **Output**: a single `structured_output` (JSON string) when `--json-schema` is in `claude_args`; read with `fromJSON(steps.<id>.outputs.structured_output).field`. Otherwise results land in the run log or as PR/issue comments (`--comment` for `/code-review`). Requires `id-token: write`. `/install-github-app` bootstraps.

---

## 6. Transcript JSONL as a result channel

https://code.claude.com/docs/en/sessions#where-transcripts-are-stored , https://code.claude.com/docs/en/agent-sdk/sessions

- Path: `~/.claude/projects/<project>/<session-id>.jsonl`; `<project>` = absolute cwd with every non-alphanumeric char -> `-` (`/Users/me/proj` -> `-Users-me-proj`); names > 200 chars truncated + hash. `$CLAUDE_CONFIG_DIR/projects/` if set; `CLAUDE_CODE_PROJECT_DIR_NAME` pins the slug (v2.1.234+, needs `CLAUDE_CONFIG_DIR`).
- Subagents: `~/.claude/projects/<project>/<sessionId>/subagents/agent-<agentId>.jsonl` (also exposed as `agent_transcript_path` in `SubagentStop`). Workflow run scripts/results also under the session directory.
- Hooks receive `transcript_path` (written asynchronously, may lag). Each line = JSON object for message/tool use/metadata. **Docs: "The entry format is internal to Claude Code and changes between versions, so scripts that parse these files directly can break on any release."** Recommended alternatives: `claude -p --output-format json`, `claude -p --resume <id> --output-format json "summarize what we changed" | jq -r .result`, hooks' `last_assistant_message`, SDK `getSessionMessages()` / `get_session_messages()`, `/export`.
- `--resume` accepts the absolute `.jsonl` path; copying the file into any dir under `~/.claude/projects/` on another host lets `--resume <id>` find it (cross-project lookup v2.1.223+; must be unique). `SessionStore` adapters (TS/Py) mirror transcripts to S3/Redis/Postgres for multi-host resume.
- Retention: `cleanupPeriodDays` (default 30); `claude purge [path]` deletes; `--no-session-persistence` / `CLAUDE_CODE_SKIP_PROMPT_HISTORY` suppress writes; `CLAUDE_CODE_TRANSCRIPT_LOCAL_GC` caps `-p`/SDK transcript growth.
- `-p`/SDK sessions are hidden from the interactive picker and `claude --continue`, but `claude -p --continue` and `--resume <id>` reach them.

---

## Gaps / things explicitly NOT documented (as of 2026-10-11)

- No `TeamCreate`/`TeamDelete`/`Workflow`-style tools for creating named teams; teams are implicit (one per session) and interactive-only.
- No HTTP API to create an arbitrary claude.ai/code cloud session or Remote Control session; only the routine `/fire` endpoint (returns session id/url, no result wait) and `claude -p --cloud <id>` (fire-and-forget message).
- `claude mcp serve` exposes tools, not an agent-run tool.
- Agent view documents reading state (`claude agents --json`) from another session, but dispatch only via `claude --bg` from a shell.
- Transcript JSONL schema is unstable by design.
- `claude-code-action` exposes only `structured_output` as a step output.
