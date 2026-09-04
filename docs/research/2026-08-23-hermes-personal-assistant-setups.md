# Hermes as a personal life-management assistant — recommended setups

Researched 2026-08-23 against primary sources: the official docs site and the
`NousResearch/hermes-agent` repo at `main` (v0.20.5; installed mini runs
v0.20.4 — one patch behind, nothing below depends on the delta).

**Citation convention:** `docs:<path>` = `https://hermes-agent.nousresearch.com/docs/<path>`,
whose source file is `website/docs/<path>.md` in `NousResearch/hermes-agent`.
Community-reported patterns cite `docs:user-stories` (official aggregation page).
Install facts (launchd gateway, openai-codex/gpt-5.6-sol, @san_hermes_pa_bot
DM-paired, built-in memory on, no search keys, OpenRouter key in 1Password) are
taken as given from `docs/plans/2026-08-16-hermes-mac-mini-handoff.md`.

---

## Try these first

1. **Set the home channel now.** DM `/sethome` to @san_hermes_pa_bot (or `hermes config set TELEGRAM_HOME_CHANNEL <your-user-id>`). Until it's set, cron and proactive messages have nowhere to deliver. (`docs:guides/tips`, `docs:user-guide/messaging/telegram`)
2. **Move your persona into `~/.hermes/SOUL.md`** — it's slot #1 of the system prompt. Put "Challenge my assumptions. Be extremely concise." there, not in memory; skip `hermes import-agent` (it would dump CLAUDE.md into the 2,200-char MEMORY.md instead). (`docs:user-guide/features/personality`)
3. **Wire OpenRouter as fallback** (key already in 1Password): `hermes config set OPENROUTER_API_KEY …` + a top-level `fallback_providers:` list in config.yaml. Codex weekly-limit outages then fail over per-turn and auto-return when the reset passes. (`docs:user-guide/features/fallback-providers`)
4. **First cron: weekday morning brief at 08:00, pinned to a model.** Unpinned jobs fail closed if the global model ever changes — always pass `--provider openai-codex --model gpt-5.6-sol` or set `cron.model`. Use `[SILENT]` on monitor-type jobs so quiet runs send nothing. (`docs:user-guide/features/cron`)
5. **Don't buy search keys yet.** `web_search`/`web_extract` already work with zero keys via the keyless free-tier ring (Exa/Parallel/Tavily/Firecrawl/Keenable, auto-failover). Add a free `EXA_API_KEY` (1k/mo) only if the ring throttles you. (`docs:user-guide/features/web-search`)
6. **Close the voice loop:** send the bot a voice note — local `faster-whisper` transcribes it free; `brew install ffmpeg` then re-run `hermes gateway install` (launchd PATH is snapshotted!) so free Edge-TTS replies arrive as native voice bubbles; toggle with `/voice on`. (`docs:user-guide/messaging/telegram`, `docs:user-guide/features/tts`)
7. **Keep Telegram as the daily driver — it's the right call.** It is Hermes' deepest adapter by a wide margin (streaming, DM topics, inline approvals, notification tuning). Add Discord later only if you want live voice-channel conversations; skip WhatsApp (documented ban risk) and SMS (needs a public webhook). See §1.
8. **Give the agent time-sense and tidy chat:** `gateway.message_timestamps.enabled: true` (off by default; enables "you asked this morning…"), `telegram.reactions: true`, `display.platforms.telegram.cleanup_progress: true`. (`docs:user-guide/messaging/index`)
9. **Trim the fixed prompt.** Run `hermes prompt-size`; disable the mlops/software-dev bundled skills you'll never use from Telegram (`skills.platform_disabled`) — every message pays for the skills index. (`docs:reference/faq`)
10. **Apple Reminders/Notes as the todo backend — challenge: is the mini signed into your iCloud?** Bundled macOS-only skills use `remindctl`/`memo` (brew) and sync to your iPhone via iCloud, but need the mini logged into your Apple ID + one-time TCC grants (screen-share once). If not, the `google-workspace` skill (Calendar/Gmail/Drive, OAuth walkthrough is agent-driven) is the better structured backend. (`docs:user-guide/skills/bundled/apple/apple-apple-reminders`, `docs:user-guide/skills/google-workspace`)

---

## 1. Gateway comparison — the daily-driver chat surface

Ground truth: the install ships all core adapters (`gateway/platforms/`: signal,
bluebubbles, whatsapp-cloud, weixin, qqbot, yuanbao, webhook, api_server…) plus
plugin platforms (`plugins/platforms/`: telegram, discord, slack, whatsapp,
matrix, email, sms, ntfy, photon, google_chat, teams, mattermost, irc, simplex,
homeassistant, line, feishu, dingtalk, wecom, buzz, raft, a2a). Availability is
not a differentiator; ergonomics and risk are.

Feature matrix per `docs:user-guide/messaging/index` (Voice/Images/Files/Threads/Reactions/Typing/Streaming):

| Platform | Connection (NAT-friendly?) | Input richness | Output formatting | Friction / risk | Session keying | Notes for a personal agent |
|---|---|---|---|---|---|---|
| **Telegram** | Long polling, outbound (yes); optional webhook mode for cloud | voice notes (STT), images, files, threads/topics | MarkdownV2 + opt-in native rich messages (tables/math); streaming incl. native draft transport; `MEDIA:` file delivery incl. docx/pdf/zip | Lowest: BotFather token, free | per user (irrelevant single-owner); DM topics give parallel sessions | Deepest adapter: inline-keyboard clarify + exec approvals, `/model` picker, per-channel prompts, notification modes (`important` default), pin-during-turn, `/topic` multi-session, cron thread targeting. `docs:user-guide/messaging/telegram` |
| **Discord** | WebSocket, outbound (yes) | voice notes + **live voice channels** (talk to the PA), images, files | streaming edits, threads, reactions, forum channels | Moderate: app + intents + invite; no ToS risk | per channel → a private server = channel-per-context "life dashboard" | Only platform with real-time spoken conversation (`voice_fx` ambient/acks). Best secondary. `docs:user-guide/messaging/discord`, `docs:user-guide/features/voice-mode` |
| **Slack** | Socket Mode WebSocket (yes) | voice, images, files | streaming, thread-keyed sessions; flat in-channel continuable cron | High: app manifest + xoxb/xapp tokens (automated by `hermes slack manifest --write`) | per thread | Built for teams; personal workspace is overhead. Free plan hides history ≥90d. Skip unless you live in Slack. `docs:user-guide/messaging/slack` |
| **iMessage — BlueBubbles** | Local webhook loopback; server runs **on the mini itself** | images, voice, video, docs both ways | **markdown stripped to plain text**; no streaming; tapbacks/typing/read-receipts need Private API helper | High: BlueBubbles server + Apple ID in Messages.app on the mini; Private API extra setup | — | Native Messages UX on all your devices; but formatting loss hurts a tool-using agent, and the bot texts *as* the mini's Apple ID. Novelty secondary, not primary. `docs:user-guide/messaging/bluebubbles` |
| **iMessage — Photon** | Outbound gRPC sidecar (yes) | outbound media/polls/effects; **inbound attachments metadata-only** | plain text | Low setup, but third-party service in the loop; free shared line can't initiate new conversations (cron to you works only after you text the line once) | — | Managed iMessage without touching the Mac. Privacy/functionality tradeoffs documented. `docs:user-guide/messaging/photon` |
| **WhatsApp (Baileys)** | Bridge session, outbound (yes) | voice (STT), images, files, native polls/locations, clarify-as-poll | streaming; WA-markdown conversion; 4,096-char chunking | **Unofficial bridge — documented ban risk**; use a dedicated number; breaks on WA protocol updates until re-pair | — | Docs themselves warn. Community uses it for family-shared agents (`docs:user-stories`). Skip for now. `docs:user-guide/messaging/whatsapp` |
| **Signal** | signal-cli SSE (yes) | images/audio/docs; voice transcribed | **native styled text** (bodyRanges), reply-quotes, reactions; **no message edits → no streaming, no tool-progress** | Moderate: signal-cli + Java 17, linked device; "Note to Self" works on your own number | — | Most private mainstream option; ergonomics worse than Telegram. `docs:user-guide/messaging/signal` |
| **Matrix** | Client sync (yes) | full media, threads, reactions | streaming, editable thinking panes, E2EE modes | Highest: homeserver/account + client | per user in room | Only if already in Matrix. `docs:user-guide/messaging/matrix` |
| **Email** | IMAP/SMTP polling (yes) | attachments, threads | plain email | Low (app password); slow loop | — | Delivery target for digests, not a chat surface. `docs:user-guide/messaging/email` |
| **ntfy** | HTTP pub-sub, outbound (yes) | none (4,096-char text) | optional markdown; no threads/attachments | Trivial; **topic name = identity** — use unguessable topic or self-host | — | Not a chat surface; excellent **push sidecar** for cron alerts (`deliver: ntfy`), incl. outgoing-only mode. `docs:user-guide/messaging/ntfy` |
| **SMS (Twilio)** | **Inbound webhook — needs public URL** (no) | text only | text only | Twilio cost + exposing the mini | — | Skip on a home mini. `docs:user-guide/messaging/sms` |

**Verdict:** Telegram primary — confirmed right, not just incumbent: it is the
only adapter with streaming + rich input + interactive approvals + topics +
proactive-delivery tooling all at once, and its defaults are explicitly tuned
for a mobile inbox (`docs:user-guide/messaging/index` "Mobile-friendly progress
defaults"). Discord is the best secondary (voice-channel conversations, channel
organization). ntfy is worth adding as a zero-cost push sidecar. Skip WhatsApp
(ban risk), SMS (public webhook), Slack/Matrix (friction > payoff for one user).
The gateway is one process serving all platforms, so adding a second later is
config, not surgery.

## 2. Messaging patterns for a single-owner PA (Telegram)

- **Access control is already right:** DM pairing beats allowlists for one owner; `hermes pairing list` audits it. Default-deny applies to everyone else. (`docs:user-guide/messaging/index#security`)
- **Home channel** = where cron/proactive/restart messages land: `/sethome` in the DM, or `TELEGRAM_HOME_CHANNEL=<user-id>` (DM chat id = your user id). (`docs:user-guide/messaging/telegram#home-channel`)
- **Noise tuning (mostly defaults):** `tool_progress` defaults **off** on Telegram, notifications `important` (only final replies/approvals ring). Add `display.platforms.telegram.cleanup_progress: true` to auto-delete progress bubbles after the final reply, `telegram.reactions: true` for 👀/✅ processing feedback. (`docs:user-guide/messaging/index`, `docs:user-guide/messaging/telegram`)
- **Streaming:** `gateway.streaming: {enabled: true, transport: auto}` uses Telegram's native draft streaming in DMs (Bot API 9.5), falling back to edit-based elsewhere. (`docs:user-guide/messaging/telegram#streaming-transport`)
- **Parallel contexts when the single DM sprawls:** two mechanisms — operator-declared `platforms.telegram.extra.dm_topics` (fixed topics, each its own session, optional `skill:` auto-load — e.g. a "Tasks" topic bound to `apple-reminders`) or user-driven `/topic` multi-session mode (you create topics ad hoc; root DM becomes a lobby). Both need Topics enabled client-side / BotFather Threaded Mode. If you enable topics, set `TELEGRAM_CRON_THREAD_ID` so cron lands in a replyable topic. (`docs:user-guide/messaging/telegram`)
- **Mid-task control:** messaging a busy agent redirects it by default (`display.busy_input_mode: interrupt|queue|steer`); `/stop` hard-stops; exec approvals and `clarify` questions arrive as inline buttons. (`docs:user-guide/messaging/index`, `telegram#exec-approval`)
- **Sessions:** never auto-reset by default. For a PA, opt into `session_reset: {mode: idle, idle_minutes: 1440}` — daily-fresh sessions also refresh the frozen memory snapshot (memory changes only appear in the prompt at session start). `/new`, `/resume`, `/sessions search`, `/title` manage the rest. (`docs:user-guide/messaging/index#reset-policies`, `docs:user-guide/which-file-does-what`)
- **Group-chat later:** `require_mention: true` + `group_allowed_chats`; `guest_mode: true` allows @mention-only replies in non-allowlisted groups; `observe_unmentioned_group_messages` lets it lurk for context without replying. Remember BotFather privacy-mode + remove/re-add gotcha. (`docs:user-guide/messaging/telegram#group-allowlisting`)
- **Multi-platform when added:** per-platform home channels; `deliver: "all"` fans cron out to every connected home channel, resolved at fire time (a job created today picks up Discord automatically the day you wire it). (`docs:user-guide/features/cron#delivery-options`)
- **Push from any script:** `hermes send --to telegram "text"` / `--file report.md` — lets dotfiles scripts and cron-outside-hermes ping you through the same bot. (`docs:guides/pipe-script-output`)

## 3. Cron: scheduled + proactive patterns

Scheduler lives in the gateway (ticks every 60s; jobs in `~/.hermes/cron/jobs.json`,
output in `~/.hermes/cron/output/<job_id>/`). Create via chat (`/cron add`),
natural language ("every morning at 8, …"), agent `cronjob` tool, CLI, or
dashboard. (`docs:user-guide/features/cron`)

**Schedule formats:** `30m` (one-shot), `every 2h`, cron exprs (`0 8 * * 1-5`), ISO timestamps.
**The golden rule:** jobs run in fresh sessions — prompts must be self-contained (bake in who the briefing is for; a persona line dramatically improves relevance — `docs:guides/daily-briefing-bot`).

Key mechanics for a PA:

- **Model pinning / drift guard.** Resolution: per-job pin → `cron.model`/`cron.model_provider` → global default. Unpinned jobs snapshot the model at creation and **fail closed (skip + one alert)** if the global default later changes. Pin per job or set `cron.model` once. (`docs:user-guide/features/cron`)
- **`[SILENT]`** — if the final response is exactly a silence token, delivery is suppressed (output still saved locally). The watchdog pattern: "If nothing noteworthy, respond with [SILENT]." (`docs:user-guide/features/cron#silent-suppression`)
- **`--skill` attachment** — load skills into the job's fresh session (`--skill blogwatcher --skill maps`); the blueprint way to run `weekly-review-planning` on Sundays.
- **`no_agent` + `script`** — pure script jobs, stdout delivered verbatim, zero tokens; empty stdout = silent tick. Scripts must live under `~/.hermes/scripts/` and do **not** inherit provider secrets. `wakeAgent` gates let a $0 pre-check decide whether to wake the LLM (file-mtime/flag/SQL-count recipes in the doc). Ideal on Codex quota. (`docs:user-guide/features/cron#no-agent-mode-script-only-jobs`, `docs:guides/cron-script-only`)
- **`continuity: true`** — job sees its own previous output (dedupe: "report only items NOT already covered"). **`context_from`** chains jobs (collect → rank → deliver pipelines).
- **Continuable deliveries** — default is fire-and-forget (replying to a cron message hits an agent with no memory of it). `cron.mirror_delivery: true` (or per-job `attach_to_session`) makes each brief a thread/session you can reply into. (`docs:user-guide/features/cron#continuable-jobs-reply-to-a-cron-delivery`)
- **`enabled_toolsets`** per job (e.g. `["web","file"]`) cuts the tool-schema prompt cost of small jobs; the cron "platform" also has its own toolset via `hermes tools`.
- **Per-job `--reasoning-effort`** (`minimal`…`ultra`) — heavy weekly analyses high, cheap recurring jobs minimal.
- **Preflight validation** — misconfigured jobs (missing key/skill env/delivery target) block with one alert and **no LLM call** (`cron.preflight`, default on). Failure streaks nudge you to fix/pause after 3 consecutive failures.
- **`/heartbeat every 10m <prompt>`** — recurring prompt *inside the current session* (full context), vs cron's fresh sessions. One per session; survives restarts; coalesces missed ticks. "Watch X in this thread" ≠ a standing job. (`docs:user-guide/features/heartbeat`)
- **`/goal`** — standing objective with judge-driven continuation loop (20-turn budget, gates, contracts) — for "keep working until done" tasks issued from Telegram, not schedules. (`docs:user-guide/features/goals`)
- **Blueprints** — `/blueprint <name>` parameterized recipes (e.g. `/blueprint morning-brief time=08:00`); catalog at `docs:reference/automation-blueprints-catalog`; copy-paste library incl. uptime watchdog, news digests at `docs:guides/automation-blueprints`.

Community-validated PA cron ideas (`docs:user-stories`): morning inbox summary; once-daily HN digest; Google-Tasks change watcher pinging chat; end-of-day journaling into Obsidian; proactive check-ins ("gently re-engage").

## 4. Memory for a long-running PA

Built-in (active on the mini) is **bounded and curated**: `MEMORY.md` (2,200 chars, agent's notes) + `USER.md` (1,375 chars, your profile) in `~/.hermes/memories/`, injected as a **frozen snapshot at session start** (mid-session saves hit disk immediately but appear next session — another reason for daily session resets). Agent manages entries via the `memory` tool; duplicates rejected; entries security-scanned. (`docs:user-guide/features/memory`, `docs:user-guide/which-file-does-what`)

- **Unlimited recall lives elsewhere:** `session_search` — FTS5 over every session in `~/.hermes/state.db` (~20ms, no LLM cost). Memory = always-in-context facts; session search = "did we discuss X three weeks ago". (`docs:user-guide/features/memory#session-search`)
- **Audit/prune what it learned:** `hermes journey list|edit|delete` (also `/journey`). If it saves a wrong assumption: `memory.write_approval: true` stages every save for `/memory pending` → approve/reject. Default (write freely) is fine to start; flip the gate if background saves annoy you.
- **Background self-improvement review** runs post-turn on your main model; `display.memory_notifications: on|off|verbose` controls the `💾 Memory updated` line; `auxiliary.background_review.{provider,model}` can route it to a cheap OpenRouter model (~3–5× cheaper); `enabled: false` kills it.
- **One agent per HERMES_HOME.** Never point a second Hermes process at the same home — writers compound each other's memory. Profiles exist for that. (`docs:user-guide/features/memory` caution)
- **External providers** (8: Honcho, Mem0, OpenViking, Hindsight, Holographic, RetainDB, ByteRover, Supermemory) are **additive** — built-in stays on; one external max. For a PA the interesting one is **Honcho** (cross-session user modeling, dialectic reasoning, gateway identity mapping for Telegram UIDs; cloud or self-hosted; headless device-code auth). `hermes memory setup` / `memory.provider: honcho`. **Recommendation: don't add one yet** — built-in + session search + skills covers a single-user PA; revisit if you want deep user-modeling. (`docs:user-guide/features/memory-providers`)
- Community pattern worth stealing (`docs:user-stories`, 794-upvote item): Obsidian vault as "long-term memory backbone" — agent writes structured markdown notes into a synced vault via the bundled `obsidian` skill; survives resets and device moves.

## 5. Skills: hub, authoring, and the life-management set

Skills live in `~/.hermes/skills/`; every one is a `/slash-command`; progressive
disclosure keeps token cost down (index ~3k tokens; content loads on demand).
(`docs:user-guide/features/skills`)

**Hub:** `hermes skills browse|search|inspect|install|check|update|audit|uninstall`; sources: `official/…` (in-repo optional skills, trusted), GitHub taps (`openai/skills`, `anthropics/skills`, …), `skills-sh`, `well-known:` URLs, direct URLs, browse.sh (200+ site-automation skills). All third-party installs are security-scanned; `--force` overrides warnings but never `dangerous`. Set `GITHUB_TOKEN` to avoid the 60 req/h unauthenticated GitHub API limit. (`docs:user-guide/features/skills#skills-hub`)

**Authoring:** `/learn <anything>` — point it at a directory, URL, pasted procedure, or "what we just did" and it writes a house-standard SKILL.md (big sources become knowledge-base skills with `references/`). Ask "save what you just did as a skill called X" after any workflow you'll repeat. `skills.write_approval: true` stages agent skill-writes for `/skills diff` review if wanted. **Bundles**: `hermes bundles create weekly-reset --skill weekly-review-planning --skill obsidian` → `/weekly-reset`. (`docs:guides/work-with-skills`, `docs:user-guide/features/skills`)

**Life-management set for this install** (bundled = already present):

| Skill | What it unlocks | Needs |
|---|---|---|
| `apple-reminders` (bundled, macOS) | Todos synced to iPhone via iCloud (`remindctl`) | `brew install steipete/tap/remindctl`, Reminders TCC grant, mini signed into your Apple ID |
| `apple-notes` (bundled, macOS) | Notes.app create/search/edit (`memo`) | brew tap install, Automation TCC |
| `apple-imessage` (bundled, macOS) | Read/send iMessage via Messages.app (`imsg`) | Messages signed in, Full Disk Access + Automation |
| `google-workspace` (bundled) | **Gmail + Calendar + Drive + Sheets + Docs** — the real calendar backend; agent-driven OAuth setup | Google Cloud project + Desktop OAuth client (one-time, walkthrough in chat) |
| `himalaya` (bundled) | Email-only alternative, 2-min setup | Gmail app password |
| `email-inbox-triage` (bundled) | Inbox triage workflow | one of the above |
| `weekly-review-planning` (bundled) | Weekly reset: commitments, stalled work, next-week plan; pairs with the `weekly-review` blueprint | — |
| `document-to-action-items`, `meeting-action-items` (bundled) | Docs/notes → task lists | — |
| `obsidian` (bundled) | Structured notes into a synced vault (community memory-backbone pattern) | vault path |
| `maps` (bundled) | Places/directions | — |
| `product-price-monitor`, `blogwatcher` (bundled) | Watch prices/feeds via cron `--skill` | — |
| `official/health/fitness-nutrition` (optional) | Voice-first fitness/nutrition log that learns patterns (community favorite) | `hermes skills install official/health/health-fitness-nutrition` — verify id with `hermes skills browse --source official` |
| `official/productivity/memento-flashcards` (optional) | Spaced repetition | install |
| `duckduckgo-search` (bundled) | Auto-appears as fallback only when the web toolset is unavailable | — |

**Cost control:** bundled catalog is broad (mlops, blockchain, gaming…). `hermes prompt-size` shows the fixed per-message cost; disable irrelevant ones globally (`skills.disabled`) or just on Telegram (`skills.platform_disabled.telegram`) — also keeps you under Telegram's ~60-command menu cap. `hermes skills opt-out` exists for full blank-slate. (`docs:reference/faq#managing-skills-on-telegram-slash-command-limit`)

## 6. Personality / instructions

The file map (`docs:user-guide/which-file-does-what`):

- **`~/.hermes/SOUL.md`** — identity, slot #1 of the system prompt, replaces the default persona; loaded only from HERMES_HOME (never cwd); seeded automatically, never overwritten. Durable voice/tone/what-to-avoid goes here.
- **`USER.md`** — agent-maintained profile; populate it by *telling* the bot ("remember I prefer one-line answers, timezone PT, name Sanjeev"), not by editing SOUL.md.
- **`AGENTS.md`** (or `.hermes.md`, highest priority; `CLAUDE.md`/`.cursorrules` also read, first match wins) — project-scoped, from the working directory; cron jobs only load them when `--workdir` is set.
- **`/personality <name>`** — session-level overlay (13 built-ins + custom via `agent.personalities`); `none` resets. `agent.system_prompt` applies only when no personality selected.

A good PA SOUL.md per the docs' example: direct, no sycophancy, push back on bad
ideas, admit uncertainty, compact answers (`docs:user-guide/features/personality#good-soulmd-content`)
— i.e., your global CLAUDE.md persona, expanded a little.

**`hermes import-agent claude-code` — challenge the obvious move:** it maps
global CLAUDE.md → *memory entries*, permissions → command allowlist, MCP
servers → config, skills → `skills/claude-code-imports/`. For this install the
only meaningful import is 2 sentences of persona, which belongs in SOUL.md —
and memory has a 2,200-char budget. Skip it, or run `--dry-run` and cherry-pick
only if you later want your Claude skills mirrored. (`docs:user-guide/import-from-other-agents`)

## 7. Tool/API keys worth adding (config keys + what each unlocks)

All secrets go in `~/.hermes/.env` (`hermes config set KEY value` routes them
there automatically, mode 600). (`docs:user-guide/configuration`)

| Key | Unlocks | Notes |
|---|---|---|
| *(none)* | `web_search` + `web_extract` already work | Keyless free-tier ring: Exa/Parallel/Tavily/Firecrawl/Keenable round-robin with failover; strictly last-resort, disable via `web.keyless_fallback: false`. Keyed backends get one-shot keyless rescue on failure. |
| `EXA_API_KEY` | Neural/semantic search, 1k/mo free | Best for research-y queries; also an extract backend |
| `TAVILY_API_KEY` | AI-optimized search+extract, 1k/mo free; also selectable keyless | |
| `FIRECRAWL_API_KEY` | Default full search+extract backend, 500 credits/mo free | The daily-briefing tutorial's assumed backend |
| `BRAVE_SEARCH_API_KEY` | Index-backed search, 2k/mo free | search-only — pair with an extract backend |
| `SEARXNG_URL` | Free unlimited self-hosted metasearch (Docker on the mini) | search-only; pair `web.extract_backend: firecrawl` |
| `GITHUB_TOKEN` | Skills-hub API limit 60/h → 5k/h; Copilot as a model provider if entitled | cheap win |
| *(ffmpeg, not a key)* | Edge TTS (default, free) → native Telegram voice bubbles | re-run `hermes gateway install` after brew install |
| `ELEVENLABS_API_KEY` / `GEMINI_API_KEY` / `VOICE_TOOLS_OPENAI_KEY` | Premium TTS voices (`tts.provider`) | Gemini TTS has a free tier + persona prompts/audio tags |
| `GROQ_API_KEY` | Cloud Whisper STT (faster than local on long memos) | local `faster-whisper` already free |
| `FAL_KEY` | Image generation (`image_gen.provider: fal`) | alternatives: `OPENAI_API_KEY`, `KREA_API_KEY`, xAI, `openrouter`; switch via `hermes tools`, not by adding keys |
| `XAI_API_KEY` / `hermes auth add xai-oauth` | Grok search backend + TTS + image gen | LLM-generated search results — trust-model caveat in docs |
| `OPENROUTER_API_KEY` | Fallback inference + cheap auxiliary/background-review models | see §8 |

Config selection matters more than keys: `web.backend` / `web.search_backend` /
`web.extract_backend` are sticky — once set, adding a key does **not** reroute.
(`docs:user-guide/features/web-search#configuration`)

## 8. Fallback providers (fits: openai-codex OAuth primary, OpenRouter key available)

`fallback_providers` (top-level list in config.yaml) fires per-turn on 429/5xx
(after retries) and 401/403/404 (immediately); conversation continues in place;
primary is retried next turn — and the retry is **reset-aware**: when Codex
reports a weekly-limit reset time, Hermes stays on the fallback until it passes
instead of bouncing (each bounce also resets the prompt cache — the documented
cost of failover). Cron jobs and subagents inherit the chain. Configure via
config.yaml or `hermes fallback` (interactive; avoid on headless — edit YAML).
(`docs:user-guide/features/fallback-providers`)

Recommended shape for this install (model choice yours; docs' own OpenRouter examples use Claude Sonnet-class models):

```yaml
# ~/.hermes/config.yaml
fallback_providers:
  - provider: openrouter
    model: anthropic/claude-sonnet-4.6   # capable fallback for agentic turns
auxiliary:
  background_review:
    provider: openrouter
    model: google/gemini-3-flash-preview  # post-turn review off the Codex quota
  compression:
    provider: openrouter
    model: google/gemini-3-flash-preview
```

Also worth routing off-quota: `auxiliary.{vision,web_extract,title_generation,goal_judge}`
all accept `{provider: openrouter, model: …}`; on `auto` they already try your
`fallback_providers` before built-in discovery. `/usage reset` redeems a banked
Codex limit reset from chat when you hit the window. (`docs:user-guide/features/fallback-providers`, `docs:user-guide/messaging/index` command table)

## 9. Web dashboard over the tailnet

`hermes dashboard` (port 9119) needs the extras: `cd ~/.hermes/hermes-agent && uv pip install -e ".[web,pty]"`.
**Verdict: yes, worth it for a long-running PA** — it's the only surface that
aggregates: cron job editor with trigger-now, sessions browser with FTS search/
export/prune, token/cost analytics per day and model, live log tailing, skills
hub with toggles, memory reset, pairing approvals, channel setup, gateway
start/stop, update button, and an embedded full TUI chat (xterm.js over PTY).
(`docs:user-guide/features/web-dashboard`)

Security model (post-June-2026 hardening):

- Loopback bind (default) = no auth. Non-loopback bind **fails closed** unless an auth provider is configured; `--insecure` is a **no-op** now.
- **Docs' recommended tailnet patterns:** (a) bind `127.0.0.1` and reach it over an SSH tunnel or Tailscale (`ssh -L 9119:127.0.0.1:9119 macmini`, or `tailscale serve`); or (b) bind the tailscale IP (`--host <tailscale-ip>`) with the username/password provider (`HERMES_DASHBOARD_BASIC_AUTH_USERNAME/PASSWORD/SECRET` in `.env`) — docs explicitly call Tailscale "the clean option" and say never to expose a password-gated dashboard to the open internet (OAuth/Nous provider is for that).
- The dashboard reads/writes `.env` (all your secrets) and can run agent commands — treat it as root on the agent.

Given Tailscale SSH already works to the mini, start with loopback + `ssh -L`;
graduate to tailscale-IP + basic auth if you want it one-tap from the phone.

## 10. Gotchas for a long-running personal deployment

- **launchd PATH is frozen at install.** After brew-installing anything the gateway needs (ffmpeg, remindctl, node), re-run `hermes gateway install` — it re-snapshots PATH and reloads. (`docs:user-guide/messaging/index#macos-launchd`)
- **LaunchAgent ≠ boot.** Gateway starts only with a user session; the mini needs auto-login (already configured per handoff) or a LaunchDaemon hand-roll (`--system` is Linux-only). (handoff §8.1; `docs:user-guide/messaging/index`)
- **One gateway per bot token.** Two pollers on one Telegram token conflict. (`docs:user-guide/messaging/telegram`)
- **Update cadence is fast** (0.20.4 → 0.20.5 within days; ~24k commits). `dotup` doesn't cover hermes: run `hermes update --yes` weekly (auto-restarts the gateway; `--check` previews; `--backup` snapshots first). Updates re-seed new bundled skills unless you opt out; your edited skills are hash-protected from stomping (`hermes skills reset <name>` un-sticks one). (`docs:reference/cli-commands`, `docs:user-guide/features/skills#bundled-skill-updates`)
- **Session/DB growth:** `hermes sessions compact` (VACUUM, non-destructive) before reaching for `hermes sessions prune --older-than 30` / `--source cron`; `sessions export --format md --redact` for archives. Media itself isn't the context hog — transcripts are; `/compress` in long threads. Dashboard shows a low-disk banner (<512MB free warns). (`docs:user-guide/sessions`, `docs:user-guide/features/web-dashboard`)
- **Log growth is mostly handled:** logs auto-redact secrets; `tool_calls.log` audit mode rotates at 5MB×3. Keep an eye on `~/.hermes/logs/gateway.log` size anyway — nothing documents rotation for it.
- **Prompt-cache economics:** model switches, provider fallbacks, and credential rotation each force a full-price re-read of history. Don't bounce models mid-session for fun. (`docs:guides/tips#dont-break-the-prompt-cache`)
- **Cron drift guard** (§3) — the #1 documented "my job silently stopped" cause: unpinned job + changed global model = fail-closed skip. Pin models on every recurring job.
- **Circuit breaker doesn't auto-resume.** A platform outage trips the adapter to `paused-by-breaker`; after Telegram recovers you must `/platform resume telegram` (operator notice goes to another platform's home channel — a second platform or ntfy earns its keep here). (`docs:user-guide/messaging/index#automatic-circuit-breaker`)
- **Delivery ledger** redelivers replies lost in a crash (bounded, labeled "♻️ Recovered reply") — leave `gateway.delivery_ledger` on.
- **Codex OAuth specifics:** keep Hermes' own OAuth session (refresh tokens are single-use; sharing `~/.codex/auth.json` with Codex CLI causes conflicts — handoff §5); quota semantics undocumented → that's what §8's fallback is for.
- **Memory is a frozen snapshot** per session; **one process per HERMES_HOME**; memory/skill writes can be gated if the self-improvement loop misbehaves (§4).
- **Skills hub without `GITHUB_TOKEN`** rate-limits at 60 req/h.
- **Cron scripts don't inherit secrets** (`_sanitize_subprocess_env`) — a `no_agent` script needing an API key must arrange its own env.
- **Dangerous-command approvals** arrive in chat (reply yes/no, or `/approve`); "always" allowlists permanently — prefer "session". (`docs:guides/tips#security`)

## 11. Managing multiple agents / profiles ("Hermes Studio"?)

**No "Hermes Studio" exists.** A case-insensitive grep across the entire docs
tree + README at `main` finds "studio" only as LM Studio / AI Studio / Visual
Studio references, two creative skills (`media-studio`, `art-studio`), and a
"Skin Studio" — a terminal *theme* editor (`docs:user-guide/features/skins`),
not agent management. Nothing by that name in the nav, README, or CLI. What
actually exists is better than the imagined product: **profiles** (the
primitive), plus three official UIs over them — the web dashboard, **Bot Mode
in Hermes Desktop** (the closest thing to a "studio"), and Desktop's
multi-machine gateway registry.

### The primitive: profiles (not raw HERMES_HOME)

A profile is a separate Hermes home under `~/.hermes/profiles/<name>` — own
`config.yaml`, `.env`, `SOUL.md`, memories, sessions, skills, cron jobs,
`state.db`, gateway state. Profiles are "a managed layer on top of
`HERMES_HOME`": the wrapper sets `HERMES_HOME` for you and handles directory
creation, command aliases, active-profile tracking, skill sync, and tab
completion. (`docs:user-guide/profiles`, `docs:reference/faq#profiles`)

```bash
hermes profile create coder                  # + auto alias: `coder <any subcommand>` (= hermes -p coder)
hermes profile create pa --clone             # copy config/.env/SOUL/skills; fresh memory+sessions
hermes profile create backup --clone-all     # everything except session history
hermes profile use coder                     # sticky default (kubectl-context style)
hermes profile list|show|rename|delete|export|import
```

Rules that matter:

- **One process per profile home, ever** — two writers on one home compound each other's memory (`docs:user-guide/profiles` caution). Profiles are isolation, not sandboxing: same filesystem access; set `terminal.cwd` per profile, and `terminal.home_mode: profile` only if you want separate git/ssh/CLI identities per agent (default shares your real `$HOME` credentials).
- **One bot token per profile.** Telegram/Discord/Slack/WhatsApp/Signal tokens are exclusive; token locks block a second gateway with an error naming the conflicting profile. A second identity on Telegram = a second BotFather bot. (`docs:user-guide/profiles#running-gateways`)
- **Services scale cleanly:** each profile's `gateway install` creates its own unit — `ai.hermes.gateway-<name>.plist` (launchd) / `hermes-gateway-<name>.service` (systemd). `hermes gateway start --all` etc. act on every profile; `docs:user-guide/multi-profile-gateways` covers fleet ops (collective start/stop, cross-profile logs, keeping the host awake).
- **Lighter alternative — multiplexing:** `hermes config set gateway.multiplex_profiles true` on the default profile → **one** gateway process serves every profile's platforms under each profile's own credentials (per-turn resolution of that profile's config/skills/memory/SOUL/keys; secondary `gateway start` becomes a hard error; HTTP-inbound routes gain a `/p/<profile>/` prefix). Opt-in, off by default; you trade process-level crash isolation for one thing to supervise. (`docs:user-guide/multi-profile-gateways#alternative-one-gateway-for-all-profiles-multiplexing`)
- `hermes update` runs once and syncs skills to **all** profiles.
- Cross-profile plumbing exists: cron `deliver: "bot-chat:<profile>"` feeds one agent's scheduled output to another as a real message (same machine, validated against `hermes profile list`); the kanban orchestrator routes cards across profiles by their `--description`. (`docs:user-guide/features/cron#bot-chat-delivery-bot-chat`)
- Sharing/versioning: `hermes profile export|import` (.tar.gz, API keys stripped) or **profile distributions** — a profile published as a git repo, installed with `hermes profile install github.com/you/research-bot --alias`, updated with `hermes profile update` (credentials/memories stay per-machine). (`docs:user-guide/profile-distributions`)

### Lighter-weight "personas" inside ONE agent (no second bot/process)

Documented mechanisms, in increasing weight — use these until two identities
must stop sharing memory (that's the line where a real profile is required):

- **`channel_overrides`** (per platform, `gateway-config.yaml`): per-channel/thread `model`, `provider`, and ephemeral `system_prompt` — cheap model in one channel, specialist persona in another; a session `/model` still wins. (`docs:user-guide/messaging/index#per-channel-model--system-prompt-overrides`)
- **Telegram `channel_prompts`**: per-group/per-topic ephemeral system prompts. (`docs:user-guide/messaging/telegram#per-channel-prompts`)
- **Telegram DM topics / `/topic`**: parallel isolated sessions on one bot, with per-topic `skill:` auto-load. (§2)
- **`/personality` overlays** + custom `agent.personalities` in config.yaml. (`docs:user-guide/features/personality`)
- **Per-cron-job pins**: `--provider/--model/--reasoning-effort` per job. (§3)

### UIs: what manages what

| Surface | Scope | What it gives you |
|---|---|---|
| **Web dashboard** (`hermes dashboard`) | **Machine-level: one server manages every profile on the box** via a sidebar profile switcher (`?profile=<name>` deep links; amber banner names the managed profile). Config, API keys, Skills, MCP, Models, and the Chat tab all follow the switcher; a Profiles page creates/edits/deletes profiles (incl. SOUL editor, Profile Builder at `/profiles/new`); the Cron page **aggregates jobs across profiles** with a filter. `coder dashboard` routes to the machine dashboard preselected; `--isolated` opts out into a dedicated per-profile server (e.g. different auth per exposed profile). Not absorbed by the switcher: per-profile gateway processes (`hermes -p <name> gateway …`), session DBs, cron schedulers. (`docs:user-guide/features/web-dashboard#managing-multiple-profiles`, `docs:user-guide/profiles#from-the-dashboard`) |
| **Bot Mode** (Hermes Desktop, built-in, on by default) | One machine's profiles | The de-facto "studio": every profile appears as a named **Bot** with role, model, memory, skills, avatar; each has a pinned forever "Bot Chat"; **Routines** tile = that Bot's cron jobs (same jobs `hermes cron list` shows); Bots share group chats and @mention each other; presence strip shows which Bots are working; New Agent dialog = profile creation with clone/model-pin/SOUL/per-skill enablement; new Bots share one OAuth/token pool with the main profile so credential refreshes don't invalidate each other. No new primitive — a Bot **is** a profile. (`docs:user-guide/bot-mode`) |
| **Desktop gateway registry** (Settings → Gateways) | **Many machines/instances** | Register the local runtime, remote gateways (LAN/VPS/SSH — a Mini behind Tailscale is the docs' own example), and Hermes Cloud instances in one desktop app and use them side by side. This is the documented answer for multiple `HERMES_HOME` *installations*: each installation has its own service label (`ai.hermes.gateway-<suffix>`) and its own dashboard, and the desktop app is what unifies them. Remote attach = a `hermes dashboard` running on that host with auth (§9). (`docs:user-guide/multi-connection-desktop`, `docs:user-guide/features/web-dashboard#connecting-hermes-desktop-to-a-remote-backend`) |

**Fit for this install:** one PA today → zero profile work needed. When a second
identity appears (say a coding agent on the mini): `hermes profile create coder`
+ a second BotFather token + `coder gateway install` — or flip on multiplexing
if launchd unit sprawl bothers you. For a UI over the fleet, run Hermes Desktop
on the Air attached to the mini's dashboard over the tailnet and you get Bot
Mode + the gateway registry without exposing anything publicly.

---

## Appendix: paste-ready commands and config

All commands run on the mini (`ssh macmini '…'`). Secrets via the existing
1Password pattern (`r(){ op read "op://Dotfiles/$1/credential" --no-newline; }`
with the three `OP_*` env guards — handoff §6).

### A. Day-one setup

```bash
# Home channel (DM chat id = your Telegram user id)
hermes config set TELEGRAM_HOME_CHANNEL <your-user-id>     # or just DM /sethome

# Persona
cat > ~/.hermes/SOUL.md <<'EOF'
# Personality
You are Sanjeev's personal assistant. Optimize for truth and usefulness.

## Style
- Challenge my assumptions; push back when something is a bad idea.
- Be extremely concise. One-line answers when one line suffices.
- Admit uncertainty plainly. No sycophancy, no filler, no hype.
- Proactive: flag conflicts, deadlines, and things I appear to have forgotten.
EOF

# OpenRouter key (fallback + cheap aux models)
hermes config set OPENROUTER_API_KEY "$(r openrouter-api-key)"   # routes to ~/.hermes/.env

# Voice replies as native bubbles (Edge TTS is default+free; needs ffmpeg)
brew install ffmpeg && hermes gateway install && hermes gateway restart
```

### B. config.yaml additions (`~/.hermes/config.yaml`)

```yaml
fallback_providers:
  - provider: openrouter
    model: anthropic/claude-sonnet-4.6

cron:
  model_provider: openai-codex   # cron-fleet default → no drift-guard skips
  model: gpt-5.6-sol
  mirror_delivery: true          # replies to cron briefs continue in-context

auxiliary:
  background_review: {provider: openrouter, model: google/gemini-3-flash-preview}
  compression:       {provider: openrouter, model: google/gemini-3-flash-preview}

session_reset:
  mode: idle
  idle_minutes: 1440             # daily-fresh sessions; memory snapshot refreshes

gateway:
  message_timestamps: {enabled: true}
  streaming: {enabled: true, transport: auto}

telegram:
  reactions: true

display:
  platforms:
    telegram:
      cleanup_progress: true
      # notifications: important   # already the default

skills:
  platform_disabled:
    telegram: []                 # fill after: hermes prompt-size + hermes skills list
```

Gateway restart applies it: `hermes gateway restart`.

### C. Starter cron fleet

```bash
# Morning brief, weekdays 08:00 (self-contained persona baked in)
hermes cron create "0 8 * * 1-5" \
  "You are briefing Sanjeev, a senior engineer in Pacific time who wants extreme brevity.
1) Search the web for significant AI/agent news from the past 24h; pick max 3 items, one line each with link.
2) One line of weather for his city.
3) If Apple Reminders is configured: list today's due reminders.
Format: tight bullets, no preamble. Nothing interesting? Say so in one line." \
  --name "morning-brief" --deliver telegram \
  --provider openai-codex --model gpt-5.6-sol

# Evening sweep, daily 21:30 — silent when clean
hermes cron create "30 21 * * *" \
  "Review today's open loops: overdue reminders, unanswered questions from today's chat sessions (use session_search), and anything I said I'd do. Max 5 bullets. If nothing needs attention, respond with [SILENT]." \
  --name "evening-sweep" --deliver telegram \
  --provider openai-codex --model gpt-5.6-sol

# Weekly review, Sunday 17:00, skill-backed
hermes cron create "0 17 * * 0" \
  "Run the weekly review: commitments made this week, stalled items, and a draft plan for next week. End by asking one question about priorities." \
  --skill weekly-review-planning \
  --name "weekly-review" --deliver telegram \
  --provider openai-codex --model gpt-5.6-sol

# Zero-token disk watchdog (script-only, silent unless bad)
mkdir -p ~/.hermes/scripts && cat > ~/.hermes/scripts/disk-watch.sh <<'EOF'
#!/bin/bash
pct=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')
[ "$pct" -ge 90 ] && echo "Disk at ${pct}% on $(hostname -s)"
exit 0
EOF
hermes cron create "every 6h" --no-agent --script disk-watch.sh \
  --deliver telegram --name "disk-watch"

hermes cron list && hermes cron status
```

Manage from chat: `/cron list`, `/cron pause <name>`, `/cron run <name>`,
`hermes cron runs <name>` for history.

### D. Skills for life management

```bash
# Apple stack (only if the mini is signed into your Apple ID; TCC prompts need one screen-share)
brew install steipete/tap/remindctl && remindctl authorize
brew tap antoniorodr/memo && brew install antoniorodr/memo/memo

# Optional installs
hermes skills browse --source official          # verify exact ids first
hermes skills install official/health/health-fitness-nutrition
hermes config set GITHUB_TOKEN "$(r github-token)"   # hub rate limits 60/h -> 5k/h

# Google Workspace (calendar/gmail): just ask the bot -
# "Set up the google-workspace skill" - it walks the OAuth flow in chat.

# Trim fixed prompt
hermes prompt-size
```

### E. Dashboard over tailnet

```bash
cd ~/.hermes/hermes-agent && uv pip install -e ".[web,pty]"
# Option 1 (start here): loopback + tunnel from the Air
hermes dashboard --no-open              # on the mini
ssh -L 9119:127.0.0.1:9119 macmini      # then open http://127.0.0.1:9119
# Option 2: tailnet bind + basic auth (docs' "clean option"); vars are documented
# as ~/.hermes/.env entries — append there directly:
{ echo "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=sanjeev"
  echo "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$(r hermes-dashboard-password)"
  echo "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(openssl rand -base64 32)"; } >> ~/.hermes/.env
hermes dashboard --host <tailscale-ip> --no-open
```

### F. Maintenance loop (manual, ~monthly)

```bash
hermes update --check && hermes backup && hermes update --yes   # weekly-ish
hermes sessions compact                                          # VACUUM state.db
hermes sessions prune --source cron --older-than 60
hermes skills check && hermes skills update
hermes doctor
```

### G. Later: second surfaces

```bash
# Discord (voice-channel conversations): create app + bot, enable intents, then
hermes config set DISCORD_BOT_TOKEN "$(r discord-bot-token)" && hermes gateway restart
# ntfy push sidecar (outgoing-only alerts to phone):
hermes config set NTFY_TOPIC "hermes-$(uuidgen | tr A-Z a-z)"   # topic = secret
hermes config set NTFY_HOME_CHANNEL "$NTFY_TOPIC"               # then deliver: ntfy on alert jobs
```

---

## Source index

- Messaging overview / platform matrix / DM pairing / service mgmt: `docs:user-guide/messaging/index`
- Telegram (topics, streaming, notifications, home channel, groups): `docs:user-guide/messaging/telegram`
- Platform pages: `docs:user-guide/messaging/{discord,slack,whatsapp,signal,matrix,email,sms,ntfy,photon,bluebubbles}`
- Cron: `docs:user-guide/features/cron`; tutorial `docs:guides/daily-briefing-bot`; recipes `docs:guides/automate-with-cron`, `docs:guides/automation-blueprints`, `docs:reference/automation-blueprints-catalog`; debugging `docs:guides/cron-troubleshooting`; `docs:guides/cron-script-only`
- Heartbeat / goals: `docs:user-guide/features/heartbeat`, `docs:user-guide/features/goals`
- Memory: `docs:user-guide/features/memory`, `docs:user-guide/features/memory-providers`, `docs:user-guide/which-file-does-what`, `docs:user-guide/sessions`
- Skills: `docs:user-guide/features/skills`, `docs:guides/work-with-skills`, catalogs `docs:reference/skills-catalog`, `docs:reference/optional-skills-catalog`, `docs:user-guide/skills/google-workspace`, bundled-skill pages under `docs:user-guide/skills/bundled/…`
- Personality: `docs:user-guide/features/personality`, `docs:guides/use-soul-with-hermes`, `docs:user-guide/features/context-files`, `docs:user-guide/import-from-other-agents`
- Web search / TTS / image gen: `docs:user-guide/features/web-search`, `docs:user-guide/features/tts`, `docs:user-guide/features/image-generation`
- Fallback: `docs:user-guide/features/fallback-providers`
- Dashboard: `docs:user-guide/features/web-dashboard`
- Ops/gotchas: `docs:guides/tips`, `docs:reference/faq`, `docs:user-guide/configuration`, `docs:reference/cli-commands`, `docs:user-guide/security`
- Profiles / multi-agent: `docs:user-guide/profiles`, `docs:user-guide/multi-profile-gateways`, `docs:user-guide/profile-distributions`, `docs:reference/profile-commands`, `docs:reference/faq#profiles`, `docs:user-guide/bot-mode`, `docs:user-guide/desktop`, `docs:user-guide/multi-connection-desktop`
- Community patterns: `docs:user-stories` (https://hermes-agent.nousresearch.com/docs/user-stories)
- Local install facts: `docs/plans/2026-08-16-hermes-mac-mini-handoff.md` (this repo)
