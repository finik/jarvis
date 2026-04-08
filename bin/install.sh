#!/bin/bash
# Jarvis install script — generates config, plists, and loads launchd agents.
# Safe to re-run (idempotent).

set -e

JARVIS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$HOME/.jarvis/config.sh"
CONFIG_EXAMPLE="$JARVIS_DIR/config.example.sh"
LAUNCHD_TEMPLATES="$JARVIS_DIR/launchd"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"

echo "Installing Jarvis from $JARVIS_DIR"

# ── Step 1: Ensure config.sh exists in workspace ────────────────────────────
mkdir -p "$HOME/.jarvis"

if [ ! -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
    echo ""
    echo "Created ~/.jarvis/config.sh from config.example.sh"
    echo "Edit $CONFIG_FILE with your values, then re-run install.sh"
    echo ""
    exit 0
fi

source "$CONFIG_FILE"

# Default workspace if not set in config
JARVIS_WORKSPACE="${JARVIS_WORKSPACE:-$HOME/.jarvis}"

# Validate required variables
for var in JARVIS_USERNAME JARVIS_CHAT_ID JARVIS_LAUNCHD_PREFIX JARVIS_CALENDAR_PRIMARY; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set in $CONFIG_FILE"
        exit 1
    fi
done

# ── Step 2: Ensure workspace directories exist ───────────────────────────────
mkdir -p "$JARVIS_WORKSPACE/logs" "$JARVIS_WORKSPACE/launchd"
echo "Workspace: $JARVIS_WORKSPACE"

# ── Step 3: Generate plists from templates into workspace ────────────────────
echo "Generating launchd plists..."

for template in "$LAUNCHD_TEMPLATES"/*.plist.template; do
    basename="${template%.template}"
    shortname="$(basename "$basename")"  # e.g. claude-session.plist
    outfile="$JARVIS_WORKSPACE/launchd/${JARVIS_LAUNCHD_PREFIX}.${shortname}"

    sed \
        -e "s|{{JARVIS_USERNAME}}|$JARVIS_USERNAME|g" \
        -e "s|{{JARVIS_LAUNCHD_PREFIX}}|$JARVIS_LAUNCHD_PREFIX|g" \
        -e "s|{{JARVIS_NODE_VERSION}}|${JARVIS_NODE_VERSION:-v18.17.1}|g" \
        -e "s|{{JARVIS_PYTHON_VERSION}}|${JARVIS_PYTHON_VERSION:-3.13}|g" \
        -e "s|{{JARVIS_DIR}}|$JARVIS_DIR|g" \
        -e "s|{{JARVIS_WORKSPACE}}|$JARVIS_WORKSPACE|g" \
        "$template" > "$outfile"

    echo "  Generated: $(basename "$outfile")"
done

# ── Step 4: Substitute config values into source prompt files ────────────────
echo "Patching prompt files..."

sub() {
    local file="$1"
    if [ -f "$JARVIS_DIR/$file" ]; then
        sed -i '' \
            -e "s|{{JARVIS_CHAT_ID}}|$JARVIS_CHAT_ID|g" \
            -e "s|{{JARVIS_CALENDAR_PRIMARY}}|$JARVIS_CALENDAR_PRIMARY|g" \
            -e "s|{{JARVIS_CALENDAR_SPORTS}}|${JARVIS_CALENDAR_SPORTS:-}|g" \
            -e "s|{{JARVIS_CALENDAR_FAMILY}}|${JARVIS_CALENDAR_FAMILY:-}|g" \
            -e "s|{{JARVIS_USERNAME}}|$JARVIS_USERNAME|g" \
            -e "s|{{JARVIS_TELEGRAM_PLUGIN}}|${JARVIS_TELEGRAM_PLUGIN:-claude-plugins-official}|g" \
            -e "s|{{JARVIS_DIR}}|$JARVIS_DIR|g" \
            -e "s|{{JARVIS_WORKSPACE}}|$JARVIS_WORKSPACE|g" \
            -e "s|{{JARVIS_NAME}}|${JARVIS_NAME:-the user}|g" \
            "$JARVIS_DIR/$file"
        echo "  Patched: $file"
    fi
}

sub "digest-prompt.md"
sub "heartbeat-prompt.md"
sub "openbrain/prompts/dreams-prompt.md"
sub "INSTRUCTIONS.md"
sub "CLAUDE.md"
sub "bin/start-session.sh"

# Also process openbrain launchd templates
OPENBRAIN_TEMPLATES="$JARVIS_DIR/openbrain/launchd"
if [ -d "$OPENBRAIN_TEMPLATES" ]; then
    for template in "$OPENBRAIN_TEMPLATES"/*.plist.template; do
        [ -f "$template" ] || continue
        basename="${template%.template}"
        shortname="$(basename "$basename")"
        outfile="$JARVIS_WORKSPACE/launchd/${JARVIS_LAUNCHD_PREFIX}.${shortname}"

        sed \
            -e "s|{{JARVIS_USERNAME}}|$JARVIS_USERNAME|g" \
            -e "s|{{JARVIS_LAUNCHD_PREFIX}}|$JARVIS_LAUNCHD_PREFIX|g" \
            -e "s|{{JARVIS_NODE_VERSION}}|${JARVIS_NODE_VERSION:-v18.17.1}|g" \
            -e "s|{{JARVIS_PYTHON_VERSION}}|${JARVIS_PYTHON_VERSION:-3.13}|g" \
            -e "s|{{JARVIS_DIR}}|$JARVIS_DIR|g" \
            -e "s|{{JARVIS_WORKSPACE}}|$JARVIS_WORKSPACE|g" \
            "$template" > "$outfile"

        echo "  Generated (openbrain): $(basename "$outfile")"
    done
fi

# ── Step 5: Create USER.md in workspace if not present ──────────────────────
if [ ! -f "$JARVIS_WORKSPACE/USER.md" ]; then
    cp "$JARVIS_DIR/USER.md.example" "$JARVIS_WORKSPACE/USER.md"
    echo "Created $JARVIS_WORKSPACE/USER.md from USER.md.example — fill in your profile"
fi

# ── Step 6: Patch ~/.claude.json to skip trust dialog ───────────────────────
CLAUDE_JSON="$HOME/.claude.json"
python3 - "$JARVIS_DIR" "$CLAUDE_JSON" <<'PYEOF'
import json, sys, os

jarvis_dir = sys.argv[1]
claude_json = sys.argv[2]

data = {}
if os.path.exists(claude_json):
    with open(claude_json) as f:
        data = json.load(f)

data.setdefault("projects", {}).setdefault(jarvis_dir, {})["hasTrustDialogAccepted"] = True

with open(claude_json, "w") as f:
    json.dump(data, f, indent=2)

print(f"Trust dialog accepted for {jarvis_dir}")
PYEOF

# ── Step 7: Ensure LaunchAgents dir exists ───────────────────────────────────
mkdir -p "$LAUNCH_AGENTS"

# ── Step 8: Load plists into launchd ─────────────────────────────────────────
echo "Loading launchd agents..."

for plist in "$JARVIS_WORKSPACE/launchd/${JARVIS_LAUNCHD_PREFIX}."*.plist; do
    [ -f "$plist" ] || continue
    dst="$LAUNCH_AGENTS/$(basename "$plist")"

    launchctl unload "$dst" 2>/dev/null || true
    rm -f "$dst"
    ln -s "$plist" "$dst"
    launchctl load "$dst"
    echo "  Loaded: $(basename "$plist")"
done

echo ""
echo "Jarvis installed. Check status with:"
echo "  launchctl list | grep $JARVIS_LAUNCHD_PREFIX"
echo ""
echo "Workspace: $JARVIS_WORKSPACE"
echo "Logs:      $JARVIS_WORKSPACE/logs"
