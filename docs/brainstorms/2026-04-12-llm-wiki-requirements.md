---
date: 2026-04-12
topic: wikibrain
---

# wikibrain: Agent-Agnostic LLM Knowledge Base CLI

## Problem Frame

Karpathy's LLM Wiki pattern (April 3, 2026) solves the central failure of personal knowledge management: humans can't sustain the bookkeeping. The LLM becomes the librarian; you're the curator/director.

The ecosystem response has been fast but shallow. ~10 open-source implementations appeared within days, but all share critical weaknesses:
- **Markdown-only ingestion** — every tool assumes you manually prep files into `raw/`. The real bottleneck (getting knowledge from YouTube, PDFs, URLs, arxiv into the wiki) is unsolved.
- **Locked to one agent** — almost all are Claude-only. The "most popular" competitor (SamurAIGPT/llm-wiki-agent, 1,666 stars) inherited its stars from a repurposed repo; the wiki code is 5 days old with broken features and shallow multi-agent support.
- **Schema files, not software** — most are CLAUDE.md templates, not installable tools.

**wikibrain** fills the gap: a proper CLI tool with a real multi-source ingestion pipeline that delegates to whichever agent you already have installed. Published under The Lemma (thelemma.dev).

## Requirements

- R1. **CLI tool installable via `pipx install wikibrain`** on Mac and Linux with zero configuration
- R2. **Multi-source ingestion pipeline** — `wikibrain ingest <source>` handles:
  - YouTube videos (transcript via youtube-transcript-api, fallback to yt-dlp + faster-whisper)
  - PDFs (via pypdf/pdfplumber)
  - Web articles/blog posts (via trafilatura)
  - arxiv papers (via arxiv API + PDF extraction)
  - Twitter/X threads
  - Local text/markdown files
  - Each source type produces a structured markdown file in `raw/` with metadata frontmatter (title, source URL, date ingested, source type)
- R3. **Agent-agnostic execution** — delegates LLM work to the user's installed agent:
  - Auto-detects installed agents (claude, codex)
  - Generates appropriate schema files (CLAUDE.md for Claude Code, AGENTS.md for Codex)
  - Shells out to agent with structured prompts for ingest/query/lint operations
  - User can override agent with `--agent <name>` flag
  - v1 supports Claude Code and Codex; Gemini CLI deferred
- R4. **Wiki initialization** — `wikibrain init <name>` scaffolds:
  - `raw/` directory for source materials
  - `wiki/` directory for LLM-generated pages (sources/, entities/, concepts/, syntheses/)
  - `index.md` — content catalog
  - `log.md` — chronological operation record
  - Agent-specific schema file based on detected agent
- R5. **Core operations** following Karpathy's pattern:
  - `wikibrain ingest <source>` — extract text, store in raw/, prompt agent to process into wiki pages
  - `wikibrain query "<question>"` — prompt agent to search wiki and synthesize answer
  - `wikibrain lint` — prompt agent to health-check (contradictions, orphans, staleness, broken wikilinks)
- R6. **Wiki structure** uses interlinked markdown with `[[wikilinks]]`, compatible with Obsidian for visual browsing
- R7. **Multiple wiki support** — user can have multiple wikis for different research domains, switch with `wikibrain use <name>`
- R8. **Incremental updates** — re-ingesting a modified source updates the existing source page rather than creating duplicates (addresses a known weakness in llm-wiki-agent)

## Success Criteria

- A user with Claude Code or Codex installed can go from `pipx install wikibrain` to a working wiki with ingested sources in under 5 minutes
- Ingesting a YouTube video or PDF requires a single command, not manual file preparation
- The same wiki works interchangeably with Claude Code and Codex without reconfiguration
- Clear differentiator vs existing projects: real ingestion pipeline + agent portability + proper CLI distribution

## Scope Boundaries

- NOT a SaaS product or web app — local CLI tool only
- NOT calling LLM APIs directly — always delegates to installed agents (uses subscription, not API keys)
- NOT building a new wiki viewer — Obsidian is the frontend
- NOT implementing RAG or vector databases — follows Karpathy's index-based navigation pattern
- NOT v1: knowledge graph visualization, proactive insight surfacing, collaborative wikis, or scheduled agents (future work)
- NOT v1: Gemini CLI support (deferred until Claude Code + Codex are solid)

## Key Decisions

- **Name: wikibrain** — memorable, communicates "wiki" + "brain" = second brain. Available on PyPI.
- **Org: The Lemma (thelemma.dev)** — published under the brand from day one. GitHub org: thelemma.
- **Python + pipx**: Best ingestion library ecosystem (yt-dlp, trafilatura, pypdf, youtube-transcript-api). Go/Rust rejected because ingestion pipeline quality is the differentiator and Python owns those libraries. pipx solves distribution.
- **Harness engineering pattern**: Tool is a thin orchestrator — extracts text, generates prompts, shells out to agents. No agentic frameworks (LangChain, CrewAI) — unnecessary complexity for "extract → prompt → shell out."
- **Delegate to installed agents**: Uses user's existing subscription (Claude Pro, Codex, etc.) rather than requiring API keys. Lower barrier, but output quality depends on agent capabilities.
- **Karpathy's three-layer architecture**: raw/ (immutable sources), wiki/ (LLM-maintained), schema (co-evolved config). Proven pattern, no need to innovate.
- **Obsidian-compatible wikilinks**: `[[page-name]]` linking. Obsidian is the de facto frontend.

## Competitive Landscape (as of 2026-04-12)

| Project | Stars | Real age | Ingestion | Agent support | Weakness |
|---------|-------|----------|-----------|---------------|----------|
| Karpathy gist | 15,350 | 9 days | N/A (pattern) | Any | Not a tool |
| llm-wiki-agent | 1,666 (inherited) | 5 days | Markdown only | Claude >> others | Fake stars, broken graph cache, no scaling |
| obsidian-wiki | 314 | ~9 days | Markdown only | Multi-agent | No ingestion |
| llmwiki | 304 | ~9 days | Doc upload (web) | Claude MCP only | Locked to Claude |
| llm-wiki-kit | 29 | 5 days | PDF, URL, YouTube | Unknown | Very new, unknown quality |
| wikibrain | — | New | Multi-source CLI | Claude Code + Codex | Needs to ship |

## Dependencies / Assumptions

- Users have at least one coding agent installed (Claude Code or Codex)
- Agents support non-interactive prompt execution (e.g., `claude --print --prompt "..."`)
- YouTube transcript API remains accessible without authentication for most videos
- Target audience: AI/ML researchers and technical users comfortable with CLI tools

## Outstanding Questions

### Resolve Before Planning

(None — all blocking questions resolved)

### Deferred to Planning

- [Affects R2] [Needs research] What is the exact CLI interface for each agent's non-interactive mode? (e.g., `claude --print`, `codex --quiet`)
- [Affects R2] [Technical] Chunking strategy for large PDFs or long YouTube videos that exceed agent context windows
- [Affects R3] [Needs research] Do Claude Code and Codex read schema files (CLAUDE.md / AGENTS.md) automatically when invoked non-interactively, or must schema be passed inline?
- [Affects R7] [Technical] Where should multiple wikis be stored? ~/.wikibrain/ or current directory?
- [Affects R2] [Needs research] Twitter/X thread extraction — which library/approach works reliably in 2026?
- [Affects R8] [Technical] How to detect that a source has been previously ingested and route to update vs. create?

## Next Steps

→ `/ce:plan` for structured implementation planning
