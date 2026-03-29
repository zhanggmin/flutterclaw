# Cron playbooks

Scheduled jobs (`cron_create` tool or gateway `cron.create`) run with session keys like `cron:<jobId>`. The runtime prompts the model to **deliver results** via `message` (if a channel session exists) and `send_notification`.

## Examples (task text you pass to `cron_create`)

### Weekly competitor URL check

```text
Fetch https://example.com/pricing with web_fetch (or http_request). If the page mentions a price change, send_notification title "Pricing changed" with one-sentence summary and session_key from this cron session.
```

### Morning digest to Telegram

```text
Use channel_sessions. If telegram session exists, use web_search for "your industry" regulatory news 24h, summarize in 5 lines, message tool to that chat_id with the summary. Always send_notification with the same text.
```

### Android: open app stats reminder

```text
On Android only: use ui_launch_intent with uri to open the relevant app settings (package details). Then ui_screenshot; describe whether updates are available in send_notification. If UI automation is unavailable, skip with a short notification.
```

## Tips

- Keep tasks **one screenful** of instructions; split complex flows into multiple jobs or a HEARTBEAT checklist.
- Prefer **`webhook`** (`POST /v1/tasks`) when an **external** system already knows the event (form submit, payment, CRM trigger); use **cron** for **clock-based** checks.
