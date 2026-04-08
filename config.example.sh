#!/bin/bash
# Jarvis configuration — copy to config.sh and fill in your values.
# config.sh is gitignored and never committed.

# Your first name (used in prompts)
JARVIS_NAME="Your Name"

# Your macOS username
JARVIS_USERNAME="yourname"

# Telegram chat_id — get yours by messaging @userinfobot on Telegram
JARVIS_CHAT_ID="000000000"

# Telegram plugin identifier (leave as-is unless you're using a different plugin)
JARVIS_TELEGRAM_PLUGIN="claude-plugins-official"

# launchd label prefix (e.g. com.yourname or net.yourname)
JARVIS_LAUNCHD_PREFIX="com.yourname"

# Google Calendar IDs
JARVIS_CALENDAR_PRIMARY="you@gmail.com"
JARVIS_CALENDAR_SPORTS="your-sports-cal-id@import.calendar.google.com"
JARVIS_CALENDAR_FAMILY="your-family-cal-id@group.calendar.google.com"

# Node.js version (used in PATH setup)
JARVIS_NODE_VERSION="v18.17.1"

# Python version (used in PATH setup)
JARVIS_PYTHON_VERSION="3.13"

# Workspace directory — runtime files (logs, config, USER.md, MEMORY.md, generated plists)
# Never inside the git repo. Default is fine for most installs.
JARVIS_WORKSPACE="$HOME/.jarvis"
