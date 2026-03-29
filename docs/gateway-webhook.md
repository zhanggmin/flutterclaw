# Gateway HTTP webhook

The embedded gateway listens for **WebSocket** clients (OpenClaw protocol) and, when enabled, for **`POST /v1/tasks`** on the same host and port (default `http://127.0.0.1:18789/v1/tasks`).

## Enabling and security

- **`gateway.webhook_enabled`** (default `true` in config JSON): set to `false` to disable the HTTP route.
- **`gateway.token`**: if non-empty, each webhook request must authenticate:
  - Header: `Authorization: Bearer <same token as gateway WebSocket connect>`, or
  - Query: `?token=<token>`
- Bind address stays **`127.0.0.1`** by default — only local processes can reach the port. For automation from the internet, use a **tunnel** and **always set a strong token**.

## Request

`Content-Type: application/json`

| Field | Required | Description |
|--------|-----------|-------------|
| `message` or `text` | yes | Instructions for the agent |
| `session_key` | no | Defaults to `webhook_default_session_key` (default `webhook:default`) |
| `channel_type` | no | Defaults to `webhook` |
| `chat_id` | no | Defaults to `default` |

Example:

```bash
curl -sS -X POST 'http://127.0.0.1:18789/v1/tasks' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_GATEWAY_TOKEN' \
  -d '{"message":"Summarize today'\''s calendar and send_notification with the result."}'
```

Response **`202 Accepted`** immediately; the agent runs asynchronously:

```json
{"ok":true,"accepted":true,"session_key":"webhook:default"}
```

## Tunneling (n8n, Zapier, etc.)

1. Set **`gateway.token`** in FlutterClaw config to a long random secret.
2. Run a tunnel that forwards HTTPS to `127.0.0.1:18789` on the device (or dev machine when testing). Options include **Cloudflare Tunnel**, **ngrok**, or similar.
3. Point your automation at `https://<public-host>/v1/tasks` with the same JSON body and `Authorization: Bearer …`.

The phone must keep the app/gateway running while the tunnel is active.

## Config keys

| Key | Meaning |
|-----|---------|
| `webhook_enabled` | Boolean |
| `webhook_default_session_key` | Session used when the body omits `session_key` |

These live alongside existing `gateway` fields in the app config JSON.
