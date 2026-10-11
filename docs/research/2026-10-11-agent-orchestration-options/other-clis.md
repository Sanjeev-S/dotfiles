# Programmatic launch + output retrieval for non-Claude coding agents (as of 2026-10-11)

Scope: how to spawn a session headlessly, get structured output, resume it, and whether the agent speaks ACP or runs as an MCP server. Primary sources only (official docs, repos, npm/PyPI registries, protocol specs). **UNVERIFIED** = not confirmable from a primary source. Versions checked are noted per agent.

Cross-cutting corrections to common assumptions:
- Codex `codex mcp-server` / `codex-mcp-server` is **removed**; `codex exec --json` and the SDKs are thin clients over `codex app-server`. Codex has no native ACP; `@agentclientprotocol/codex-acp` is a community adapter.
- Pi moved: `@mariozechner/pi-coding-agent` is deprecated; use `@earendil-works/pi-coding-agent` (repo `earendil-works/pi`).
- Factory docs moved to `docs.factory.com`; Droid `stream-json` is deprecated in favor of `stream-jsonrpc`.
- Gemini `--yolo`, `--experimental-acp`, `--allowed-tools`, `--session-summary` are deprecated/removed.
- Cursor binary is `agent` (not `cursor-agent`); Cloud Agents API is now v1 (agents + runs + SSE), v0 is legacy.
- Amp stream-json deliberately mirrors Claude Code's format; `session_id` **is** the thread ID (`T-...`). Amp HTTP API is read-only for threads.
- Every agent except Amp (first-party) is in the ACP registry; Gemini, OpenCode, Cursor, Copilot, Droid are native.

---

## 1. OpenAI Codex CLI (`@openai/codex` 0.162.1, `@openai/codex-sdk` 0.162.1, PyPI `openai-codex` 0.162.1)

Note: `developers.openai.com/codex/*` now 308-redirects to `learn.chatgpt.com/docs/*`.

### 1a. `codex exec` (non-interactive)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Basic run | `codex exec "<prompt>"` | Final agent message on stdout; progress on stderr | Requires Git repo unless `--skip-git-repo-check`. Default sandbox read-only. |
| Stdin prompt | `cat prompt.txt \| codex exec -`; piped stdin with no arg | — | If both arg and stdin: stdin appended as `<stdin>` block. Empty stdin -> "No prompt provided", exit 1. |
| JSONL stream | `codex exec --json "..."` (alias `--experimental-json`) | One JSON object per line | Event `type`: `thread.started{thread_id}`, `turn.started{}`, `turn.completed{usage}`, `turn.failed{error:{message}}`, `item.started{item}`, `item.updated{item}`, `item.completed{item}`, `error{message}` (from `codex-rs/exec/src/exec_events.rs`). |
| `usage` fields | — | `input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens` | |
| Item shape | — | `{"id":"item_N","type":<snake_case>,...}` | `type` in `agent_message{text}`, `reasoning{text}`, `command_execution{command,aggregated_output,exit_code,status}`, `file_change{changes[{path,kind}],status}`, `mcp_tool_call{server,tool,arguments,result,error,status}`, `collab_tool_call`, `web_search{query,action,results}`, `todo_list{items[{text,completed}]}`, `error{message}`. Status `in_progress\|completed\|failed\|declined`. Final answer = last `item.completed` with `type:"agent_message"`. |
| Last message to file | `-o <FILE>` / `--output-last-message <FILE>` | Plain text file (also printed to stdout) | Works with `resume`. |
| Structured output | `--output-schema <FILE>` | Final message is JSON matching schema | Bad/missing schema -> exit 1. Combine with `-o out.json`. |
| Working dir / model / config | `-C <DIR>`/`--cd`, `--add-dir <DIR>` (repeatable), `-m <MODEL>`, `-p/--profile`, `-c key=value` (repeatable), `-i/--image <PATH>` | — | |
| Sandbox / approvals | `-s read-only\|workspace-write\|danger-full-access`; `--dangerously-bypass-approvals-and-sandbox`; `--approve-for-me` | — | `--full-auto`: docs say deprecated (warns, use `--sandbox workspace-write`); flag absent from `exec/src/cli.rs` on main -> **UNVERIFIED** on current builds. Avoid. |
| Other globals | `--ephemeral` (no session file), `--ignore-user-config`, `--ignore-rules`, `--strict-config`, `--thread-source`, `--worktree`, `--color` | — | `--worktree` incompatible with `--ephemeral`, `resume`, `review`. |
| Resume | `codex exec resume <SESSION_ID\|name> ["prompt"\|-]`; `codex exec resume --last ["prompt"]`; `--all` disables cwd filter | Same (incl. `--json`, `-o`) | Session id = `thread_id` from `thread.started`. Sessions in `~/.codex/sessions`. |
| Fork / review | `codex exec fork <SESSION_ID> ["prompt"]`; `codex exec review --uncommitted\|--base <BR>\|--commit <SHA>` | — | |
| Exit codes | — | `0` success; `1` on config/schema/stdin error or if any `error` event seen | Derived from `exec/src/lib.rs`, not officially documented. Signal death -> `128+signal`. No distinct code for `turn.failed`. |
| CI auth | `CODEX_API_KEY=<key> codex exec --json "..."` | — | |

### 1b. `codex app-server` (JSON-RPC)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Launch | `codex app-server` (stdio NDJSON); `codex app-server --listen ws://127.0.0.1:4500` (experimental WS); `--listen unix://...` | JSON-RPC 2.0-style; examples omit `jsonrpc` field | Marked `[experimental]`; docs say not for production. Subcommands `daemon\|proxy\|bootstrap\|generate-ts --out DIR\|generate-json-schema --out DIR`. |
| Handshake | `{"method":"initialize","id":0,"params":{"clientInfo":{name,title,version},"capabilities"?:{experimentalApi,optOutNotificationMethods,...}}}` then notification `{"method":"initialized","params":{}}` | `result` with server info | Requests before handshake -> `Not initialized`. |
| Start thread | `thread/start {model, cwd, approvalPolicy:"never"\|"onRequest"\|"unlessTrusted", sandbox:"readOnly"\|"workspaceWrite"\|"dangerFullAccess", personality, serviceName, dynamicTools?}` | `result.thread.{id,sessionId,preview,ephemeral,modelProvider,createdAt}` + notification `thread/started` | camelCase enums here vs kebab-case on CLI. |
| Resume / fork / list | `thread/resume {threadId}`; `thread/fork {threadId, ephemeral?}`; `thread/list {cursor,limit,sortKey,sortDirection,archived,cwd,searchTerm,...}`; `thread/read`, `thread/items/list`, `thread/turns/list` | `thread/list` -> `{data:[...],nextCursor}` | Also `thread/archive`, `thread/delete`, `thread/name/set`, `thread/compact/start`, `thread/unsubscribe`. |
| Run a turn | `turn/start {threadId, input:[{type:"text",text}\|{type:"skill",name,path}\|{type:"mention",name,path}], cwd?, approvalPolicy?, sandboxPolicy?:{type:"workspaceWrite",writableRoots,networkAccess}, model?, effort?, summary?, outputSchema?}` | `result.turn.{id,status:"inProgress"}` | `turn/steer {threadId,turnId,input}`; `turn/interrupt {threadId,turnId}` -> `turn/completed` with `status:"interrupted"`. |
| Streaming notifications | `turn/started{turn}`, `item/started{item}`, `item/agentMessage/delta` (fields **UNVERIFIED**), `item/completed{item}` (authoritative), `turn/completed{turn:{status:"completed"\|"interrupted"\|"failed",error?}}`, `thread/tokenUsage/updated`, `turn/diff/updated`, `turn/plan/updated`, `command/exec/outputDelta`, `thread/status/changed`, `warning` | Notifications (no `id`) | Token usage is NOT on `turn/completed`; use `thread/tokenUsage/updated`. |
| Item types (v2) | `agentMessage{id,text,phase?:"commentary"\|"final_answer"}`, `commandExecution{...}`, `fileChange{...}`, `mcpToolCall{...}`, `reasoning{...}`, `dynamicToolCall` | camelCase | Differs from exec JSONL snake_case. |
| Approval flow (server->client requests) | `item/commandExecution/requestApproval {itemId,threadId,turnId,reason?,command?,cwd?,availableDecisions?}`; `item/fileChange/requestApproval`; `item/permissions/requestApproval`; `item/tool/requestUserInput`; `mcpServer/elicitation/request` | Reply `{"id":<req id>,"result":{"decision":"accept"\|"acceptForSession"\|"decline"\|"cancel"\|{"acceptWithExecpolicyAmendment":{...}}}}` | Set `approvalPolicy:"never"` to avoid. `serverRequest/resolved` fires when cleared. |
| Other | `model/list`, `account/read`, `config/read`, `skills/list`, `hooks/list`, `command/exec`, `fs/*`, `mcpServer/tool/call` | — | Schema: `codex app-server generate-json-schema --out ./schemas`. |

### 1c. Codex as MCP server

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| `codex mcp-server` / `codex-mcp-server` | **REMOVED** | — | Official page: command and standalone binary removed; old `codex`/`codex-reply` tools with `conversationId` "no longer supported". Replacement = app-server. No `McpServer` subcommand in `cli/src/main.rs`. |
| `codex mcp serve` | Does not exist | — | `codex mcp` = `list\|get\|add\|remove\|login\|logout` only (Codex as MCP *client*). |

### 1d. SDKs

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| TS install | `npm install @openai/codex-sdk` (Node 18+) | — | Spawns bundled `codex exec --experimental-json`, parses JSONL. |
| Client | `new Codex({codexPathOverride?, baseUrl?, apiKey?, config?, configOverrides?, env?})` | — | |
| Thread | `codex.startThread({model?, sandboxMode?:"read-only"\|"workspace-write"\|"danger-full-access", workingDirectory?, skipGitRepoCheck?, modelReasoningEffort?, networkAccessEnabled?, webSearchMode?, approvalPolicy?:"never"\|"on-request"\|"on-failure"\|"untrusted", additionalDirectories?})`; `codex.resumeThread(threadId)` | `thread.id` (null until `thread.started`) | |
| Run | `await thread.run(input, {outputSchema?, signal?})` | `Turn = {items: ThreadItem[], finalResponse: string, usage: Usage\|null}` | `input` = string or `[{type:"text",text}\|{type:"local_image",path}]`. Repeat `run()` to continue. |
| Stream | `const {events} = await thread.runStreamed(input, opts)` | `AsyncGenerator<ThreadEvent>`, same `type` strings as exec JSONL | No mid-turn interrupt except `AbortSignal` (kills process). |
| Python | `pip install openai-codex`; `with Codex() as codex:` -> `codex.thread_start(approval_mode=, cwd=, model=, sandbox=Sandbox.read_only\|workspace_write\|full_access, ephemeral=)`; `thread_resume(id)`, `thread_fork`, `thread_list`; `thread.run(input, output_schema=...) -> TurnResult`; `thread.turn(...) -> TurnHandle` with `.stream()`, `.steer()`, `.interrupt()`; `AsyncCodex` mirror | `TurnResult{id,status,error,started_at,completed_at,duration_ms,final_response,items,usage}` | Speaks app-server JSON-RPC directly (supports interrupt/steer). |

### 1e. `notify` and hooks (`~/.codex/config.toml`)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| `notify` | `notify = ["python3", "/path/notify.py"]` (argv; Codex appends one JSON-string arg) | `{"type":"agent-turn-complete","thread-id":...,"turn-id":...,"cwd":...,"input-messages":[...],"last-assistant-message":"..."}` | Only `agent-turn-complete` emitted. Ignored in project-local `.codex/config.toml`. `transcript_path` **UNVERIFIED**. |
| Lifecycle hooks | `features.hooks = true`; `~/.codex/hooks.json` or `[[hooks.Stop]]` + `[[hooks.Stop.hooks]] type="command" command="..." async=false`; also `<repo>/.codex/hooks.json` when trusted | stdin JSON: `session_id, transcript_path, cwd, hook_event_name, model, permission_mode` + per-event | Events: `SessionStart, SessionEnd, PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, UserPromptSubmit, SubagentStart, SubagentStop, Stop, Interrupt`. `Stop` adds `turn_id, stop_hook_active, last_assistant_message`. Exit 0 continue; exit 2 + stderr blocks. `Stop/SubagentStop/Interrupt` must emit JSON on exit 0. |

### 1f. Codex cloud from CLI

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Submit | `codex cloud exec "<QUERY>" --env <ENV_ID> [--attempts 1-4] [--branch <BR>]` | Text (task id); exact stdout format **UNVERIFIED** | `[EXPERIMENTAL]`; alias `codex cloud-tasks`. |
| Inspect | `codex cloud status <TASK_ID>`; `codex cloud list [--env] [--limit 1-20] [--cursor] [--json]`; `codex cloud diff <TASK_ID> [--attempt N]`; `codex cloud apply <TASK_ID>` | `list --json` emits JSON; others text/diff | |
| Public REST API | **UNVERIFIED** (none documented) | — | `codex-rs/cloud-tasks-client` crate is internal. |

### 1g. ACP

| Feature | Exact command/API shape | Notes |
|---|---|---|
| Native | **No.** | Issue openai/codex#30052 (opened 2026-06-25) still open. |
| Adapter | `npx -y @agentclientprotocol/codex-acp` (v2.2.2) | Community (ACP org, ex-Zed). Wraps app-server. Env: `CODEX_API_KEY`/`OPENAI_API_KEY`, `CODEX_PATH`, `CODEX_CONFIG`, `INITIAL_AGENT_MODE=read-only\|workspace-write\|agent\|agent-full-access`. |

Citations: https://learn.chatgpt.com/docs/non-interactive-mode ; https://learn.chatgpt.com/docs/app-server ; https://learn.chatgpt.com/docs/codex-sdk ; https://learn.chatgpt.com/docs/mcp-server ; https://learn.chatgpt.com/docs/config-file/config-advanced ; https://learn.chatgpt.com/docs/config-file/config-reference ; https://learn.chatgpt.com/docs/hooks ; https://learn.chatgpt.com/docs/cloud ; https://learn.chatgpt.com/docs/cli ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/exec/src/{cli.rs,exec_events.rs,lib.rs,event_processor_with_jsonl_output.rs} ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/utils/cli/src/shared_options.rs ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/cli/src/{main.rs,mcp_cmd.rs,exit_status.rs} ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/cloud-tasks/src/cli.rs ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/src/config/mod.rs ; https://raw.githubusercontent.com/openai/codex/main/codex-rs/app-server/README.md ; https://raw.githubusercontent.com/openai/codex/main/sdk/typescript/README.md ; https://raw.githubusercontent.com/openai/codex/main/sdk/python/README.md ; https://raw.githubusercontent.com/openai/codex/main/sdk/python/docs/api-reference.md ; https://pypi.org/project/openai-codex/ ; https://registry.npmjs.org/@openai/codex-sdk ; https://raw.githubusercontent.com/agentclientprotocol/codex-acp/main/README.md ; https://api.github.com/repos/openai/codex/issues/30052

---

## 2. Google Gemini CLI (`@google/gemini-cli` 0.63.0)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Headless prompt | `gemini -p "<prompt>"` / `--prompt` | text (default) | Also auto-headless on non-TTY. Positional `gemini "<q>"` is *interactive*. |
| stdin | `cat err.log \| gemini -p "Explain"` | text | stdin prepended, `-p` appended. |
| Approval | `--approval-mode default\|auto_edit\|yolo\|plan`; `--yolo`/`-y` **deprecated** | — | `--allowed-tools` deprecated -> Policy Engine (`--policy <files>`). `--skip-trust` bypasses folder-trust prompt (else exit 55). |
| Output format | `--output-format text\|json\|stream-json` / `-o` | — | `--raw-output` (needs `--accept-raw-output-risk`). |
| JSON shape | `gemini -p "..." -o json \| jq -r '.response'` | `{session_id?, response?, stats?, error?:{type,message,code?}, warnings?:string[]}` | `stats` = `SessionMetrics{models:{<model>:{api:{totalRequests,totalErrors,totalLatencyMs},tokens:{input,prompt,candidates,total,cached,thoughts,tool}}}, tools:{totalCalls,totalSuccess,totalFail,totalDurationMs,totalDecisions:{accept,reject,modify,auto_accept},byName}, files:{totalLinesAdded,totalLinesRemoved}}` (from `packages/core/src/output/types.ts`). |
| stream-json events | `gemini -p "..." -o stream-json` | NDJSON; each has `type` + `timestamp`. `init{session_id,model}`; `message{role:"user"\|"assistant",content,delta?}`; `tool_use{tool_name,tool_id,parameters}`; `tool_result{tool_id,status:"success"\|"error",output?,error?}`; `error{severity,message}`; `result{status:"success"\|"error",error?,stats?}` | `result.stats`: `total_tokens,input_tokens,output_tokens,cached,input,duration_ms,tool_calls,models{}`. Session id only on `init`. |
| Exit codes | — | Docs: `0` ok, `1` general/API, `42` input, `53` turn limit. Source (`core/src/utils/errors.ts`) adds `41` auth, `44` sandbox, `52` config, `54` tool exec, `55` untrusted workspace, `130` SIGINT | Turn limit via `maxSessionTurns` setting. |
| Resume | `gemini --resume`/`-r` (latest), `--resume <index>`, `--resume <uuid>` | — | Per-project store `~/.gemini/tmp/<project_hash>/chats/`. `-r` + `-p` headless combo **UNVERIFIED**. |
| Session mgmt | `--list-sessions`, `--delete-session <index\|id>`, `--session-id <uuid>` (pre-assign), `--session-file <path.json>`; `/resume`, `/chat` alias | — | `--session-id` is the clean way to know the ID before launch. |
| `--session-summary` | **UNVERIFIED/removed** | — | In changelog (PR #7347) but absent from current yargs config. |
| Hooks config | `settings.json` -> `"hooks":{"<Event>":[{"matcher":"<regex>","sequential"?:bool,"hooks":[{"type":"command","command":"...","name"?,"timeout"?}]}]}` | — | Project `.gemini/settings.json` > `~/.gemini/settings.json` > `/etc/gemini-cli/settings.json`. |
| Hook events | `SessionStart, SessionEnd, BeforeAgent, AfterAgent, BeforeModel, AfterModel, BeforeToolSelection, BeforeTool, AfterTool, PreCompress, Notification` | stdin JSON: `session_id, transcript_path, cwd, hook_event_name, timestamp` + per-event (`tool_name,tool_input,tool_response`, `prompt,prompt_response`, `llm_request/llm_response`, `source`, `reason`) | Exit 0 -> stdout parsed as JSON (`continue, stopReason, decision:"allow"\|"deny", reason, hookSpecificOutput`); exit 2 -> block. No `UserPromptSubmit`. |
| ACP | `gemini --acp` (`--experimental-acp` deprecated) | JSON-RPC 2.0 over stdio | **Native.** Registry: `npx @google/gemini-cli@0.63.0 --acp`. Zed config `agent_servers:{"<name>":{type:"custom",command,args:[...,"--acp"]}}`. |
| SDK | `@google/gemini-cli-core` (npm 0.63.0) | — | No public SDK docs, no stability guarantee. Prefer spawning `gemini -p -o stream-json`. |
| MCP server mode | None documented | — | MCP client only. |
| Other flags | `--include-directories`, `--model/-m auto\|pro\|flash\|...`, `--sandbox/-s`, `--worktree/-w`, `--extensions/-e`, `--debug/-d` | — | Docs note free-tier Gemini CLI replaced by Antigravity CLI 2026-06-18; paid tiers continue. |

Citations: https://raw.githubusercontent.com/google-gemini/gemini-cli/main/docs/cli/headless.md ; https://geminicli.com/docs/cli/headless/ ; .../docs/cli/cli-reference.md ; .../docs/cli/session-management.md ; .../docs/cli/acp-mode.md ; .../docs/cli/tutorials/automation.md ; .../docs/hooks/index.md ; .../docs/hooks/reference.md ; .../docs/ide-integration/index.md ; .../docs/core/index.md ; https://github.com/google-gemini/gemini-cli/blob/main/packages/cli/src/config/config.ts ; .../packages/core/src/output/types.ts ; .../packages/core/src/telemetry/uiTelemetry.ts ; .../packages/core/src/utils/errors.ts ; .../packages/cli/src/nonInteractiveCli.ts ; .../packages/cli/src/config/settingsSchema.ts ; https://registry.npmjs.org/@google%2Fgemini-cli-core ; https://zed.dev/docs/ai/external-agents

---

## 3. Cursor CLI (`agent`, registry version 2026.10.01)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Binary | `agent` (`curl https://cursor.com/install -fsS \| bash` -> `~/.local/bin/agent`; GH Actions uses `$HOME/.cursor/bin`) | — | `cursor-agent` name survives only in old Windows paths; rename date **UNVERIFIED**. |
| Auth | `agent login`; `--api-key <key>` or `CURSOR_API_KEY` | — | |
| Headless | `agent -p "<prompt>"` / `--print` | text (default) | Docs conflict on write access without `--force` (Using page: full write; Headless page: changes only proposed). Test before relying. |
| Auto-approve | `-f/--force` / `--yolo`; `--approve-mcps` | — | `allow`/`deny` permission rules still enforced. |
| Trust / cwd | `--trust`, `--workspace <path>`, `--worktree <name>`, `--add-dir <path>` | — | |
| Mode / model | `--mode plan\|ask` (agent default), `--plan`, `--model <name>`, `--sandbox enabled\|disabled` | — | |
| Output format | `--output-format text\|json\|stream-json` (only with `-p`); `--stream-partial-output` (stream-json only) | — | Default `text`. |
| JSON shape | `agent -p --output-format json "..." \| jq -r '.result'` | `{type:"result", subtype:"success", is_error:false, duration_ms, duration_api_ms, result, session_id, request_id?}` | On failure: non-zero exit, stderr message, no well-formed JSON. |
| stream-json events | `agent -p --output-format stream-json [--stream-partial-output] "..."` | NDJSON: `system/init{apiKeySource,cwd,session_id,model,permissionMode}`; `user{message:{role,content:[{type,text}]},session_id}`; `assistant{message:{role,content:[{type:"text",text}]},session_id,timestamp_ms?,model_call_id?}`; `tool_call/started{call_id,tool_call:{readToolCall\|writeToolCall\|function},session_id}`; `tool_call/completed{...result.success{...}}`; `result/success{duration_ms,duration_api_ms,is_error,result,session_id,request_id}` | Delta dedup: `assistant` with `timestamp_ms` and no `model_call_id` = real delta; both = pre-tool flush (skip); neither = end-of-turn flush (skip). No `thinking` in print mode. Stream may end without `result` on failure. |
| Exit codes | — | `0` success; "non-zero" on failure | Numeric table **UNVERIFIED**. |
| Resume | `agent --resume [chatId]`; `agent --continue` (= `--resume=-1`); `agent resume`; `agent ls` | — | `session_id` from output is the resume ID. `-p --resume <id>` combo **UNVERIFIED**. |
| ACP | `agent acp` (subcommand; root opts first: `agent --api-key "$CURSOR_API_KEY" acp`) | JSON-RPC 2.0 stdio NDJSON; logs on stderr | **Native.** Extensions `cursor/ask_question`, `cursor/create_plan` block until answered. Team MCP servers unsupported in ACP mode. |
| MCP | `agent mcp list\|list-tools\|login\|enable\|disable`; `mcp.json` | — | Client only; no MCP-server mode. |
| Cloud Agents API v1 (public beta) | Base `https://api.cursor.com`; auth Basic `-u KEY:` or Bearer. `POST /v1/agents {prompt{text,images}, model{id,params}, name, env{type:"cloud"\|"pool"\|"machine",name}, repos[{url,startingRef,prUrl}], workOnCurrentBranch, autoCreatePR, skipReviewerRequest, envVars, mcpServers, customSubagents, mode:"agent"\|"plan", agentId}` | `{agent:{id,name,status:"ACTIVE"\|"IDLE"\|"ARCHIVED",env,repos,url,createdAt,updatedAt,latestRunId}, run:{id,agentId,status,createdAt,updatedAt}}` | `GET /v1/agents` (`limit<=100,cursor,prUrl,includeArchived`) -> `{items,nextCursor}`; `GET /v1/agents/{id}`; `POST .../archive`; `DELETE /v1/agents/{id}`; `GET /v1/models`, `/v1/repositories`, `/v1/me`. Webhooks "coming soon". |
| Cloud v1 runs / output | `POST /v1/agents/{id}/runs {prompt,mcpServers,mode}` (follow-up; `409 agent_busy`); `GET /v1/agents/{id}/runs[/{runId}]` -> `{id,agentId,status,createdAt,updatedAt,durationMs?,result?,git?:{branches:[{repoUrl,branch?,prUrl?}]}}`; `POST .../runs/{runId}/cancel`; `GET .../runs/{runId}/stream` (SSE) | SSE: `status{runId,status}`, `assistant{text}`, `thinking{text}`, `tool_call{callId,name,status,args?,result?}`, `interaction_update`, `result{runId,status,text?,durationMs?,git?}`, `error{code,message}`, `heartbeat`, `done` | Run statuses `CREATING, RUNNING` -> `FINISHED, ERROR, CANCELLED, EXPIRED`. Artifacts: `GET .../artifacts`, `GET .../artifacts/download?path=`. `GET .../usage`. |
| Cloud API v0 (legacy) | `POST /v0/agents {prompt, model, source{repository,ref,prUrl}, target{autoCreatePr,branchName,...}, webhook{url,secret>=32}}`; `GET /v0/agents/{id}`; `GET /v0/agents/{id}/conversation -> {id,messages:[{id,type,text}]}`; `POST /v0/agents/{id}/followup`; `DELETE`; `GET /v0/models`, `/v0/repositories`, `/v0/me` | JSON | Kept during migration window; still has webhooks. |

Citations: https://cursor.com/docs/cli/overview ; https://cursor.com/docs/cli/installation ; https://cursor.com/docs/cli/using ; https://cursor.com/docs/cli/headless ; https://cursor.com/docs/cli/reference/parameters ; https://cursor.com/docs/cli/reference/output-format ; https://cursor.com/docs/cli/mcp ; https://cursor.com/docs/cli/acp ; https://cursor.com/docs/cli/github-actions ; https://cursor.com/docs/cli/changelog ; https://cursor.com/docs/cloud-agent/api/overview ; https://cursor.com/docs/cloud-agent/api/endpoints ; https://cursor.com/docs/cloud-agent/api/v0

---

## 4. OpenCode (`anomalyco/opencode`, formerly `sst/opencode`)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| One-shot | `opencode run [message..]` flags: `--continue/-c`, `--session/-s <id>`, `--fork`, `--share`, `--model/-m provider/model`, `--agent`, `--file/-f`, `--format default\|json`, `--title`, `--attach <url>` (to a running `serve`), `--dir`, `--port`, `--variant`, `--thinking`, `--auto` (auto-approve), `--command`; global `--print-logs`, `--log-level` | `default`: text; `json`: JSONL | No `--json` flag. stdin merged into prompt when not a TTY. **Without `--auto`, permission requests are auto-rejected.** |
| `--format json` schema | — | Each line `{"type":<t>,"timestamp":<ms>,"sessionID":"ses_...",...}`; `type` in `step_start, text, reasoning, tool_use, step_finish, error`; `error` carries `error:{type,message}`; others carry `part` | From `packages/cli/src/run/noninteractive.ts` (dev branch); docs only say "raw JSON events". Exit: `1` on error, `130` on interrupt. |
| HTTP server | `opencode serve --port 4096 --hostname 127.0.0.1 [--cors <origin>] [--mdns]`; basic auth via `OPENCODE_SERVER_PASSWORD` (+ `OPENCODE_SERVER_USERNAME`) | OpenAPI 3 at `GET /doc` | |
| REST endpoints | `POST /session {parentID?,title?}`; `POST /session/:id/message {messageID?,model?,agent?,noReply?,system?,tools?,parts}` -> `{info:Message, parts:Part[]}` (blocks until reply); `POST /session/:id/prompt_async` -> 204; `GET /session/:id/message`; `POST /session/:id/abort`; `/fork`, `/share`, `/summarize`, `/revert`, `/permissions/:permissionID`; `GET /session`, `GET /session/status`, `GET /session/:id/diff`; `GET /event` (SSE; first event `server.connected`); `GET /global/event`, `GET /global/health` | JSON / SSE | |
| TS SDK | `npm i @opencode-ai/sdk`; `createOpencode({hostname,port,signal,timeout,config})` (starts server+client); `createOpencodeClient({baseUrl,fetch,responseStyle,throwOnError})`; `client.session.create({body:{title}})`; `client.session.prompt({path:{id}, body:{model:{providerID,modelID}, parts:[{type:"text",text}], noReply?, format?:{type:"json_schema",schema}}})` -> structured at `result.data.info.structured_output`; `client.session.messages({path:{id}})`; `client.event.subscribe()` | typed JSON | Caveat: `dev` branch uses new `@opencode/client` API (`client.session.prompt({sessionID,text,files,delivery:"steer"})`); published shape may change. |
| Python SDK | `pip install --pre opencode-ai` (0.1.0a36, 2025-08-27) | — | Stale; **UNVERIFIED** against current server. |
| ACP | `opencode acp [--cwd] [--port --hostname --mdns --cors]` | ACP JSON-RPC stdio | **Native.** Zed `agent_servers:{"OpenCode":{type:"custom",command:"opencode",args:["acp"]}}`. `/undo` `/redo` unsupported over ACP. |
| Sessions | `opencode session list [-n N] [--format table\|json]`; `opencode session delete <id>`; `opencode export [sessionID]` -> JSON; `opencode import <file\|url>`; `run -c`, `run -s <id>`, `--fork` | table/JSON | |
| MCP server mode | None (MCP client only via `opencode.json` `mcp:{}`; `opencode mcp list/auth/logout/debug`) | — | |
| Plugins/hooks | `.opencode/plugins/`, `~/.config/opencode/plugins/`, or `"plugin":[...]`. Hooks `event`, `tool.execute.before/after`, `tool`, `experimental.session.compacting`. Bus events: `session.created/updated/deleted/idle/status/error/compacted/diff`, `message.updated/removed`, `message.part.updated/removed`, `permission.asked/replied`, `tool.execute.before/after`, `file.edited`, `command.executed`, `server.connected`, ... | — | Same bus events arrive on `GET /event`. |

Citations: https://opencode.ai/docs/cli/ ; https://opencode.ai/docs/server/ ; https://opencode.ai/docs/sdk/ ; https://opencode.ai/docs/acp/ ; https://opencode.ai/docs/plugins/ ; https://opencode.ai/docs/mcp-servers/ ; https://github.com/anomalyco/opencode (packages/cli/src/run/run.ts, noninteractive.ts, commands/handlers/run.ts, branch dev) ; https://pypi.org/project/opencode-ai/

---

## 5. Sourcegraph Amp CLI (`@ampcode/cli`, formerly `@sourcegraph/amp`; SDK `@ampcode/sdk`, `amp-sdk`)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| Execute mode | `amp -x "<prompt>"` / `--execute`; `echo "..." \| amp -x`; auto-enables when stdout redirected. Flags: `--fast`, `--mcp-config '<json>'`, `--attach <path>`, `--executor local\|orb\|runner:<id>`, `-ox` (orb execute), `--mode`, `--title`, `--settings-file` | Final assistant message on stdout | CI auth `AMP_API_KEY=sgamp_...`. By default Amp does not ask approval for tools. |
| `--stream-json` | `amp -x "..." --stream-json`; `--stream-json-thinking`; `--stream-json-input` (JSON user messages on stdin) | JSONL: `system{subtype:"init",cwd,session_id,tools[],mcp_servers[{name,status}],agent_mode?}`; `user{message{role,content[text\|tool_result]},parent_tool_use_id,session_id}`; `assistant{message{type,role,content[text\|tool_use{id,name,input}],stop_reason,usage{...}},session_id}`; `result{subtype:"success"\|"error_during_execution"\|"error_max_turns",is_error,result\|error,duration_ms,duration_api_ms?,num_turns,session_id,usage?,permission_denials?}` | Docs: "tries to be compatible with Claude Code's format". Input line `{"type":"user","steer"?:bool,"message":{"role":"user","content":[...]}}`. |
| Thread ID | `session_id` on every stream-json message = thread ID `T-<uuid>`; URL `https://ampcode.com/threads/<id>` (`.md` suffix for Markdown) | — | Plain `-x` prints no ID; use `--stream-json` or `-ox` (prints URL). |
| Threads CLI | `amp threads continue T-... [-x "..." --stream-json]` (omit ID = most recent); `amp threads list`, `search`, `share T-... --visibility ...`, `markdown T-...`, `export T-...` (JSON), `label/rename/archive/delete` | text/MD/JSON | `amp threads new`: **UNVERIFIED**. `amp threads fork`: removed 2026-01-13. `compact`, `-t <id>`, `list --json`: **UNVERIFIED**. |
| Permissions | `--dangerously-allow-all`: **UNVERIFIED** in current docs (third-party only) | — | `result.permission_denials[]` exists. |
| Exit codes / logging | Exit codes **UNVERIFIED** (undocumented). `--log-level`, `--log-file` verified as SDK options; CLI flag names **UNVERIFIED** | — | |
| Modes | SDK `mode: low\|medium\|high\|ultra`; `effort: none\|minimal\|low\|medium\|high\|xhigh\|max`; `--fast` | — | "smart/rush/free" are legacy. |
| MCP | `amp mcp add <name> -- <cmd>`; `amp mcp add <name> <url>`; `--mcp-config` | — | Amp as MCP server: none found (**UNVERIFIED/none**). |
| ACP | Not in Amp docs; not on ACP agents page as first-party | — | ACP registry has `amp-acp` (binary `./amp-acp`) and third-party `@edlsh/amp-acp`, `acp-amp`. First-party ACP **UNVERIFIED/none**. |
| SDKs | TS: `import {execute, createUserMessage} from '@ampcode/sdk'`; `for await (const m of execute({prompt, options:{continue:true\|'T-...', cwd, mode, effort, executor, mcpConfig, settingsFile, logLevel, logFile, title, labels, enabledTools, env}, signal}))`. Python: `pip install amp-sdk`; `async for m in execute(prompt, AmpOptions(cwd=, continue_thread=True\|"T-...", mode=, executor=))` | Same message objects as `--stream-json` | SDKs wrap the local CLI; `AMP_API_KEY` required. |
| HTTP API | `https://ampcode.com/api/v2` Bearer (OAuth M2M): `GET /threads` -> `{nextCursor,threads[{id,title,createdAt,updatedAt,creatorUserID,...}]}`; `GET /threads/{id}/messages`; `GET /threads/{id}/usage`; `DELETE /threads/{id}` | JSON | **Read-only**: no endpoint to create a thread or send a message. |
| Remote exec | `-ox` (orb on Amp servers; `--stream-json` to stay attached); `amp --no-tui --runner-id <id>` + `amp -x "..." --executor runner:<id>`; `amp sync` | thread URL or JSONL | |

Citations: https://ampcode.com/manual ; https://ampcode.com/docs/cli ; https://ampcode.com/docs/cli/execute-mode ; https://ampcode.com/docs/cli/streaming-json ; https://ampcode.com/docs/cli/settings ; https://ampcode.com/docs/cli/remote-control ; https://ampcode.com/docs/cli/runners ; https://ampcode.com/docs/cli/spawning-orbs ; https://ampcode.com/docs/threads ; https://ampcode.com/docs/sdk ; https://ampcode.com/docs/sdk/python ; https://ampcode.com/docs/customize/mcp ; https://ampcode.com/api/external ; https://ampcode.com/news/streaming-json ; https://ampcode.com/news/stick-a-fork-in-it ; https://cdn.jsdelivr.net/npm/@ampcode/sdk/README.md ; https://cdn.jsdelivr.net/npm/@ampcode/cli/README.md ; https://pypi.org/project/amp-sdk/

---

## 6. Pi coding agent (`@earendil-works/pi-coding-agent` 1.1.0, repo `earendil-works/pi`)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| One-shot | `pi -p "<prompt>"` / `--print`; `git diff \| pi --print "Review"` | Final assistant text | Auto one-shot when stdin/stdout redirected. `@path` attachments in first prompt. |
| JSONL | `pi --mode json "..." > events.jsonl` | First line `{"type":"session","version":3,"id","timestamp","cwd"}`; then `agent_start`, `agent_end{messages}`, `agent_settled{aborted}`, `turn_start`, `turn_end{message,toolResults}`, `message_start`, `message_update{usage,assistantMessageEvent}`, `message_end{message}`, `tool_execution_start{toolCallId,toolName,args}`, `tool_execution_update`, `tool_execution_end{toolCallId,toolName,result,isError}`, `queue_update`, `compaction_start/end`, `auto_retry_start/end`, ... | `assistantMessageEvent.type` in `start, text_start, text_delta{delta}, text_end, thinking_*, toolcall_start/delta/end, done, error`. `message_end.message` authoritative. Wait for `agent_settled`, not `agent_end`. |
| RPC mode | `pi --mode rpc --no-session`; stdin `{"id":"req-2","type":"prompt","message":"..."}` | stdout JSONL: `{"id","type":"response","command","success","data?","error?"}` + events; diagnostics on stderr | Commands: `prompt{message,images?,streamingBehavior?:"steer"\|"followUp"}`, `steer`, `follow_up`, `abort`, `clear_queue`, `new_session`, `get_state`, `get_messages`, `set_model{provider,modelId}`, `set_thinking_level`, `compact`, `bash{command}`, `switch_session{sessionPath}`, `fork`, `clone`, `get_tree`, `get_last_assistant_text`->`{text\|null}`, `set_session_name`, `export_html`, `extension_ui_response`. `@path` rejected in rpc. |
| SDK | `import { createAgentSession, SessionManager, SettingsManager, ModelRuntime } from "@earendil-works/pi-coding-agent"`; `const {session} = await createAgentSession({cwd?, model?, thinkingLevel?, sessionManager?, resourceLoader?, tools?})`; `await session.prompt(text)`; `session.getLastAssistantText()`; `session.subscribe(ev=>...)`; `session.steer()`, `followUp()`, `abort()`, `waitForIdle()`, `dispose()` | Same events as JSON mode | `SessionManager.inMemory(cwd)` for ephemeral. |
| Sessions | `--session <path\|id>`, `-c/--continue`, `-r/--resume` (picker), `--fork <path\|id>`, `--no-session`, `--session-dir`, `-n/--name` | — | Files `~/.pi/agent/sessions/<cwd-encoded>/<ts>_<uuid>.jsonl` (JSONL tree, header `type:"session",version:3`). `--session-id` as CLI flag **UNVERIFIED** (only in session-format doc). |
| Model / tools | `--model <provider/id[:thinking]>`, `--provider`, `--thinking off\|minimal\|low\|medium\|high\|xhigh\|max`, `-t/--tools read,bash,...`, `--no-tools` | — | |
| Export | `--export <session.jsonl> [out.html]` | HTML | |
| ACP | `npx pi-acp` (0.0.34) | ACP stdio | **Third-party** adapter (svkozak/pi-acp), spawns `pi --mode rpc`. In ACP registry as `pi-acp`. No first-party ACP. |
| MCP server mode | None documented | — | |

Citations: https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/{cli,json,rpc,rpc-commands,sdk,sessions,session-format,index}.md ; https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/coding-agent/README.md ; https://registry.npmjs.org/@earendil-works/pi-coding-agent ; https://registry.npmjs.org/@mariozechner/pi-coding-agent ; https://registry.npmjs.org/pi-acp

---

## 7. Factory Droid CLI (`droid` 0.238.x; docs at docs.factory.com)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| One-shot | `droid exec "<prompt>"`; `droid exec -f <file>`; `echo "..." \| droid exec` | text (default) | No `--auto` = read-only. |
| JSON result | `droid exec "..." -o json` / `--output-format json` | `{"type":"result","subtype":"success","is_error":false,"duration_ms":N,"num_turns":N,"result":"<text>","session_id":"<uuid>"}` | |
| Output formats | `-o text\|json\|stream-json\|stream-jsonrpc` | — | `stream-json` deprecated; per-event schema no longer documented -> **UNVERIFIED**. |
| JSON-RPC driver | `droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc --auto low` | NDJSON JSON-RPC on stdin/stdout | Methods `droid.initialize_session`, `droid.load_session` (resume), `droid.add_user_message`; notification `droid.session_notification` (deltas, tool events, usage, completion); server->client `droid.request_permission`, `droid.ask_user`. Full param schema partially **UNVERIFIED**. |
| Autonomy / model | `--auto low\|medium\|high`; `--skip-permissions-unsafe`; `-m/--model`, `-r/--reasoning-effort` | — | Failed permission check -> non-zero exit, no partial changes. |
| Resume | `droid exec -s <id> "next"` / `--session-id <id>`; `droid exec --fork <id>`; interactive `droid --resume [id]` | — | Listing: only `droid search "q" [--json]`; no `droid sessions list` found. |
| Other flags | `--cwd`, `-w/--worktree`, `--restrict-tools`, `--additional-tools`, `--disabled-tools`, `--append-system-prompt[-file]`, `--tag`, `--settings`, `--mission` | — | `--max-turns` **UNVERIFIED**. |
| Exit codes | — | `0` ok; `1` runtime error; `2` invalid args | |
| Hooks | `~/.factory/hooks.json`, `.factory/hooks.json` | stdin JSON `session_id, transcript_path, cwd, permission_mode, hook_event_name, tool_name, tool_input, tool_response` | Events `PreToolUse, PostToolUse, UserPromptSubmit, Notification, Stop, SubagentStop, PreCompact, SessionStart, SessionEnd`. Exit 2 blocks; stdout JSON `continue, stopReason, decision, hookSpecificOutput.permissionDecision`. |
| MCP | `droid mcp add <name> <url> --type http\|sse\|stdio` | — | Droid as MCP server **UNVERIFIED/none**. |
| ACP | `droid exec --output-format acp` (IDE docs); registry: `npx droid@0.238.0 exec --output-format acp-daemon` | ACP stdio | **Native**, though `acp`/`acp-daemon` absent from `-o` list in cli-reference. |
| SDK | `npm i @factory/droid-sdk`; `import { run, resumeSession, listSessions } from '@factory/droid-sdk/node'`; `const r = await run('...'); r.success, r.text` | stream messages `assistant, user, tool_call, tool_result, hook, error, result{subtype,success,text,sessionId,durationMs,turnCount,tokenUsage}` | `result.subtype` in `success, interrupted, error_during_execution, error_structured_output`. |

Citations: https://docs.factory.com/droid-exec/overview ; https://docs.factory.com/reference/cli-reference ; https://docs.factory.com/reference/hooks-reference ; https://docs.factory.com/ide-integrations ; https://docs.factory.com/sdk/typescript ; https://docs.factory.com/guides/building/droid-exec-tutorial ; https://docs.factory.com/changelog/cli-updates

---

## 8. GitHub Copilot CLI (`@github/copilot` 1.0.95; SDK `@github/copilot-sdk`)

| Feature | Exact command/API shape | Output format | Notes |
|---|---|---|---|
| One-shot | `copilot -p "<prompt>"` / `--prompt=`; `-s/--silent` (response only); `echo "..." \| copilot` | text | Piped stdin ignored if `-p` given. |
| JSON | `copilot -p "..." --output-format=json` | JSONL | Per-event schema for `-p` runs **UNVERIFIED** (only `copilot workflow run` documents `{"type":"workflow.result","data":{...}}`). |
| Permissions | `--allow-all-tools` (required for programmatic use); `--allow-tool='shell(git:*), write(README.md), url(github.com)'`; `--deny-tool`; `--allow-all`/`--yolo`; `--allow-url`, `--no-ask-user` | — | Env `COPILOT_ALLOW_ALL=true`. |
| Model / dirs | `--model=`, `--add-dir=` (repeatable), `--attachment`, `--agent=`, `--no-color`, `--log-level=`, `--autopilot`, `--cloud`, `-w/--worktree` | — | |
| Export | `--share=PATH` (md, default `./copilot-session-<ID>.md`), `--share-gist` | Markdown | |
| Resume | `-r/--resume[=id\|prefix\|name]`, `--continue` (most recent in cwd); `/resume`, `/session ...` | — | `-p` exit summary prints a resume hint. |
| Storage | `~/.copilot/session-state/<sessionId>/events.jsonl`; `session-store.db` (SQLite); `COPILOT_HOME` override | JSONL | |
| Headless server (SDK) | `copilot --headless [--port 4321] [--host 0.0.0.0]` | JSON-RPC over TCP (loopback default) | SDK: `new CopilotClient({cliUrl:"localhost:4321"})` or default (spawns bundled CLI over stdio); `await client.createSession({sessionId?, model?, tools?, systemMessage?, onPermissionRequest: approveAll, hooks?, workingDirectory?})`; `session.send()`; `await session.sendAndWait({prompt}, timeout?)` -> `response.data.content`; `session.on("assistant.message_delta", e=>e.data.deltaContent)`; `client.listSessions()`, `client.resumeSession(id)`, `client.deleteSession(id)`. Python `github-copilot-sdk`, Go, .NET, Rust, Java. Supply your own `sessionId` or it cannot be resumed. |
| SDK events | `assistant.turn_start/turn_end/message{messageId,content,toolRequests?}/message_delta{deltaContent}/reasoning*/usage`, `tool.execution_start{toolCallId,toolName,arguments?}/execution_progress/shell_output/execution_complete{success,result?,error?}`, `session.idle{aborted?}`, `session.error`, `session.compaction_*`, `session.task_complete`, `permission.requested/completed`, `user_input.requested/completed`, `subagent.started/completed/failed`, `skill.invoked`, `abort` | — | 49 event types documented. |
| ACP | `copilot --acp [--stdio\|--port <n>]` | ACP NDJSON JSON-RPC | **Native, public preview.** Registry `npx @github/copilot@1.0.95 --acp`. `--fleet` unsupported in ACP. |
| MCP | `/mcp add\|list\|...`; `~/.copilot/mcp-config.json` | — | Copilot as MCP server **UNVERIFIED/none**. |
| Exit codes | — | Documented only for `copilot workflow run`: `0`, `1`, `2`, `130` | Plain `copilot -p` codes **UNVERIFIED**. |
| CI auth | `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN`; `copilot login --with-token` | — | |

Citations: https://docs.github.com/en/copilot/reference/copilot-cli-reference ; .../cli-command-reference ; .../cli-programmatic-reference ; .../acp-server ; .../cli-config-dir-reference ; https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli ; https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically ; https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli ; https://raw.githubusercontent.com/github/copilot-cli/main/README.md ; https://raw.githubusercontent.com/github/copilot-sdk/main/{README.md,nodejs/README.md,docs/getting-started.md,docs/features/streaming-events.md,docs/features/session-persistence.md}

---

## 9. Agent Client Protocol (ACP) — generic stdio JSON-RPC driver

| Item | Value |
|---|---|
| Transport | JSON-RPC 2.0, NDJSON over stdio (agent as client subprocess). `protocolVersion: 1` negotiated in `initialize`. |
| Client->Agent | `initialize`, `authenticate`, `session/new`, `session/prompt{sessionId, prompt:[content blocks]}`, `session/load` (needs `loadSession` cap), `session/set_mode`, `logout`; notification `session/cancel{sessionId}` |
| Agent->Client | `session/request_permission`; notification `session/update` with `params.update.sessionUpdate` in `agent_message_chunk, agent_thought_chunk, user_message_chunk, tool_call, tool_call_update, plan, available_commands_update, current_mode_update`; optional `fs/read_text_file`, `fs/write_text_file`, `terminal/*` |
| `session/prompt` result | `stopReason` in `end_turn, max_tokens, max_turn_requests, refusal, cancelled` |
| SDKs | TS `@agentclientprotocol/sdk`, Rust `agent-client-protocol`, Python `python-sdk`, Kotlin, Java |
| Registry | `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json` (41 entries, Oct 2026) |

ACP registry entries for the agents in scope:

| Agent | Registry id / launch | Native or adapter |
|---|---|---|
| Codex | `codex-acp` — `npx @agentclientprotocol/codex-acp@2.2.2` | adapter (ACP org, community) |
| Gemini CLI | `gemini` — `npx @google/gemini-cli@0.63.0 --acp` | native |
| Cursor | `cursor` — `cursor-agent acp` / `agent acp` | native |
| OpenCode | `opencode` — `opencode acp` | native |
| Amp | `amp-acp` — `./amp-acp` binary | adapter; first-party ACP UNVERIFIED |
| Pi | `pi-acp` — `npx pi-acp@0.0.34` | third-party adapter |
| Factory Droid | `factory-droid` — `npx droid@0.238.0 exec --output-format acp-daemon` | native |
| GitHub Copilot | `github-copilot-cli` — `npx @github/copilot@1.0.95 --acp` | native (public preview) |
| (Claude Code) | `claude-acp` — `npx @agentclientprotocol/claude-agent-acp@0.89.1` | adapter |

Citations: https://agentclientprotocol.com/overview/agents ; https://agentclientprotocol.com/overview/clients ; https://agentclientprotocol.com/protocol/overview ; https://agentclientprotocol.com/protocol/prompt-turn ; https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/main/README.md ; https://raw.githubusercontent.com/agentclientprotocol/registry/main/README.md ; https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json

---

## Comparison

| Agent | Spawn method (headless) | Structured output | Session ID source | Resume | ACP | MCP-server mode | Hosted/HTTP API |
|---|---|---|---|---|---|---|---|
| Codex | `codex exec --json [-o f] [--output-schema s] "p"`; `codex app-server` (stdio JSON-RPC); TS/Py SDK | JSONL `thread.started/turn.*/item.*`; `-o` last message; schema-constrained final | `thread.started.thread_id` | `codex exec resume <id\|--last>`; `thread/resume`; `resumeThread()` | adapter only (`codex-acp`) | **removed** | `codex cloud exec` (experimental, CLI only); REST UNVERIFIED |
| Gemini CLI | `gemini -p "p" -o json\|stream-json --approval-mode yolo` | JSON `{response,stats,error}`; NDJSON `init/message/tool_use/tool_result/error/result` | `init.session_id` or pre-set `--session-id` | `--resume <id\|index>` (headless combo UNVERIFIED) | native `--acp` | none | none |
| Cursor | `agent -p "p" --output-format json\|stream-json [-f] [--trust]` | JSON `{type:"result",result,session_id}`; NDJSON `system/init, user, assistant, tool_call/*, result/success` | `session_id` on every event | `--resume <id>`, `--continue` (headless combo UNVERIFIED) | native `agent acp` | none | Cloud Agents v1 REST + SSE `/v1/agents/{id}/runs/{runId}/stream` |
| OpenCode | `opencode run --format json --auto "p"`; `opencode serve` + REST/SSE; `@opencode-ai/sdk` | JSONL `step_start/text/reasoning/tool_use/step_finish/error` w/ `sessionID`; REST `{info,parts}`; SSE `/event` | `sessionID` on each line; `POST /session` | `run -c`, `run -s <id>`; REST session id | native `opencode acp` | none | self-hosted `opencode serve` (OpenAPI at `/doc`) |
| Amp | `amp -x "p" --stream-json`; `@ampcode/sdk` `execute()` | Claude Code-style JSONL `system/user/assistant/result` | `session_id` = thread `T-...` | `amp threads continue T-... -x "p"`; SDK `continue:'T-...'` | adapter only (`amp-acp`); first-party UNVERIFIED | none | `ampcode.com/api/v2/threads` read-only; `-ox` orbs |
| Pi | `pi -p "p"`; `pi --mode json`; `pi --mode rpc`; SDK `createAgentSession()` | JSONL `agent_*/turn_*/message_*/tool_execution_*`; RPC responses | first line `{"type":"session","id"}` | `--session <id>`, `-c`, `--fork`; RPC `switch_session` | third-party adapter (`pi-acp`) | none | none |
| Droid | `droid exec -o json\|stream-jsonrpc --auto low "p"`; `@factory/droid-sdk` `run()` | JSON `{type:"result",result,session_id}`; JSON-RPC `droid.session_notification` | `result.session_id` | `droid exec -s <id> "p"`; `droid.load_session`; `resumeSession()` | native `exec --output-format acp` | UNVERIFIED/none | none |
| Copilot | `copilot -p "p" --allow-all-tools [--output-format=json]`; `copilot --headless --port N` + `@github/copilot-sdk` | JSONL (schema UNVERIFIED); SDK events `assistant.*`, `tool.*`, `session.idle` | SDK: supply own `sessionId`; CLI: `~/.copilot/session-state/<id>` | `--resume <id>`, `--continue`; `client.resumeSession(id)` | native `--acp` (preview) | UNVERIFIED/none | none (headless server is local TCP) |

Practical note: the only common denominator across all eight is ACP over stdio (native for 5, adapter for Codex/Amp/Pi). For a single orchestration layer, drive agents via ACP (`session/new` -> `session/prompt` -> `session/update` chunks -> `stopReason`) and fall back to each CLI's JSONL mode only where ACP is adapter-only or you need agent-specific features (Codex `--output-schema`, Cursor Cloud, Amp orbs).
