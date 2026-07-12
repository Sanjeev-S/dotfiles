---
title: "feat: Build wikibrain — agent-agnostic LLM knowledge base CLI"
type: feat
status: active
date: 2026-04-12
origin: docs/brainstorms/2026-04-12-llm-wiki-requirements.md
---

# feat: Build wikibrain — Agent-Agnostic LLM Knowledge Base CLI

## Overview

Build **wikibrain**, an open-source Python CLI tool that implements Karpathy's LLM Wiki pattern with a focus on multi-source ingestion and agent portability. The tool extracts knowledge from YouTube, PDFs, web articles, and arxiv papers, then delegates wiki compilation to the user's installed coding agent (Claude Code or Codex). Published under The Lemma (thelemma.dev) on GitHub at `thelemma/wikibrain`.

## Problem Statement / Motivation

Karpathy's LLM Wiki pattern (April 2026) created massive interest in AI-compiled personal knowledge bases, but the ecosystem response has been shallow — mostly CLAUDE.md templates and single-agent wrappers. The real bottleneck is **ingestion**: getting knowledge from diverse sources into `raw/` format. No existing tool solves this (see origin: `docs/brainstorms/2026-04-12-llm-wiki-requirements.md` — Competitive Landscape section).

wikibrain fills the gap: `pipx install wikibrain` → `wikibrain ingest <anything>` → agent compiles wiki.

## Proposed Solution

A Python CLI (Typer + Rich) distributed via pipx that acts as a **thin orchestrator** (harness pattern):

1. **Extracts** text from diverse sources using Python libraries
2. **Stores** structured raw markdown in `raw/` with metadata frontmatter
3. **Delegates** wiki compilation to the user's installed agent
4. **Manages** wiki state (index, sources manifest, multi-wiki switching)

The agent writes wiki pages directly to disk using its native file tools. wikibrain controls the input (structured prompts) and validates the output (wiki structure).

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      wikibrain CLI                       │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌───────┐  ┌──────────┐  │
│  │  init     │  │  ingest  │  │ query │  │   lint   │  │
│  └────┬─────┘  └────┬─────┘  └───┬───┘  └────┬─────┘  │
│       │              │            │            │         │
│       │         ┌────▼─────┐     │            │         │
│       │         │Extractors│     │            │         │
│       │         │ youtube  │     │            │         │
│       │         │ pdf      │     │            │         │
│       │         │ web      │     │            │         │
│       │         │ arxiv    │     │            │         │
│       │         │ local    │     │            │         │
│       │         └────┬─────┘     │            │         │
│       │              │           │            │         │
│  ┌────▼──────────────▼───────────▼────────────▼─────┐  │
│  │              Agent Dispatcher                     │  │
│  │  detect agent → build prompt → shell out → verify │  │
│  └──────────────────────┬────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────┘
                          │
              ┌───────────▼───────────┐
              │   Installed Agent      │
              │   (claude / codex)     │
              │                        │
              │   Reads: raw/, wiki/   │
              │   Writes: wiki/        │
              │   Schema: CLAUDE.md    │
              │          AGENTS.md     │
              └────────────────────────┘
```

### Agent Invocation (Critical Decision)

Agents write files directly to disk. wikibrain sets the working directory to the wiki root and invokes:

**Claude Code:**
```bash
claude -p "<prompt>" \
  --allowedTools "Read,Write,Edit,Glob,Grep" \
  --output-format json \
  --max-turns 20
```
- Loads CLAUDE.md automatically (do NOT use `--bare`)
- `--allowedTools` sandboxes to file operations only (no Bash)
- Returns JSON with `result` and `session_id`

**Codex:**
```bash
codex exec "<prompt>" \
  --full-auto \
  -o /tmp/wikibrain-output.txt
```
- Loads AGENTS.md automatically
- `--full-auto` allows file writes without approval
- Final message written to output file

**Agent detection:** `shutil.which("claude")` then `shutil.which("codex")`. First found wins. Override with `--agent`.

(see origin: `docs/brainstorms/2026-04-12-llm-wiki-requirements.md` — Key Decisions)

### Wiki Directory Structure

```
my-research/                    # User-chosen directory (Obsidian vault)
├── .wikibrain/
│   ├── config.toml             # Wiki metadata (name, created, agent)
│   └── sources.json            # Source manifest for dedup/incremental (R8)
├── raw/                        # Immutable extracted sources
│   ├── youtube-attention-is-all-you-need.md
│   ├── pdf-transformers-survey.md
│   └── web-karpathy-llm-wiki.md
├── wiki/                       # LLM-generated (agent writes here)
│   ├── sources/                # One summary per source
│   ├── entities/               # People, companies, projects
│   ├── concepts/               # Ideas, frameworks, methods
│   └── syntheses/              # Query answers saved as pages
├── index.md                    # Content catalog (agent-maintained)
├── log.md                      # Append-only operation record
├── CLAUDE.md                   # Schema for Claude Code
└── AGENTS.md                   # Schema for Codex
```

- Both CLAUDE.md and AGENTS.md are always generated (same wiki instructions, agent-specific format)
- `~/.config/wikibrain/config.toml` tracks all known wiki paths for `wikibrain list` and `wikibrain use`
- Wikis are Obsidian-compatible directories — user opens as vault directly

### Source Type Detection

```python
def detect_source_type(source: str) -> SourceType:
    # URL patterns
    if "youtube.com" in source or "youtu.be" in source:
        return SourceType.YOUTUBE
    if "arxiv.org" in source:
        return SourceType.ARXIV
    # Local files by extension
    if source.endswith(".pdf"):
        return SourceType.PDF
    if source.endswith((".md", ".txt")):
        return SourceType.LOCAL
    # URL with Content-Type check
    if source.startswith("http"):
        return SourceType.WEB
    # Fallback
    return SourceType.LOCAL
```

Override with `--type` flag for ambiguous cases (e.g., direct PDF URL on unknown domain).

### Incremental Update Detection (R8)

`.wikibrain/sources.json` maintains a manifest:
```json
{
  "sources": [
    {
      "id": "youtube-attention-is-all-you-need",
      "url": "https://youtube.com/watch?v=...",
      "type": "youtube",
      "raw_path": "raw/youtube-attention-is-all-you-need.md",
      "content_hash": "sha256:abc123...",
      "first_ingested": "2026-04-12T10:00:00Z",
      "last_ingested": "2026-04-12T10:00:00Z",
      "wiki_pages": ["wiki/sources/attention-is-all-you-need.md"]
    }
  ]
}
```

- `wiki_pages` tracked by diffing wiki/ before and after agent invocation (not agent-reported — agents can't be trusted to report this reliably)

On re-ingest: match by canonical URL/path → overwrite raw/ → prompt agent with "this source was previously ingested, update existing wiki pages rather than creating new ones."

### Chunking Strategy (Large Sources)

For v1, a pragmatic approach:
- **Threshold**: Warn if raw source exceeds 50K tokens (~200K chars)
- **YouTube**: Already chunked by transcript segments — include timestamps, let agent handle
- **PDFs**: Extract by page ranges if > threshold, ingest as sequential chunks
- **Web articles**: Rarely exceed limits; pass as-is
- Agent prompt includes chunk number and total: "This is chunk 2/4 of source X. Previous chunks created these wiki pages: [...]"

### Implementation Phases

#### Phase 1: Foundation + Agent Spike (Repo + CLI skeleton + Init + Validate Agent Dispatch)

**Goal:** `pipx install wikibrain && wikibrain init my-research` works, AND agent file-writing is validated

Tasks:
- [ ] **Spike agent dispatch first** — before building anything else, test the exact shell commands for both agents to confirm they can write files to a wiki directory:
  - `claude -p "Create a file called test.md with 'hello'" --allowedTools "Read,Write,Edit,Glob,Grep" --output-format json`
  - `codex exec "Create a file called test.md with 'hello'" --full-auto`
  - If file-writing doesn't work as expected, revisit the architecture before proceeding
- [ ] Create `thelemma/wikibrain` GitHub repo
- [ ] Set up project structure:
  ```
  wikibrain/
  ├── pyproject.toml          # Hatchling, Python >=3.12
  ├── src/
  │   └── wikibrain/
  │       ├── __init__.py
  │       ├── cli.py           # Main Typer app
  │       ├── commands/
  │       │   ├── __init__.py
  │       │   ├── init.py
  │       │   ├── ingest.py
  │       │   ├── query.py
  │       │   ├── lint.py
  │       │   ├── use.py
  │       │   ├── list.py
  │       │   └── status.py
  │       ├── extractors/
  │       │   ├── __init__.py
  │       │   ├── base.py      # Extractor Protocol
  │       │   ├── youtube.py
  │       │   ├── pdf.py
  │       │   ├── web.py
  │       │   ├── arxiv.py
  │       │   └── local.py
  │       ├── agents/
  │       │   ├── __init__.py
  │       │   ├── base.py      # Agent Protocol
  │       │   ├── claude.py
  │       │   └── codex.py
  │       ├── core/
  │       │   ├── __init__.py
  │       │   ├── config.py    # Global + wiki config
  │       │   ├── manifest.py  # sources.json management
  │       │   └── prompts.py   # Prompt templates
  │       └── templates/
  │           ├── claude_schema.py   # CLAUDE.md template (str.format)
  │           └── codex_schema.py    # AGENTS.md template (str.format)
  ├── tests/
  │   ├── conftest.py
  │   ├── test_cli.py
  │   ├── test_extractors/
  │   └── test_agents/
  ├── .github/
  │   └── workflows/
  │       └── ci.yml           # pytest + ruff
  ├── LICENSE                  # MIT
  └── README.md
  ```
- [ ] Implement `wikibrain init <name>`:
  - Scaffold directory structure (raw/, wiki/sources|entities|concepts|syntheses/)
  - Detect installed agent
  - Generate CLAUDE.md and AGENTS.md from string templates
  - Create index.md and log.md stubs
  - Create `.wikibrain/config.toml` and `.wikibrain/sources.json`
  - Register wiki path in `~/.config/wikibrain/config.toml`
- [ ] Implement `wikibrain list` and `wikibrain status`
- [ ] Implement `wikibrain use <name>`
- [ ] Set up CI: GitHub Actions with pytest + ruff
- [ ] Verify `pipx install .` works locally

**Acceptance criteria:**
- `pipx install .` succeeds
- `wikibrain init test-wiki` creates correct directory structure
- `wikibrain list` shows the wiki
- `wikibrain status` shows active wiki, detected agent, source count

#### Phase 2: Extractors (Source Ingestion Pipeline)

**Goal:** `wikibrain ingest <source> --dry-run` extracts text from any supported source

Tasks:
- [ ] Implement `Extractor` Protocol in `extractors/base.py`:
  ```python
  class Extractor(Protocol):
      def can_handle(self, source: str) -> bool: ...
      def extract(self, source: str) -> ExtractedSource: ...
  ```
  Where `ExtractedSource` is a dataclass with: title, content, metadata dict, source_url, source_type
- [ ] Implement `YouTubeExtractor`:
  - Primary: `youtube-transcript-api` (instance method API, v1.2.x)
  - Fallback: `yt-dlp` audio download → `faster-whisper` transcription
  - Metadata via `yt-dlp --dump-json` (title, duration, channel, chapters)
  - Output: structured markdown with frontmatter + timestamped transcript
- [ ] Implement `PDFExtractor`:
  - Primary: `pypdf` for text extraction
  - Metadata: title, author, page count from PDF info
  - Handle page-range extraction for large PDFs
- [ ] Implement `WebExtractor`:
  - `trafilatura.fetch_url()` + `trafilatura.extract()` with `with_metadata=True`
  - Always pass `url=` for better metadata extraction
  - If trafilatura fails, report error (no fallback in v1 — trafilatura handles edge cases well)
- [ ] Implement `ArxivExtractor`:
  - `arxiv` library for paper metadata (title, authors, abstract, categories)
  - Download PDF → delegate to PDFExtractor for text
  - Structured output: abstract separately, full text, BibTeX reference
- [ ] Implement `LocalExtractor`:
  - Read .md/.txt files directly
  - Detect encoding, handle frontmatter passthrough
- [ ] Implement source type detection (`detect_source_type()`)
- [ ] Implement `--type` override flag
- [ ] Implement `--dry-run` flag (extract + display without writing or calling agent)
- [ ] Write raw markdown output with frontmatter:
  ```markdown
  ---
  title: "Attention Is All You Need"
  source_url: "https://youtube.com/watch?v=..."
  source_type: youtube
  date_ingested: 2026-04-12T10:00:00Z
  duration: 3600
  ---

  # Attention Is All You Need

  [Extracted content here...]
  ```
- [ ] Update `.wikibrain/sources.json` manifest on each extraction
- [ ] Tests for each extractor (mock external APIs at boundary)

**Acceptance criteria:**
- `wikibrain ingest https://youtube.com/watch?v=... --dry-run` shows extracted transcript + metadata
- `wikibrain ingest paper.pdf --dry-run` shows extracted text
- `wikibrain ingest https://example.com/article --dry-run` shows clean article text
- `wikibrain ingest https://arxiv.org/abs/2401.12345 --dry-run` shows paper content
- Re-running same source detected as duplicate
- `--type pdf` override works for direct PDF URLs

#### Phase 3: Agent Dispatch (The Core Loop)

**Goal:** `wikibrain ingest <source>` extracts AND compiles wiki pages via agent

Tasks:
- [ ] Implement `Agent` Protocol in `agents/base.py`:
  ```python
  class Agent(Protocol):
      name: str
      def is_available(self) -> bool: ...
      def run(self, prompt: str, cwd: Path) -> AgentResult: ...
  ```
- [ ] Implement `ClaudeAgent`:
  ```python
  cmd = [
      "claude", "-p", prompt,
      "--allowedTools", "Read,Write,Edit,Glob,Grep",
      "--output-format", "json",
      "--max-turns", "25",
  ]
  result = subprocess.run(cmd, capture_output=True, text=True, cwd=wiki_root)
  ```
  - Parse JSON response for `result` field
  - Capture `session_id` for potential follow-ups
  - Handle errors: non-zero exit, JSON parse failure, timeout
- [ ] Implement `CodexAgent`:
  ```python
  cmd = [
      "codex", "exec", prompt,
      "--full-auto",
      "-o", str(output_path),
  ]
  result = subprocess.run(cmd, capture_output=True, text=True, cwd=wiki_root)
  ```
  - Read output from `-o` file
  - Handle `--skip-git-repo-check` if wiki isn't a git repo
- [ ] Implement `detect_agent()` → returns first available agent
- [ ] Implement prompt templates in `core/prompts.py`:
  - **Ingest prompt**: "Read {raw_path}. Create/update wiki pages following the schema in CLAUDE.md. Update index.md. Append to log.md."
  - **Ingest update prompt**: "Source {raw_path} was previously ingested. Existing wiki pages: {pages}. The source has been updated — revise the wiki pages to reflect changes."
  - **Query prompt**: "Read index.md. Answer: {question}. Search wiki pages for relevant content. Cite sources with [[wikilinks]]."
  - **Lint prompt**: "Read index.md and all wiki pages. Check for: broken [[wikilinks]], contradictions between pages, orphan pages not in index, stale content, missing cross-references. Report findings."
- [ ] Implement CLAUDE.md and AGENTS.md templates (plain Python string formatting):
  - Wiki structure conventions
  - Page naming rules
  - Wikilink format (`[[Human-Readable Title]]`)
  - Frontmatter requirements for wiki pages
  - index.md update rules
  - log.md format
- [ ] Wire ingest command: extract → write raw → snapshot wiki/ file list → invoke agent → diff wiki/ to detect created/modified pages → update sources.json manifest with actual pages written
- [ ] Wire query command: build prompt → invoke agent → print result
- [ ] Wire lint command: build prompt → invoke agent → display findings
- [ ] Error handling:
  - Agent not found → clear error message with install instructions
  - Agent timeout → configurable via `--timeout` (default 120s)
  - Agent failure → log to log.md, report error, raw/ preserved for retry
  - Partial failure → wiki left in consistent state (raw written, wiki untouched until agent succeeds)
- [ ] Add `--verbose` flag (show agent command, prompt preview, output)

**Acceptance criteria:**
- `wikibrain ingest https://youtube.com/watch?v=...` creates raw/ file AND wiki pages
- `wikibrain query "what is attention?"` returns synthesized answer with citations
- `wikibrain lint` reports wiki health issues
- Same source re-ingested triggers update flow (R8)
- Works with both Claude Code and Codex
- Agent failures don't corrupt wiki state

#### Phase 4: Polish + Ship

**Goal:** Ready for public release

Tasks:
- [ ] README.md with:
  - One-line install (`pipx install wikibrain`)
  - 30-second demo (init → ingest YouTube → query)
  - Agent setup instructions (Claude Code / Codex)
  - Source types supported
  - Obsidian setup guide
  - Architecture diagram
- [ ] `--help` text polished for all commands
- [ ] Rich output: progress spinners during extraction, styled tables for status/list, colored lint output
- [ ] ~~`wikibrain lint --fix`~~ — moved to Future Considerations (auto-repair is a significant feature, not polish)
- [ ] Publish to PyPI (`hatch publish`)
- [ ] GitHub release with changelog
- [ ] Test full flow on fresh machine (Mac + Linux)

**Acceptance criteria:**
- `pipx install wikibrain` from PyPI works
- Full flow in < 5 minutes: install → init → ingest 2 sources → query → lint
- Works on macOS and Linux
- README is compelling enough for Hacker News/Twitter

## Alternative Approaches Considered

1. **Go/Rust binary** — Rejected: ingestion library ecosystem (yt-dlp, trafilatura, pypdf) is Python-native. Go would require shelling out to Python tools anyway. (see origin: Key Decisions)
2. **Direct API calls** — Rejected: requires API keys, adds cost. Delegating to installed agents uses existing subscriptions. (see origin: Key Decisions)
3. **MCP server architecture** — Rejected: locks to MCP-capable agents, adds complexity. Shell-out is simpler and more portable.
4. **Agentic frameworks (LangChain/CrewAI)** — Rejected: unnecessary complexity for "extract → prompt → shell out." (see origin: Key Decisions)
5. **Schema-only project (no CLI)** — Rejected: user wants a real tool, not another CLAUDE.md template. (see origin: Problem Frame)

## System-Wide Impact

### Interaction Graph

wikibrain CLI → subprocess call → Claude Code/Codex agent → agent reads raw/, reads CLAUDE.md/AGENTS.md schema → agent writes to wiki/, index.md, log.md → wikibrain validates output → updates sources.json manifest.

No callbacks, middleware, or observers. Linear pipeline with clear handoff points.

### Error & Failure Propagation

```
Extraction failure (network, parse) → ExtractorError → reported to user, nothing written
Raw write failure (disk) → IOError → reported, no agent invoked
Agent invocation failure (not found) → AgentNotFoundError → install instructions shown
Agent runtime failure (timeout, crash) → AgentError → raw preserved, log.md records failure
Agent output invalid (no wiki pages created) → ValidationWarning → reported, raw preserved
```

### State Lifecycle Risks

- **Partial ingest**: Raw written but agent fails → safe, raw preserved for retry. Wiki unchanged.
- **Concurrent ingests**: Not supported in v1. Single-user CLI, sequential operations.
- **Manifest drift**: sources.json out of sync with actual files → `wikibrain lint` detects and reports.

### API Surface Parity

Agent-specific interfaces (CLAUDE.md / AGENTS.md) must produce identical wiki output. Test by ingesting same source with both agents and comparing wiki structure.

## Acceptance Criteria

### Functional Requirements

- [ ] `pipx install wikibrain` works on Mac and Linux (R1)
- [ ] `wikibrain init <name>` scaffolds complete wiki structure (R4)
- [ ] `wikibrain ingest <youtube-url>` extracts and compiles (R2, R5)
- [ ] `wikibrain ingest <pdf-path>` extracts and compiles (R2, R5)
- [ ] `wikibrain ingest <web-url>` extracts and compiles (R2, R5)
- [ ] `wikibrain ingest <arxiv-url>` extracts and compiles (R2, R5)
- [ ] `wikibrain ingest <local-file>` extracts and compiles (R2, R5)
- [ ] `wikibrain query "<question>"` returns answer with citations (R5)
- [ ] `wikibrain lint` reports wiki health issues (R5)
- [ ] Wiki uses `[[wikilinks]]` compatible with Obsidian (R6)
- [ ] `wikibrain use <name>` switches active wiki (R7)
- [ ] Re-ingesting same source triggers update, not duplicate (R8)
- [ ] Works with both Claude Code and Codex (R3)
- [ ] `--agent` flag overrides auto-detection (R3)

### Non-Functional Requirements

- [ ] Install-to-working-wiki in < 5 minutes
- [ ] Single ingest operation completes in < 2 minutes (excluding agent time)
- [ ] No API keys required — uses agent subscriptions only

### Quality Gates

- [ ] pytest test suite with > 80% coverage on extractors and core modules
- [ ] ruff linting passes (configured in pyproject.toml)
- [ ] GitHub Actions CI green
- [ ] README with install + quickstart + architecture

## Dependencies & Prerequisites

- Python >= 3.12 (user's standard)
- At least one installed agent: Claude Code or Codex CLI
- Key Python dependencies:
  - `typer[all]` — CLI framework + Rich
  - `youtube-transcript-api` — YouTube transcripts
  - `yt-dlp` — YouTube metadata + fallback
  - `pypdf` — PDF text extraction
  - `trafilatura[all]` — Web article extraction
  - `arxiv` — arxiv paper metadata
  - ~~`jinja2`~~ — not needed; CLAUDE.md/AGENTS.md templates use Python `str.format()` for simple substitution
- Optional: `faster-whisper` for YouTube videos without captions (heavy dep, suggest as extra)

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Agent non-interactive mode doesn't allow file writes as expected | Medium | Critical | Spike Phase 3 agent dispatch early. Test exact commands before building extractors. |
| youtube-transcript-api blocked by YouTube | Low | High | yt-dlp fallback path already designed. Could add Whisper as last resort. |
| Codex sandbox blocks file writes | Medium | High | Test `--full-auto` flag. Fall back to `--sandbox danger-full-access` with user warning. |
| Context window exceeded on large sources | Medium | Medium | Chunking strategy defined. v1 warns + truncates; v1.1 implements smart chunking. |
| PyPI name `wikibrain` taken | Low | Medium | Check availability before publishing. Fallback: `wikibrain-cli` or `thewikibrain`. |

## Future Considerations (NOT v1)

- **Google Docs ingestion (authenticated sources)** — Currently wikibrain only handles public/unauthenticated sources. Google Docs is a common research repository and a high-value ingestion target. The core challenge is authentication: Google requires OAuth2 for any API access to user documents. The Google Drive API can export Docs as plain text/HTML in a single call (simpler than parsing the Docs API JSON structure). Open-source CLI tools typically ship their own OAuth client_id so users just click "Allow" in a browser rather than creating their own Google Cloud project. Unverified OAuth apps show a "This app isn't verified" warning — acceptable for a technical audience, but Google's verification process (requires privacy policy, demo video, 2-6 week review cycle) should be considered once the tool has traction. This feature opens the door to broader Google Drive support (ingest folders of docs) and potentially other authenticated sources (Notion, private wikis). No existing competitor in the Karpathy wiki ecosystem handles authenticated sources.
- `wikibrain lint --fix` (agent auto-repairs issues)
- Knowledge graph visualization (vis.js like llm-wiki-agent)
- Proactive insight surfacing ("these sources contradict on X")
- Twitter/X thread extraction
- Gemini CLI support
- Collaborative wikis (team shared brain)
- Scheduled ingestion (watch folder, RSS feeds)
- `faster-whisper` as optional extra for caption-less videos
- MCP server mode (expose wiki tools to agents)
- Web UI for non-Obsidian users

## Sources & References

### Origin

- **Origin document:** [docs/brainstorms/2026-04-12-llm-wiki-requirements.md](docs/brainstorms/2026-04-12-llm-wiki-requirements.md) — Key decisions carried forward: Python + pipx distribution, harness engineering pattern, agent-agnostic with subscription-based execution, Karpathy three-layer architecture

### Internal References

- User's Python project conventions: `/Users/sanjeevsuresh/edgebench/pyproject.toml` (Hatchling, >=3.12)
- Global agent config: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`

### External References

- [Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — canonical reference
- [Claude Code headless mode docs](https://code.claude.com/docs/en/headless) — `-p` flag, `--allowedTools`, `--output-format`
- [Codex CLI non-interactive docs](https://developers.openai.com/codex/noninteractive) — `exec` command, `--full-auto`
- [Typer documentation](https://typer.tiangolo.com/) — CLI framework
- [youtube-transcript-api](https://github.com/jdepoix/youtube-transcript-api) — v1.2.x instance method API
- [trafilatura docs](https://trafilatura.readthedocs.io/) — web extraction
- [Competitive landscape analysis](docs/brainstorms/2026-04-12-llm-wiki-requirements.md#competitive-landscape-as-of-2026-04-12)
