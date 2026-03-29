# HEARTBEAT.md — example snippets

Copy useful lines into your workspace **`HEARTBEAT.md`** (non-comment, non-empty lines are sent to the agent on each heartbeat tick when heartbeat is enabled).

Heartbeats run as **system** tasks: have the model use tools to **notify** you (e.g. `send_notification`, `message` to Telegram) when something needs attention.

## Marketing / social

```text
Check memory for "campaign_brief". If it exists, use web_search for the product name plus "news" this week; write a 3-bullet summary to memory/MEMORY.md under today's heading and send_notification titled "Campaign pulse" with the bullets.
```

## Lead / inbox triage

```text
Use channel_sessions. If there is an active telegram or slack session, use sessions_history with a small limit to see the latest user messages; if any message contains "urgent" or "ASAP", send_notification with the snippet and channel.
```

## Daily health / habits (mobile)

```text
Call get_health_data for steps for the last 1 day. If steps are below 3000, send_notification suggesting a short walk (no medical claims).
```

## External systems (with HTTP webhook)

Schedule row or automation that **POSTs** to `/v1/tasks` is often better for precise timing; use HEARTBEAT for **periodic light scans** only.
