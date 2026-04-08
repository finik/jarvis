#!/usr/bin/env python3
"""
Jarvis Session Monitor
Tails the most recent Claude Code session transcript and prints
clean conversation in real-time.

Usage:
    python3 ~/jarvis/bin/monitor.py
    python3 ~/jarvis/bin/monitor.py --all      # show from beginning
    python3 ~/jarvis/bin/monitor.py --status   # show daemon status only
    python3 ~/jarvis/bin/monitor.py --messages # show Telegram message trace (received/sent)
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from datetime import datetime

PROJECTS_DIR = Path.home() / ".claude" / "projects"
POLL_INTERVAL = 1.0  # seconds

# ANSI colors
RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
CYAN    = "\033[36m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
RED     = "\033[31m"
MAGENTA = "\033[35m"


def get_daemon_status() -> list[tuple[str, str, str]]:
    """Returns list of (label, pid_or_dash, status) for Jarvis launchd jobs."""
    try:
        out = subprocess.check_output(["launchctl", "list"], text=True)
    except subprocess.CalledProcessError:
        return []
    rows = []
    for line in out.splitlines():
        if "jarvis" not in line.lower() and "claude" not in line.lower():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        pid, exit_code, label = parts[0], parts[1], parts[2]
        if pid != "-":
            status = f"{GREEN}running (PID {pid}){RESET}"
        elif exit_code == "0":
            status = f"{DIM}idle (last exit: 0){RESET}"
        else:
            status = f"{RED}crashed (exit: {exit_code}){RESET}"
        rows.append((label, pid, status))
    return rows


def print_status():
    print(f"\n{BOLD}── Jarvis Daemon Status ──{RESET}")
    rows = get_daemon_status()
    if not rows:
        print(f"  {RED}No Jarvis daemons found{RESET}")
    for label, pid, status in rows:
        # Strip common launchd prefix to get a short display name
        short = label.split(".")[-1] if "." in label else label
        print(f"  {CYAN}{short:<20}{RESET} {status}")
    print()


def find_latest_transcript() -> Path | None:
    """Find the most recently modified JSONL transcript."""
    transcripts = []
    if not PROJECTS_DIR.exists():
        return None
    for p in PROJECTS_DIR.rglob("*.jsonl"):
        if "subagents" not in str(p):
            transcripts.append(p)
    if not transcripts:
        return None
    return max(transcripts, key=lambda p: p.stat().st_mtime)


def extract_text(content) -> str:
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                t = block.get("text", "").strip()
                if t:
                    parts.append(t)
        return "\n".join(parts)
    return ""


def format_message(obj: dict) -> str | None:
    msg_type = obj.get("type", "")
    if msg_type not in ("user", "assistant"):
        return None
    if obj.get("isMeta"):
        return None

    message = obj.get("message", {})
    content = message.get("content", "")
    if not content:
        return None

    # Skip pure tool result messages
    if isinstance(content, list):
        non_tool = [b for b in content if isinstance(b, dict) and b.get("type") not in ("tool_result", "tool_use", "thinking")]
        if not non_tool:
            return None

    text = extract_text(content)
    if not text:
        return None

    # Skip system caveat injections
    if "<local-command-caveat>" in text or "<command-name>" in text:
        return None

    ts_raw = obj.get("timestamp", "")
    try:
        ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00")).strftime("%H:%M:%S")
    except Exception:
        ts = "--:--:--"

    if msg_type == "user":
        label = f"{GREEN}{BOLD}You{RESET}"
        color = GREEN
    else:
        label = f"{CYAN}{BOLD}Jarvis{RESET}"
        color = CYAN

    # Truncate very long messages for readability
    MAX = 400
    display = text if len(text) <= MAX else text[:MAX] + f"  {DIM}[+{len(text)-MAX} chars]{RESET}"

    return f"{DIM}{ts}{RESET} {label}: {display}"


def tail_transcript(path: Path, from_start: bool = False):
    """Tail a transcript file, printing new messages as they appear."""
    print(f"\n{BOLD}── Monitoring: {path.name} ──{RESET}")
    print(f"{DIM}(Ctrl+C to stop){RESET}\n")

    lines_seen = 0
    if not from_start:
        # Start from end of file — only show new messages
        lines_seen = sum(1 for _ in path.open())

    try:
        while True:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            new_lines = lines[lines_seen:]

            for line in new_lines:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    formatted = format_message(obj)
                    if formatted:
                        print(formatted)
                except json.JSONDecodeError:
                    pass

            lines_seen += len(new_lines)
            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print(f"\n{DIM}Monitor stopped.{RESET}\n")


def find_jarvis_transcript() -> Path | None:
    """Find the active jarvis session transcript (not heartbeat/processor)."""
    jarvis_dir = PROJECTS_DIR / ("-Users-" + Path.home().name + "-jarvis")
    if not jarvis_dir.exists():
        return None
    sessions_dir = Path.home() / ".claude" / "sessions"
    # Find PID with cwd=~/jarvis
    active_session_id = None
    if sessions_dir.exists():
        for sf in sessions_dir.glob("*.json"):
            try:
                d = json.loads(sf.read_text())
                if d.get("cwd") == str(Path.home() / "jarvis"):
                    active_session_id = d.get("sessionId")
                    break
            except Exception:
                pass
    if active_session_id:
        p = jarvis_dir / f"{active_session_id}.jsonl"
        if p.exists():
            return p
    # Fallback: most recent in jarvis dir
    candidates = [p for p in jarvis_dir.glob("*.jsonl") if "subagents" not in str(p)]
    return max(candidates, key=lambda p: p.stat().st_mtime) if candidates else None


def show_message_trace():
    """Parse jarvis transcript and show all received/sent Telegram messages."""
    transcript = find_jarvis_transcript()
    if not transcript:
        print(f"{RED}No jarvis transcript found{RESET}")
        return

    print(f"\n{BOLD}── Telegram Message Trace: {transcript.name[:12]}… ──{RESET}\n")

    lines = transcript.read_text(encoding="utf-8", errors="replace").splitlines()
    pending_reply_input = None  # buffer tool_use for reply

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg = obj.get("message", {})
        content = msg.get("content", "")

        # Received Telegram message
        if obj.get("type") == "user" and isinstance(content, str):
            m = re.search(r'<channel source="plugin:telegram:telegram"[^>]*message_id="(\d+)"[^>]*user="([^"]+)"[^>]*ts="([^"]+)"[^>]*>(.*?)</channel>', content, re.DOTALL)
            if m:
                mid, user, ts_raw, text = m.group(1), m.group(2), m.group(3), m.group(4).strip()
                try:
                    ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00")).strftime("%H:%M:%S")
                except Exception:
                    ts = ts_raw
                print(f"{DIM}{ts}{RESET} {GREEN}{BOLD}← RECV{RESET} msg_id={BOLD}{mid}{RESET} from={user}")
                print(f"       {GREEN}{text[:200]}{RESET}")
                continue

        # Sent reply (tool_use)
        if obj.get("type") == "assistant" and isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_use" and "reply" in block.get("name", ""):
                    inp = block.get("input", {})
                    pending_reply_input = (block.get("id"), inp.get("text", "")[:200])

        # Tool result for the reply
        if obj.get("type") == "user" and isinstance(content, list) and pending_reply_input:
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    result_content = block.get("content", "")
                    if isinstance(result_content, list):
                        result_text = " ".join(b.get("text","") for b in result_content if isinstance(b, dict))
                    else:
                        result_text = str(result_content)
                    # Extract sent message id
                    id_match = re.search(r'id:\s*(\d+)', result_text)
                    sent_id = id_match.group(1) if id_match else "?"
                    tool_id, reply_text = pending_reply_input
                    status = f"{GREEN}✓ sent msg_id={BOLD}{sent_id}{RESET}" if "sent" in result_text.lower() else f"{RED}✗ {result_text[:80]}{RESET}"
                    print(f"         {CYAN}{BOLD}→ SENT{RESET} {status}")
                    print(f"       {CYAN}{reply_text}{RESET}")
                    pending_reply_input = None
                    break

    print(f"\n{DIM}End of trace.{RESET}\n")


def main():
    args = sys.argv[1:]

    if "--status" in args:
        print_status()
        return

    if "--messages" in args:
        print_status()
        show_message_trace()
        return

    print_status()

    transcript = find_latest_transcript()
    if not transcript:
        print(f"{RED}No transcripts found in {PROJECTS_DIR}{RESET}")
        sys.exit(1)

    from_start = "--all" in args
    tail_transcript(transcript, from_start=from_start)


if __name__ == "__main__":
    main()
