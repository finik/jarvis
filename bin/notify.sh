#!/bin/bash
# Send a Telegram message directly via Bot API — no Claude involved.
# Usage: notify.sh "message text"
# Reads TELEGRAM_BOT_TOKEN from ~/.claude/channels/telegram/.env
# Reads JARVIS_CHAT_ID from ~/.jarvis/config.sh

set -e

MSG="${1:?Usage: notify.sh <message>}"

TOKEN_FILE="$HOME/.claude/channels/telegram/.env"
CONFIG_FILE="$HOME/.jarvis/config.sh"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "ERROR: $TOKEN_FILE not found" >&2
    exit 1
fi

source "$TOKEN_FILE"       # sets TELEGRAM_BOT_TOKEN
source "$CONFIG_FILE"      # sets JARVIS_CHAT_ID

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$JARVIS_CHAT_ID" ]; then
    echo "ERROR: TELEGRAM_BOT_TOKEN or JARVIS_CHAT_ID not set" >&2
    exit 1
fi

curl -s -o /dev/null -w "%{http_code}" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${JARVIS_CHAT_ID}" \
    -d "text=${MSG}" \
    -d "parse_mode=HTML"
