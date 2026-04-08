# Jarvis

A self-hosted personal AI agent built on [Claude Code](https://claude.ai/code). Runs continuously on a Mac Mini, communicates via Telegram, and maintains memory across sessions through a two-tier system: an in-context short-term file and a long-term vector memory store ([Open Brain](https://github.com/finik/openbrain)).

For the full architecture and design rationale, see [DESIGN.md](DESIGN.md).

---

## What it does

- **Always-on Telegram agent** — Claude Code runs as a persistent daemon, listening for Telegram messages and responding with full tool access (calendar, email, memory search, etc.)
- **Heartbeat** — every 30 minutes, checks Open Brain for pending tasks and high-urgency insights; sends a Telegram message if anything is actionable
- **Morning digest** — daily at 8am, reads Gmail and Google Calendar and writes a structured briefing to `logs/last-digest.md`
- **Dreaming** — nightly at 2:17am, consolidates Open Brain memory: deduplicates, merges related thoughts, generates insights, cleans stale tasks, and updates `MEMORY.md` (prompt and scripts live in the [openbrain](https://github.com/finik/openbrain) submodule)
- **Transcript processor** — every 30 minutes, extracts memorable facts from Claude Code session transcripts and saves them to Open Brain (script lives in the openbrain submodule)

---

## Architecture

```
Mac Mini
│
├── launchd: claude-session   (KeepAlive)
│     └── claude --channels plugin:telegram@...
│           WorkingDirectory: ~/jarvis  ← CLAUDE.md auto-loaded
│           In-session cron: heartbeat every 30 min
│
├── launchd: claude-digest    (8:00am daily)
│     └── claude -p digest-prompt.md --no-session-persistence
│
├── launchd: claude-dreaming  (2:17am nightly)
│     └── claude -p openbrain/prompts/dreams-prompt.md
│
└── launchd: claude-transcripts (every 30 min)
      └── openbrain/bin/process-transcripts.py → Open Brain
```

---

## Prerequisites

- **macOS** (uses launchd for scheduling)
- **[Claude Code CLI](https://claude.ai/code)** installed and authenticated
- **Telegram account** + a Claude Code Telegram plugin ([claude-plugins-official](https://claudeplugins.com) or equivalent)
- **[Open Brain](https://github.com/finik/openbrain)** deployed to Supabase (see below)
- **Google Calendar MCP** configured in Claude Code (for digest and calendar tools)
- **Gmail MCP** configured in Claude Code (for digest email review)

---

## Open Brain setup

Open Brain is the long-term memory backend — a Supabase Edge Function with pgvector embeddings. It is included as a git submodule at `openbrain/`.

See the [Open Brain README](https://github.com/finik/openbrain) for full setup instructions, including Supabase project creation, deployment, and MCP registration.

---

## Jarvis setup

```bash
git clone --recurse-submodules https://github.com/<you>/jarvis ~/jarvis
cd ~/jarvis
bash bin/install.sh
```

The first run creates `~/.jarvis/config.sh` from `config.example.sh` and exits. Fill it in:

```bash
# ~/.jarvis/config.sh
JARVIS_NAME="Your Name"
JARVIS_USERNAME="yourmacusername"
JARVIS_CHAT_ID="123456789"          # from @userinfobot on Telegram
JARVIS_LAUNCHD_PREFIX="com.yourname"
JARVIS_CALENDAR_PRIMARY="you@gmail.com"
# ... see config.example.sh for all options
```

Then re-run:

```bash
bash bin/install.sh
```

This will:
- Substitute your config values into prompt files
- Generate launchd plists into `~/.jarvis/launchd/`
- Load all agents via `launchctl`
- Create `~/.jarvis/USER.md` from `USER.md.example` (fill in your profile)

Check that everything is running:
```bash
launchctl list | grep com.yourname
python3 ~/jarvis/bin/monitor.py --status
```

---

## Customization

| File | Purpose |
|---|---|
| `SOUL.md` | Jarvis's personality and behavioral boundaries |
| `INSTRUCTIONS.md` | Operating rules, tool preferences, capture rules |
| `~/.jarvis/USER.md` | Your profile — who you are, context Jarvis should always have |
| `~/.jarvis/MEMORY.md` | Short-term memory — active tasks, hot projects, recent decisions |
| `heartbeat-prompt.md` | What the hourly heartbeat checks and how it reports |
| `digest-prompt.md` | Morning briefing format and scope |
| `openbrain/prompts/dreams-prompt.md` | Nightly memory consolidation behavior (in submodule) |

---

## Open Brain Viewer

A web app for browsing and exploring your Open Brain memory visually, with force-directed graph, semantic search, and demo mode.

**Live:** [openbrain.finik.net](https://openbrain.finik.net/)
**Demo:** [openbrain.finik.net/?demo](https://openbrain.finik.net/?demo)
**Location:** `openbrain/viewer/` (submodule)

See the [Open Brain README](https://github.com/finik/openbrain) for viewer setup and usage details.

---

## Monitoring

```bash
# Live conversation stream (new messages only)
python3 ~/jarvis/bin/monitor.py

# From the beginning of the current session
python3 ~/jarvis/bin/monitor.py --all

# Daemon status only
python3 ~/jarvis/bin/monitor.py --status

# Telegram message trace (received + sent)
python3 ~/jarvis/bin/monitor.py --messages
```

---

## Logs

All logs are written to `~/.jarvis/logs/` (gitignored):

| File | Written by |
|---|---|
| `last-digest.md` | Morning digest |
| `dreaming-YYYY-MM-DD.md` | Nightly dreaming run |
| `transcript-state.json` | Transcript processor (tracks processed sessions) |
