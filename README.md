<h1 align="center">
  <img src="https://raw.githubusercontent.com/ssssmy/CodeNotify/main/assets/icon.svg" width="48" height="48" alt="CodeNotify" valign="middle">
  CodeNotify
</h1>

<p align="center">
  <b>Real-time push notifications when Claude Code finishes a task</b><br>
  macOS · Webhook · Telegram · Discord · Slack
</p>

<p align="center">
  <a href="#how-it-works">How It Works</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#hermes-integration">Hermes Integration</a>
</p>

---

## What is CodeNotify?

You ask Claude Code to refactor a module, switch to another window, and forget about it. Minutes later you wonder: "Is it done yet?"

**CodeNotify** solves this. It hooks into Claude Code's native event system and pushes a notification the moment a task completes — to your Mac, your phone, or your team's Slack.

No polling. No window switching. Just a single lightweight shell script.

## How It Works

```
You type a task in Claude Code
        │
        ▼
Claude Code works on it...
        │
        ▼
Task completes → Stop hook fires
        │
        ▼
bridge.sh receives event JSON via stdin
        │
        ├──→ macOS notification (always, instant)
        ├──→ Webhook POST (optional, any HTTP endpoint)
        └──→ Event file → Hermes Cron → Telegram/Discord/Slack
```

### The Hook System

Claude Code (v2.x+) supports a **hooks** system — shell commands that fire on specific lifecycle events. CodeNotify registers a hook on the `Stop` event, which Claude triggers after every completed response.

The hook calls `bridge.sh` with the full event payload on stdin:

```json
{
  "hook_event_name": "Stop",
  "session_id": "abc123...",
  "cwd": "/Users/you/project",
  "model": "claude-sonnet-4-6",
  "stop_reason": "end_turn",
  "last_user_message": "Refactor the auth module",
  "last_assistant_message": "Done! Extracted JWT logic into...",
  "usage": { "input_tokens": 15420, "output_tokens": 3847 }
}
```

`bridge.sh` parses this, extracts the useful bits, and delivers notifications through every configured channel — all within 2 seconds, well under Claude's 5-second hook timeout.

## Quick Start

### Prerequisites

- **Claude Code** v2.x+ installed (`npm install -g @anthropic-ai/claude-code`)
- **macOS** (for native notifications) or any Unix (webhook-only mode)
- **Python 3** (usually pre-installed)

### Install

```bash
# Clone the repo
git clone https://github.com/ssssmy/CodeNotify.git
cd CodeNotify

# Install globally (all Claude Code projects)
./install.sh --global

# Or install for a single project
./install.sh --project /path/to/your/project
```

That's it. The next time Claude Code finishes a task, you'll get a macOS notification.

### With Webhook (Slack/Discord/etc.)

```bash
./install.sh --global --webhook "https://hooks.slack.com/services/..."
```

### Uninstall

```bash
./uninstall.sh --global
```

## What You'll See

### macOS Notification

```
┌─────────────────────────────────────┐
│ Claude Code · my-project            │
│ claude-sonnet-4-6                   │
│─────────────────────────────────────│
│ Done! Extracted JWT logic into a    │
│ separate module with refresh token  │
│ rotation.                           │
└─────────────────────────────────────┘
```

### Chat Message (Telegram/Discord/Slack via Hermes)

```
━━━━━━━━━━━━━━━━━━━━━━━
🤖 Claude Code · sterminal
Model: claude-sonnet-4-6  |  Status: end_turn
Tokens: 15420→3847
━━━━━━━━━━━━━━━━━━━━━━━
▶ Refactor the auth module to use JWT
───
Done! Extracted JWT logic into a separate module
with refresh token rotation. All tests passing.
```

## Usage

### CLI Reference

| Command | Description |
|---------|-------------|
| `install.sh --global` | Install for all Claude Code projects |
| `install.sh --project DIR` | Install for a specific project directory |
| `install.sh --webhook URL` | Set webhook URL during install |
| `install.sh --force` | Reinstall (overwrite existing hook) |
| `install.sh --dry-run` | Preview changes without applying |
| `uninstall.sh` | Remove from current directory |
| `uninstall.sh --global` | Remove from global config |
| `uninstall.sh --project DIR` | Remove from project config |

### Install Options Deep Dive

**`--global`** — Adds the hook to `~/.claude/settings.json`. Every Claude Code session, in any project, will trigger CodeNotify. This is the recommended setup for most users.

```bash
./install.sh --global
```

**`--project DIR`** — Adds the hook to `DIR/.claude/settings.json`. Only sessions started in that project directory will trigger notifications. Use this for focused workflows.

```bash
./install.sh --project ~/work/main-project
```

**`--webhook URL`** — Sets a webhook URL for direct HTTP delivery. The webhook receives a JSON payload with the full event data. Works with Slack, Discord, Zapier, n8n, or any HTTP endpoint.

```bash
./install.sh --global --webhook "https://hooks.slack.com/services/T00/B00/xxxx"
```

Webhook payload format:
```json
{
  "session_id": "abc123...",
  "project": "my-project",
  "cwd": "/Users/you/my-project",
  "model": "claude-sonnet-4-6",
  "stop_reason": "end_turn",
  "last_user_message": "Refactor auth module",
  "last_assistant_message": "Done! Extracted JWT logic...",
  "total_tokens": "15420→3847",
  "timestamp": "2026-05-01T06:08:12Z",
  "transcript_path": "/Users/you/.claude/projects/.../session.jsonl"
}
```

## Configuration

All configuration lives in `~/.code-notify/config`:

```
WEBHOOK_URL=https://your-webhook-url
```

Edit this file directly, or use the install script with `--webhook` to set it.

### Logs

Bridge execution logs are at `~/.code-notify/bridge.log`:

```bash
# Watch live
tail -f ~/.code-notify/bridge.log

# Check recent activity
tail -20 ~/.code-notify/bridge.log
```

### Event Files

Pending events (before Hermes cron delivers them) sit in `~/.code-notify/events/`. Each file is named `<unix_timestamp>-<session_id>.json`.

## Hermes Integration

CodeNotify is designed to work standalone, but shines brightest with **Hermes Agent** — which delivers notifications to your messaging platforms.

### Setup

After installing CodeNotify, load the `claude-code-notify` skill in Hermes and say:

> **"setup claude code notify cron"**

Hermes creates a cron job that:
1. Polls `~/.code-notify/events/` every minute
2. Reads new completion events
3. Sends formatted messages to your connected channels
4. Cleans up processed files

### Supported Channels

Via Hermes's `send_message` tool:
- Telegram (channels, groups, DMs)
- Discord (channels, threads)
- Slack (channels)

### Custom Delivery Target

> **"send claude code notify to telegram:#my-channel"**

Hermes updates the cron job to target your preferred channel.

## How It Compares

| Feature | CodeNotify | CodeIsland |
|---------|-----------|------------|
| macOS notifications | ✅ | ✅ |
| Push to chat apps | ✅ (via Hermes) | ❌ |
| Webhook delivery | ✅ | ❌ |
| macOS notch panel | ❌ | ✅ |
| Permission approval UI | ❌ | ✅ |
| 22 AI tools supported | 1 (Claude Code) | 22 |
| Install size | ~5 KB shell scripts | ~15 MB Swift app |
| Cross-platform | ✅ (Unix) | ❌ (macOS only) |
| Open source | ✅ MIT | ✅ MIT |

CodeNotify is intentionally minimal. It does one thing — notify on task completion — and does it with zero dependencies beyond bash, curl, and python3. If you want a rich macOS-native panel with permission management and multi-tool support, use [CodeIsland](https://github.com/wxtsky/CodeIsland).

## Files

```
CodeNotify/
  README.md              This file
  LICENSE                MIT
  bridge.sh              Hook handler (called by Claude Code)
  install.sh             Installer (adds Stop hook to Claude settings)
  uninstall.sh           Uninstaller (removes the hook)

~/.code-notify/          (created at runtime)
  events/                Pending notification event files
  config                 User configuration (webhook URL)
  bridge.log             Execution log
```

## Troubleshooting

### "Not getting notifications"

1. **Check the hook is installed:**
   ```bash
   cat ~/.claude/settings.json | python3 -m json.tool | grep -A5 bridge.sh
   ```
   You should see `code-notify-v1` in the output.

2. **Check the bridge log:**
   ```bash
   tail -20 ~/.code-notify/bridge.log
   ```
   Look for `ERROR` entries. If the log is empty, the hook isn't being called.

3. **Test the bridge manually:**
   ```bash
   echo '{"hook_event_name":"Stop","session_id":"test-123","cwd":"/tmp/test","model":"claude-sonnet","stop_reason":"end_turn","last_user_message":"Hello","last_assistant_message":"Hi there!","usage":{"input_tokens":100,"output_tokens":50}}' | bash ./bridge.sh
   ```
   You should see a macOS notification pop up immediately.

4. **Claude Code version:** hooks require Claude Code v2.x+. Check with `claude --version`.

### "macOS notification not showing"

- Make sure you haven't disabled notifications for Terminal.app or your terminal emulator in System Settings → Notifications.
- The `osascript` command is used — it should be available on all macOS systems.

### "Webhook not receiving"

- Verify the URL with `curl -X POST <url> -d '{"test":true}'`
- Check `~/.code-notify/bridge.log` for connection errors
- Webhook delivery is fire-and-forget with a 10-second timeout

## Contributing

Bug reports and pull requests are welcome. Before submitting a PR:

1. Test the bridge script manually (see Troubleshooting)
2. Test install + uninstall on a clean config
3. Keep the no-dependency philosophy — bash + python3 + curl only

## Credits

Inspired by [CodeIsland](https://github.com/wxtsky/CodeIsland) — the excellent macOS Dynamic Island AI coding agent status panel that pioneered Claude Code hook monitoring.

## License

MIT — see [LICENSE](LICENSE)
