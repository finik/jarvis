#!/bin/bash
# Injected as context before every user message in the Jarvis session.
# Output is prepended by Claude Code's UserPromptSubmit hook.

# 1. Always inject current datetime
echo "[Context: Current time: $(date '+%Y-%m-%d %H:%M %Z')]"

# 2. Startup guard — fires once per session restart
#    start-session.sh deletes this flag on spawn; we create it here after first trigger.
STARTUP_FLAG="/tmp/jarvis-startup-done"
if [ ! -f "$STARTUP_FLAG" ]; then
    touch "$STARTUP_FLAG"
    echo "[Context: New session started. Before responding to this message, complete the Session Start Checklist from INSTRUCTIONS.md: read SOUL.md, USER.md, search Open Brain, send 'Jarvis online.' to Telegram, create CronCreate heartbeat. Then handle the message below.]"
fi
