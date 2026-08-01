# hermes_plugin

Hermes Plugin — Android automation bridge for [Hermes AI Agent](https://github.com/Jasim2026/hermes-agent).

## What it does

This app acts as a bridge between Hermes (running in Termux) and Android's system capabilities:

- **Screenshots** via Shizuku (shell `screencap`)
- **Screen control** via AccessibilityService (tap, swipe, scroll, type)
- **System buttons** (back, home, recent apps)
- **Volume & mode** (silent/vibrate/sound)
- **App launching** by package name
- **Screen content** reading via accessibility tree

## Architecture

```
┌─────────────┐     WebSocket      ┌──────────────────┐
│   Hermes    │ ◄───────────────► │  Hermes Plugin   │
│  (Termux)   │   ws://127.0.0.1:8765  │  (Flutter App) │
└─────────────┘                     └───────┬──────────┘
                                            │
                              ┌─────────────┼─────────────┐
                              │             │             │
                        ┌─────▼─────┐ ┌─────▼─────┐ ┌────▼────┐
                        │AccService │ │  Shizuku  │ │ Android │
                        │(tap,scroll│ │(screenshot│ │ (shell) │
                        │ read tree)│ │  shell)   │ │         │
                        └───────────┘ └───────────┘ └─────────┘
```

**Why WebSocket?**
- Bidirectional: Hermes sends commands, plugin sends responses
- No permission needed for localhost
- Low latency (~1ms)
- Can stream screenshot data back
- Language-agnostic (Hermes is Python)

## Commands

| Command | Description | Requires |
|---------|-------------|----------|
| `screenshot` | Capture screen as PNG | Shizuku |
| `tap` | Tap at (x, y) | Accessibility |
| `long_press` | Long press at (x, y) | Accessibility |
| `swipe` | Swipe from (x1,y1) to (x2,y2) | Accessibility |
| `scroll` | Scroll in direction | Accessibility |
| `type_text` | Input text into focused field | Accessibility |
| `press_back` | Press back button | Accessibility |
| `press_home` | Press home button | Accessibility |
| `press_recent` | Press recent apps | Accessibility |
| `volume_up` | Increase volume | Shizuku |
| `volume_down` | Decrease volume | Shizuku |
| `set_volume` | Set volume level | Shizuku |
| `set_mode` | Set silent/vibrate/normal | Shizuku |
| `screen_on` | Turn screen on | Shizuku |
| `screen_off` | Turn screen off | Shizuku |
| `open_app` | Open app by package name | Accessibility |
| `get_screen_content` | Read accessibility tree | Accessibility |
| `find_element` | Find UI element by text | Accessibility |
| `click_element` | Click element by node ID | Accessibility |

## Command Format (JSON)

```json
// Request
{
  "id": "uuid-1234",
  "command": "tap",
  "params": {"x": 540, "y": 1200}
}

// Response
{
  "id": "uuid-1234",
  "success": true,
  "data": {"tapped": true, "x": 540, "y": 1200}
}
```

## Requirements

- Android 7.0+ (API 24)
- Shizuku installed and running (for screenshots/volume)
- Accessibility service enabled (for screen control)

## Setup

1. Install [Shizuku](https://github.com/RikkaApps/Shizuku) from Play Store
2. Install Hermes Plugin APK
3. Enable Hermes Plugin in Accessibility Settings
4. Grant Shizuku permission to Hermes Plugin
5. Start Shizuku (via wireless debugging or root)

## Build

This project uses GitHub Actions for CI/CD. Push to `main` or create a tag to trigger builds.

APKs are available as build artifacts.

## License

MIT
