#!/bin/bash
# Starts the Jarvis Claude session.
# Handles permission dialogs, waits for Claude to finish starting,
# then injects the startup checklist trigger as a user message.

exec expect -c '
set timeout -1

spawn $env(HOME)/.local/bin/claude \
    --channels plugin:telegram@claude-plugins-official \
    --dangerously-skip-permissions

# Handle any startup permission dialogs (trust folder, limits, etc.)
# Also watch for "bypass" which appears at end of startup screen
set timeout 30
expect {
    "Stop and wait for limit" { send "\r"; exp_continue }
    "trust this folder"       { send "1\r"; exp_continue }
    "Yes, I trust"            { send "1\r"; exp_continue }
    "Medium (recommended)"    { after 500; send "\r"; exp_continue }
    "bypass"                  { }
    timeout                   { }
    eof                       { exit }
}

# Claude is ready — inject the checklist as a user message
after 1500
send "Run Session Start Checklist from INSTRUCTIONS.md\r"

# Wait indefinitely, handling any mid-session prompts
set timeout -1
expect {
    "rate-limit-options"  { exec /bin/bash -c {~/jarvis/bin/notify.sh "⚠️ Jarvis hit a rate limit. Auto-selecting option 1."}; after 1000; send "\r"; exp_continue }
    "Stop and wait"        { exec /bin/bash -c {~/jarvis/bin/notify.sh "⚠️ Jarvis hit a rate limit. Waiting for reset."}; after 1000; send "\r"; exp_continue }
    eof                    { }
}
'
