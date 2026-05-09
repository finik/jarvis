#!/bin/bash
# Jarvis session watchdog — runs every 15 minutes via launchd.
# Checks if the Claude session is alive and responsive.
# On failure: sends Telegram notification with context, then restarts.

set -euo pipefail

NOTIFY="$HOME/jarvis/bin/notify.sh"
SESSION_LOG="$HOME/.jarvis/logs/session.log"
SESSION_LABEL="net.finik.claude-session"
STALE_MINUTES=75  # heartbeat is hourly, so 75 min = missed one full cycle
INCIDENT_FILE="$HOME/.jarvis/watchdog-incident.md"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $*"; }

# Write incident file so the restarted session knows what happened and can investigate/fix
write_incident() {
    local reason="$1"
    local context="$2"
    cat > "$INCIDENT_FILE" <<INCIDENT
# Watchdog Incident — $(date '+%Y-%m-%d %H:%M:%S %Z')

## Reason
$reason

## Context
$context

## Session log tail (last 30 lines before restart)
\`\`\`
$(tail -30 "$SESSION_LOG" 2>/dev/null || echo "no log available")
\`\`\`

## Action taken
Session force-restarted via \`launchctl kickstart -k\`.

## Instructions for new session
1. Read this file to understand what happened
2. Check session-prev.log for the full previous session log
3. If the cause is a new interactive prompt pattern, add it to start-session.sh expect block
4. If the cause is an MCP hang or rate limit, note it in Open Brain
5. Delete this file after processing: rm ~/.jarvis/watchdog-incident.md
INCIDENT
}

# --- Check 1: Is the claude process actually running? ---
# The launchd job runs expect -> claude. Check if a claude process exists
# that's a child of an expect process running start-session.sh.
CLAUDE_PID=$(pgrep -f "claude.*--channels.*plugin:telegram" 2>/dev/null | head -1 || true)

if [ -z "$CLAUDE_PID" ]; then
    log "FAIL: No claude session process found"
    write_incident "Claude process not found" "pgrep found no process matching 'claude.*--channels.*plugin:telegram'. The process may have crashed or exited unexpectedly."
    "$NOTIFY" "Watchdog: Claude session process not found. Restarting."
    launchctl kickstart -k "gui/$(id -u)/$SESSION_LABEL"
    log "Restart triggered"
    exit 0
fi

# --- Check 2: Is the session log fresh? ---
# If the log hasn't been modified in STALE_MINUTES, the session is frozen.
if [ -f "$SESSION_LOG" ]; then
    LAST_MOD=$(stat -f %m "$SESSION_LOG")
    NOW=$(date +%s)
    AGE_MIN=$(( (NOW - LAST_MOD) / 60 ))

    if [ "$AGE_MIN" -ge "$STALE_MINUTES" ]; then
        log "FAIL: session.log is ${AGE_MIN}m stale (threshold: ${STALE_MINUTES}m)"
        write_incident "Session stale — no log activity for ${AGE_MIN} minutes" "Heartbeat runs hourly. Log not modified for ${AGE_MIN}m (threshold: ${STALE_MINUTES}m). Session is likely frozen — rate limit dialog, MCP hang, or compaction stall."
        "$NOTIFY" "Watchdog: Session stale for ${AGE_MIN}m (no heartbeat). Restarting."
        launchctl kickstart -k "gui/$(id -u)/$SESSION_LABEL"
        log "Restart triggered"
        exit 0
    fi
else
    log "WARN: session.log not found at $SESSION_LOG"
fi

# --- Check 3: Is the session stuck at an interactive prompt? ---
# Grab the last non-empty lines and look for prompt patterns.
if [ -f "$SESSION_LOG" ]; then
    # Get the last 5 non-empty lines
    TAIL=$(tail -20 "$SESSION_LOG" | grep -v '^$' | tail -5)

    # Patterns that indicate an unanswered interactive prompt
    # (rate limit is handled by expect, but catch anything else)
    if echo "$TAIL" | grep -qE '(\? \(Y/n\)|\? \(y/N\)|Select an option|Enter a number|Press Enter|Continue\?|Confirm\?)'; then
        # Only flag if the log hasn't been written to in 5+ minutes
        # (prompt might have just appeared and expect will handle it)
        if [ "$AGE_MIN" -ge 5 ]; then
            PROMPT_CONTEXT=$(echo "$TAIL" | tail -3 | tr '\n' ' ' | cut -c1-200)
            log "FAIL: Session stuck at prompt for ${AGE_MIN}m: $PROMPT_CONTEXT"
            write_incident "Session stuck at interactive prompt for ${AGE_MIN} minutes" "Detected unanswered prompt in session.log. The expect wrapper in start-session.sh did not handle this pattern. Prompt text: ${PROMPT_CONTEXT}"
            "$NOTIFY" "Watchdog: Session stuck at prompt (${AGE_MIN}m): ${PROMPT_CONTEXT}. Restarting."
            launchctl kickstart -k "gui/$(id -u)/$SESSION_LABEL"
            log "Restart triggered"
            exit 0
        fi
    fi
fi

log "OK: PID=$CLAUDE_PID, log age=${AGE_MIN:-?}m"
