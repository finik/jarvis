# Heartbeat — Every 60 Minutes

You are running an in-session heartbeat check. Follow these steps IN ORDER. Do not skip steps.

## Step 1: Gather data (silent — no messages yet)

A. Get all open tasks:
   - `list_thoughts(type="task", limit=50)`

B. Search for unseen high-urgency dreaming insights:
   - `search_thoughts("Dreaming insight urgency:high", limit=5)`
   - Ignore results containing "SEEN" in the content

C. Check calendar for events starting in the next 2 hours.

## Step 2: Decision gate — STOP here if nothing is actionable

Ask yourself: is ANY of the following true?
- A task has a concrete deadline (an actual date) that is approaching or overdue
- An unseen urgency:high dreaming insight was found
- A calendar event is starting within 2 hours that the user may not be aware of

If the answer is NO to ALL of the above: **STOP. Do not send any Telegram message. Do not send "all quiet." Do not send "standing by." Say nothing. Skip to Step 5.**

If the answer is YES to any: continue to Step 3.

## Step 3: Send ONE Telegram message

- Send to chat_id from config.sh ($JARVIS_CHAT_ID)
- Be concise: only list what needs attention
- Use `mcp__plugin_telegram_telegram__reply`
- If an unseen urgency:high insight was found, include it, then update that thought to prepend "SEEN [YYYY-MM-DD]: " so it won't resurface

## Step 4: Capture to Open Brain

- `capture_thought("Heartbeat [YYYY-MM-DD HH:MM]: [what you flagged]")`

## Step 5: Renew cron (always run, even if nothing was actionable)

Cron jobs expire after 7 days. Renew on every run:
1. `CronList` — find the heartbeat job
2. `CronDelete` it by ID
3. `CronCreate(cron="7 * * * *", recurring=true, prompt="Read ~/jarvis/heartbeat-prompt.md and follow all instructions in it.")`

## Rules (hard constraints — violating any of these is a bug)

- NEVER send a message if nothing is actionable. Silence = all clear.
- NEVER send between 10pm-8am PST unless a deadline is within 1 hour.
- NEVER count "stalled cycles" or escalate urgency based on how long a task has been open.
- Tasks stay pending until the user acts. That is intentional, not stalled.
- Only flag tasks with concrete deadlines (actual dates) that are approaching or overdue.
- Open-ended tasks without deadlines should sit quietly — do not nag.
- Do NOT use reply_to in Telegram messages.
