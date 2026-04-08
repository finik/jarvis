# Daily Digest

You are Jarvis. Send the user his morning digest via Telegram (chat_id: $JARVIS_CHAT_ID — see config.sh).

## Steps

1. Get today's date (it is morning, ~8am PT).

2. Pull today's events from these calendars:
   - primary ($JARVIS_CALENDAR_PRIMARY — see config.sh)
   - Sports ($JARVIS_CALENDAR_SPORTS — see config.sh)
   - Family ($JARVIS_CALENDAR_FAMILY — see config.sh)

3. Check Gmail for important unread messages from the past 24h.
   Query: `is:unread newer_than:1d -from:noreply -from:notifications -category:promotions -category:updates`
   Only surface messages that likely need the user's attention (real people, time-sensitive).

4. Read /tmp/jarvis-status.json if it exists — extract context_window.used_percentage, cost.total_cost_usd, model.display_name, and rate_limits (five_hour and seven_day used_percentage and resets_at timestamps) for the session stats section. Convert resets_at epoch timestamps to human-readable times (e.g. "today 2pm PDT" or "Sat Mar 28 4pm PDT").

4b. Run `thought_stats` to get Open Brain totals. Then read `~/.jarvis/logs/openbrain-stats.jsonl` — the last line has yesterday's counts. Compute the delta. Append today's stats as a new JSON line:
`{"date":"YYYY-MM-DD","total":N,"observation":N,"task":N,"reference":N,"idea":N,"person_note":N}`
Use Bash to append (>>). Do not overwrite.

4c. Read `~/.jarvis/logs/token-usage.jsonl` for token metrics. This is the single daily token report — it covers all usage since the last digest. Each line is JSON with `ts`, `source`, and token fields: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, and optionally `turns`. Group by source (heartbeat, transcripts, dreaming, user). For each source, sum all token fields and count entries. Compute `total_input` = `input_tokens` + `cache_creation_input_tokens` + `cache_read_input_tokens`. Also compute a grand total across all sources. If the file is empty or missing, omit the token usage section. After reading, truncate the file (empty it) so the next digest starts fresh.

5. Send ONE Telegram message formatted like:

```
Good morning. Here's your day:

📅 Today — [Weekday, Month Day]
• [time] — [event] ([location if relevant])
• ...
(or "Nothing on the calendar today.")

📬 Inbox
• [Sender]: [subject] — [one-line summary if clear]
• ...
(or "Inbox clear.")

🤖 Session
• Model: [model]
• Context: [used_percentage]% used
• Cost: $[total_cost_usd]
• 5-hour limit: [used_percentage]% used, resets [time]
• 7-day limit: [used_percentage]% used, resets [time]
(omit this section if /tmp/jarvis-status.json doesn't exist)

🧠 Open Brain
• [total] thoughts ([+N] since yesterday)
• Types: [observation] obs, [task] tasks, [reference] ref, [idea] ideas, [person_note] people
(omit delta if no previous stats)

📊 Token usage (last 24h)
• Total: [grand_total_input] in / [grand_total_output] out
• Heartbeat: [total_input] in / [output] out — [N] runs
• Transcripts: [total_input] in / [output] out — [N] runs
• Dreaming: [total_input] in / [output] out — [N] runs
• User: [total_input] in / [output] out — [N] runs
(omit sources with 0 runs; omit section if token-usage.jsonl is empty or missing)
```

Keep it short. No fluff. If nothing notable, still send the calendar section — skip inbox section if empty.

6. After sending, capture the digest to Open Brain using capture_thought so the main session has context. Format: "Daily digest [YYYY-MM-DD]: [paste full digest text]"

7. Also write the exact same digest text to ~/.jarvis/logs/last-digest.md (overwrite each time). The main session reads this file to have context when you want to discuss the digest.
