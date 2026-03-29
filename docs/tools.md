# Tools

Reference of all tools available to FlutterClaw agents. Categories: file system, web, memory, agent management, sessions & subagents, messaging, device, camera & media, contacts/calendar/location, health, UI automation & shortcuts, and scheduling.

---

## File System

| Tool | Description |
|------|-------------|
| `read_file` | Read file from agent workspace |
| `write_file` | Write file to agent workspace |
| `edit_file` | Edit file with find/replace |
| `list_dir` | List directory contents |
| `append_file` | Append content to file |

## Web

| Tool | Description |
|------|-------------|
| `web_search` | Search the web (DuckDuckGo, Brave, Tavily, or Perplexity) |
| `web_fetch` | Fetch URL content as text (optional headless browser for JS sites) |
| `http_request` | Custom HTTP requests (GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS) |

## Memory

| Tool | Description |
|------|-------------|
| `memory_search` | Search long-term memory |
| `memory_get` | Get full memory contents |
| `memory_write` | Write to memory (MEMORY.md + episodic logs) |

## Agent Management

| Tool | Description |
|------|-------------|
| `agent_create` | Create a new agent with name, emoji, model, vibe, system prompt |
| `agent_update` | Update agent properties |
| `agent_delete` | Archive and deactivate an agent |
| `agent_switch` | Switch to a different agent |
| `agents_list` | List all available agents |

## Sessions & Subagents

| Tool | Description |
|------|-------------|
| `session_status` | Current session info |
| `sessions_list` | List active sessions |
| `sessions_spawn` | Spawn a child subagent with a task |
| `sessions_yield` | Signal the current turn is done |
| `sessions_send` | Send a message to any session and wait for reply |
| `sessions_history` | Read transcript of any session |
| `subagents` | List, kill, or steer running subagents |

## Messaging

| Tool | Description |
|------|-------------|
| `message` | Send message to a configured channel (telegram, discord, webchat, whatsapp, slack, signal — depends on app settings) |
| `channel_sessions` | Discover active channel sessions |

## Device (mobile)

Tools that use device hardware and OS APIs (GPS, health, camera, clipboard, notifications, share).

| Tool | Description |
|------|-------------|
| `device_status` | Battery level, charging state, connectivity |
| `send_notification` | Send a local push notification |
| `schedule_reminder` | Schedule a future reminder notification |
| `cancel_reminder` | Cancel a scheduled reminder |
| `clipboard_read` | Read system clipboard |
| `clipboard_write` | Write to system clipboard |
| `share_content` | Share content via system share sheet |
| `open_external_uri` | Open allowed URIs in system apps. On **Android**, for SMS/email you can open the composer then **finish with `ui_*`** (tap Send in the device language) |
| `pick_file_to_workspace` | System file picker; copy file into workspace `inbox/` |
| `pick_image_to_workspace` | Gallery picker; save image into workspace `inbox/` |

## Camera & Media (mobile)

| Tool | Description |
|------|-------------|
| `camera_take_photo` | Take a photo (returns base64 for vision models) |
| `camera_record_video` | Record a video clip |
| `media_play` | Play audio with background and lock-screen controls |

## Contacts, Calendar & Location (mobile)

| Tool | Description |
|------|-------------|
| `contacts_search` | Search device address book |
| `calendar_list_events` | List calendar events |
| `calendar_create_event` | Create a calendar event |
| `get_location` | Get GPS coordinates with accuracy level (low/medium/high) |

## Health (mobile)

Health: HealthKit (iOS) / Health Connect (Android).

| Tool | Description |
|------|-------------|
| `get_health_data` | Read health data by type and date range: steps, heart_rate, calories, sleep_in_bed, sleep_asleep, blood_oxygen, weight |

## UI Automation & Shortcuts (mobile)

| Tool | Description |
|------|-------------|
| `ui_check_permission` | Check if automation permission is granted |
| `ui_request_permission` | Request automation permission |
| `ui_tap` | Tap at screen coordinates |
| `ui_swipe` | Swipe gesture |
| `ui_type_text` | Type text (use after ui_tap on the input field) |
| `ui_find_elements` | List visible interactive elements (text, bounds, center) — Android |
| `ui_click_element` | Find element by text/id/description and click — Android |
| `ui_screenshot` | Capture screen as PNG (base64) for vision models |
| `ui_global_action` | Back, Home, Recents, Notifications, Quick Settings — Android |
| `ui_launch_app` | Open installed app by package or label search — Android |
| `ui_launch_intent` | Fire Android intent / deep link (VIEW, settings, tel, etc.) |
| `ui_app_intents` | List exported intent filters for a package — Android |
| `ui_batch_actions` | Run taps/swipes/clicks/types/globals plus optional `launch_app`, `launch_intent`, `wait` in one go — Android |
| `run_shortcut` | Run an iOS Shortcut via deep link |
| `list_shortcuts` | List installed iOS Shortcuts |

## Scheduling

| Tool | Description |
|------|-------------|
| `cron_create` | Create a scheduled task (cron, interval, or one-shot) |
| `cron_list` | List scheduled tasks |
| `cron_update` | Update a scheduled task |
| `cron_delete` | Delete a scheduled task |

## Gateway HTTP webhook

When the embedded gateway is running, external systems can enqueue work via HTTP. See [gateway-webhook.md](gateway-webhook.md).
