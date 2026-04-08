# Jarvis — Design Document

**Status**: Live (March 2026)
**Repo**: `~/jarvis`

---

## Overview

Jarvis is a self-hosted personal AI agent built on Claude Code. It runs continuously on a Mac Mini M1, communicates via Telegram, and maintains memory across sessions through a two-tier memory system.

Long-term memory is handled by [Open Brain](https://github.com/finik/openbrain) (included as a git submodule). See that repo for the memory backend architecture, MCP tools, viewer, and automation scripts.

---

## Architecture

```
Mac Mini M1
│
├── launchd: {PREFIX}.claude-session      (KeepAlive)
│     └── claude --channels plugin:telegram@...
│           WorkingDirectory: ~/jarvis  ← CLAUDE.md auto-loaded
│           In-session cron: heartbeat every 60 min
│
├── launchd: {PREFIX}.claude-digest       (8:00am daily)
│     └── claude -p digest-prompt.md --no-session-persistence
│
├── launchd: {PREFIX}.claude-dreaming     (2:17am nightly)
│     └── claude -p openbrain/prompts/dreams-prompt.md
│
├── launchd: {PREFIX}.claude-transcripts  (every 30 min)
│     └── openbrain/bin/process-transcripts.py → Open Brain
│
└── launchd: {PREFIX}.openbrain-viewer    (KeepAlive)
      └── python3 -m http.server 8765
```

All launchd plists are generated from templates by `bin/install.sh`. Jarvis templates live in `launchd/`, Open Brain templates in `openbrain/launchd/`. Generated files go to `~/.jarvis/launchd/` (gitignored).

---

## Session Files

CLAUDE.md auto-loads because it's in the WorkingDirectory. It instructs Claude to read:

| File | Purpose | Location |
|---|---|---|
| `SOUL.md` | Personality, tone, behavioral boundaries | `~/jarvis/` |
| `INSTRUCTIONS.md` | Operating rules, tool preferences, capture rules | `~/jarvis/` |
| `~/.jarvis/USER.md` | User's static profile | `~/.jarvis/` (gitignored) |
| `~/.jarvis/MEMORY.md` | Short-term memory | `~/.jarvis/` (gitignored) |

`~/.jarvis/` is the runtime workspace: logs, config, MEMORY.md, USER.md, and generated launchd plists. Separate from the git repo, never committed.

---

## Memory System (Two-Tier)

### Tier 1: MEMORY.md (Short-Term)

**File**: `~/.jarvis/MEMORY.md`
**Size limit**: ~60 lines — always in context.
**Managed by**: Dreaming nightly — promotes from Open Brain, evicts stale entries.

What belongs: tasks due soon, active decisions, hot projects, known system issues.
What doesn't: completed tasks, stable decisions, historical context (→ Open Brain).

### Tier 2: Open Brain (Long-Term)

**Repo**: [`openbrain/`](https://github.com/finik/openbrain) (git submodule)

Persistent storage via Supabase + pgvector. See the [Open Brain README](https://github.com/finik/openbrain) for full architecture, MCP tools, search design, and viewer docs.

What belongs: everything with lasting value — decisions, facts, preferences, dreaming insights.
What doesn't: time-bound reminders (→ CronCreate), calendar events, recruiter emails, telemetry.

---

## Scheduled Jobs

### Heartbeat (in-session, every 60 min)

**Prompt**: `heartbeat-prompt.md`
**Mechanism**: In-session `CronCreate`, recreated on every session start.

Checks Open Brain for tasks with approaching deadlines and unseen high-urgency dreaming insights. Sends a Telegram message only if something is actionable. Silence = all clear.

### Digest (8:00am daily)

**Prompt**: `digest-prompt.md`
**Output**: `~/.jarvis/logs/last-digest.md`

Gmail + Google Calendar review. Read by the main session when the user references the morning briefing.

### Dreaming (2:17am nightly)

**Prompt**: `openbrain/prompts/dreams-prompt.md`
**Log**: `~/.jarvis/logs/dreaming-YYYY-MM-DD.md`

Memory consolidation: dedup, merge, generate insights, clean tasks, update MEMORY.md. See [Open Brain docs](https://github.com/finik/openbrain) for the full dreaming design.

### Transcript Processor (every 30 min)

**Script**: `openbrain/bin/process-transcripts.py`

Extracts facts from Claude Code session logs into Open Brain.

---

## MCP Servers

| Server | Purpose |
|---|---|
| [Open Brain](https://github.com/finik/openbrain) | Persistent memory (submodule) |
| Telegram | Primary communication channel |
| Gmail | Email read/search |
| Google Calendar | Calendar read/write |
| Bodyspec | DEXA scan / health data |

---

## Key Behavioral Rules

- Heartbeat checks Open Brain tasks only — no email/calendar
- Time-bound reminders use CronCreate, never Open Brain
- Behavioral rules go in INSTRUCTIONS.md, not memory files
- MEMORY.md stays under 60 lines — dreaming is the only process that writes it
- No notifications 10pm–8am unless deadline within 1 hour

---

## Known Issues

- Gmail MCP search is unreliable — query param sometimes ignored, returns recent emails instead
- Google Calendar MCP requires camelCase params (`timeMin`/`timeMax`/`calendarId`) — snake_case is silently ignored
- DESIGN.md is not loaded at session start — for reference only
