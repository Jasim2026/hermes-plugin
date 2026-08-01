# Hermes Plugin

Flutter Android app for device automation — accessibility gestures + Shizuku root access + WebSocket bridge for Hermes agent control.

## Features

### Core
- **WebSocket Server** (`ws://127.0.0.1:8765`) — real-time command/response with Hermes agent
- **Accessibility Service** — tap, long press, swipe, scroll, type text, get screen content, find/click elements
- **Shizuku Integration** — screenshots, shell commands, volume/ringer control, device info
- **File-based Signaling** — Kotlin FileObserver watches `/sdcard/hermes_plugin/control.txt` for agent commands

### Commands (35)
| Category | Commands |
|----------|----------|
| Navigation | `press_home`, `press_back`, `press_recent` |
| Gestures | `tap`, `long_press`, `swipe`, `scroll` |
| Input | `type_text`, `clear_input_field` |
| Screen | `screen_on`, `screen_off`, `screenshot`, `screenshot_cached` |
| UI | `get_screen_content`, `find_element`, `click_element`, `ui_automator_dump` |
| Volume | `volume_up`, `volume_down`, `set_volume`, `set_mode` |
| Apps | `open_app`, `get_installed_apps`, `get_app_state` |
| Info | `get_display_info`, `get_device_info`, `get_battery_info`, `health` |
| Tier 2 | `batch`, `set_webhook`, `stream_events`, `get_input_methods` |
| Meta | `ping`, `help` |

### UI
- **Dark theme** with Inter font and purple accent
- **Permission modal** — Accessibility + Notification + Shizuku (optional)
- **Status dashboard** — WebSocket, clients, accessibility, Shizuku status pills
- **Quick actions** — 12 one-tap buttons (Home, Back, Recent, Vol+/-, Screen On/Off, Screenshot, Scroll, Clear)
- **Activity log** — monospace terminal panel with copy/clear

### Screen On/Off
- Uses accessibility service first (PowerManager wake lock / goToSleep)
- Falls back to Shizuku shell `input keyevent` only if accessibility fails
- Response includes `via` field indicating which method was used

### Error Knowledge Base
- SQLite database at `/root/hermes-mini/errors.db` (28 errors, 6 patterns)
- Search tool: `err_search.py` — keyword search across error signatures, fixes, and patterns
- Universal DB manager: `db.py` — 22 actions for any SQLite database

## Architecture

```
Hermes Agent (Telegram)
    ↓ WebSocket
Flutter App (ws://127.0.0.1:8765)
    ↓ MethodChannel
Kotlin (AccessibilityService + ShizukuServiceImpl)
    ↓
Android APIs
```

- **Flutter** — UI, WebSocket server, command routing
- **Kotlin** — Accessibility gestures, Shizuku shell, file observer, permission handling
- **ShizukuServiceImpl** — shell command allowlist, path validation, background thread execution
- **HermesAccessibilityService** — gesture dispatch, node tree traversal, screen on/off

## Build

```bash
# Local
cd /tmp/hermes-plugin
flutter build apk --debug

# CI
# GitHub Actions: .github/workflows/build.yml
# Triggers on push to main
# Builds debug APK, uploads as artifact
```

## Project Structure

```
hermes-plugin/
├── android/app/src/main/kotlin/com/hermes/plugin/
│   ├── MainActivity.kt          — Lifecycle channel, permission handling
│   ├── HermesService.kt         — Foreground service + FileObserver
│   ├── HermesAccessibilityService.kt — Gestures, node tree, screen on/off
│   └── ShizukuServiceImpl.kt    — Shell commands, volume, ringer, screenshots
├── lib/
│   ├── main.dart                — App entry, theme
│   ├── screens/home_screen.dart — Dashboard UI, permission modal
│   ├── services/
│   │   ├── service_control.dart — WS server + permission helpers
│   │   ├── command_handler.dart — 35 command handlers + help docs
│   │   ├── accessibility_bridge.dart — Dart→Kotlin accessibility API
│   │   ├── shizuku_service.dart — Dart→Kotlin Shizuku API
│   │   └── websocket_server.dart — WebSocket server
│   └── models/command.dart      — Command/Response models
├── assets/fonts/Inter-Variable.ttf
└── .github/workflows/build.yml  — CI
```

## Agent-Side Tools

| Tool | Description |
|------|-------------|
| `hermes_ctl.py` | Agent writes commands to `/sdcard/hermes_plugin/control.txt` |
| `db.py` | Universal SQLite manager (22 actions) |
| `err_search.py` | Error knowledge base search |
| `errors.db` | Error patterns + verified fixes |
| `populate_errors*.py` | DB population scripts |

## Permissions

| Permission | Required | Purpose |
|------------|----------|---------|
| Accessibility | Yes | Gestures, UI tree, screen on/off |
| Notification | Yes | Alert delivery |
| QUERY_ALL_PACKAGES | Yes | List installed apps |
| Shizuku | Optional | Shell commands, screenshots, volume |
