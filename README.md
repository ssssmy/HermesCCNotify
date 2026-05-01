<h1 align="center">
  <img src="https://raw.githubusercontent.com/ssssmy/CodeNotify/main/assets/icon.svg" width="48" height="48" alt="CodeNotify" valign="middle">
  CodeNotify
</h1>

<p align="center">
  <b>Claude Code 任务完成时，实时推送通知到你手里</b><br>
  macOS · Webhook · Telegram · Discord · Slack
</p>

<p align="center">
  <a href="#这是什么">这是什么</a> ·
  <a href="#工作原理">工作原理</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#用法详解">用法详解</a> ·
  <a href="#配置">配置</a> ·
  <a href="#hermes-集成">Hermes 集成</a>
</p>

---

## 这是什么

你让 Claude Code 去重构一个模块，切到别的窗口，然后就忘了。几分钟后你想："它搞完了没？"

**CodeNotify** 解决的就是这个。它挂载到 Claude Code 的原生事件系统上，任务完成的瞬间推送通知——到你的 Mac、手机、或团队 Slack。

不轮询。不用切窗口。只有一个轻量级的 shell 脚本。

## 工作原理

```
你在 Claude Code 里输入任务
        │
        ▼
Claude Code 开始干活...
        │
        ▼
任务完成 → Stop 钩子触发
        │
        ▼
bridge.sh 从 stdin 接收事件 JSON
        │
        ├──→ macOS 系统通知（始终开启，即时弹出）
        ├──→ Webhook POST（可选，任意 HTTP 端点）
        └──→ 事件文件 → Hermes 定时任务 → Telegram/Discord/Slack
```

### 钩子系统

Claude Code（v2.x+）内置了 **hooks** 系统——在特定生命周期事件触发时执行 shell 命令。CodeNotify 在 `Stop` 事件上注册钩子，Claude 每完成一轮回复就会触发。

钩子调用 `bridge.sh`，把完整的事件载荷通过 stdin 传给它：

```json
{
  "hook_event_name": "Stop",
  "session_id": "abc123...",
  "cwd": "/Users/you/project",
  "model": "claude-sonnet-4-6",
  "stop_reason": "end_turn",
  "last_user_message": "重构认证模块",
  "last_assistant_message": "完成！已将 JWT 逻辑提取到独立模块...",
  "usage": { "input_tokens": 15420, "output_tokens": 3847 }
}
```

`bridge.sh` 解析这段数据，提取关键信息，然后通过所有已配置的通道投递通知——全程在 2 秒内完成，远低于 Claude Code 的 5 秒 hook 超时限制。

## 快速开始

### 环境要求

- **Claude Code** v2.x+（`npm install -g @anthropic-ai/claude-code`）
- **macOS**（用于系统通知）或任意 Unix（可只用 webhook）
- **Python 3**（通常系统自带）

### 安装

```bash
# 克隆仓库
git clone https://github.com/ssssmy/CodeNotify.git
cd CodeNotify

# 全局安装（所有 Claude Code 项目生效）
./install.sh --global

# 或者只安装到单个项目
./install.sh --project /path/to/your/project
```

搞定。下次 Claude Code 完成任务，你就会收到 macOS 通知。

### 配置 Webhook（Slack/Discord 等）

```bash
./install.sh --global --webhook "https://hooks.slack.com/services/..."
```

### 卸载

```bash
./uninstall.sh --global
```

## 通知效果

### macOS 通知

```
┌─────────────────────────────────────┐
│ Claude Code · my-project            │
│ claude-sonnet-4-6                   │
│─────────────────────────────────────│
│ 完成！已将 JWT 逻辑提取到独立模块，  │
│ 支持 refresh token 轮换。           │
└─────────────────────────────────────┘
```

### 聊天消息（通过 Hermes 推送到 Telegram/Discord/Slack）

```
━━━━━━━━━━━━━━━━━━━━━━━
🤖 Claude Code · sterminal
Model: claude-sonnet-4-6  |  Status: end_turn
Tokens: 15420→3847
━━━━━━━━━━━━━━━━━━━━━━━
▶ 重构认证模块改用 JWT
───
完成！已将 JWT 逻辑提取到独立模块，
支持 refresh token 轮换。所有测试通过。
```

## 用法详解

### 命令参考

| 命令 | 说明 |
|---------|-------------|
| `install.sh --global` | 全局安装（所有项目生效） |
| `install.sh --project DIR` | 安装到指定项目目录 |
| `install.sh --webhook URL` | 安装时同时设置 webhook 地址 |
| `install.sh --force` | 强制重装（覆盖已有钩子） |
| `install.sh --dry-run` | 预览将要执行的操作 |
| `uninstall.sh` | 从当前目录卸载 |
| `uninstall.sh --global` | 从全局配置卸载 |
| `uninstall.sh --project DIR` | 从指定项目卸载 |

### 安装模式说明

**`--global`** — 将钩子写入 `~/.claude/settings.json`。此后在任何项目里启动的 Claude Code 会话都会触发通知。推荐大多数用户使用。

```bash
./install.sh --global
```

**`--project DIR`** — 将钩子写入 `DIR/.claude/settings.json`。只有在该项目目录下启动的会话才会触发通知。适合聚焦式工作流。

```bash
./install.sh --project ~/work/main-project
```

**`--webhook URL`** — 设置 webhook 地址，直接 HTTP 投递。接收端会拿到完整事件数据的 JSON。兼容 Slack、Discord、飞书、企业微信、Zapier、n8n 等。

```bash
./install.sh --global --webhook "https://hooks.slack.com/services/T00/B00/xxxx"
```

Webhook 接收到的 JSON 格式：
```json
{
  "session_id": "abc123...",
  "project": "my-project",
  "cwd": "/Users/you/my-project",
  "model": "claude-sonnet-4-6",
  "stop_reason": "end_turn",
  "last_user_message": "重构认证模块",
  "last_assistant_message": "完成！已将 JWT 逻辑...",
  "total_tokens": "15420→3847",
  "timestamp": "2026-05-01T06:08:12Z",
  "transcript_path": "/Users/you/.claude/projects/.../session.jsonl"
}
```

## 配置

所有配置在 `~/.code-notify/config`：

```
WEBHOOK_URL=https://your-webhook-url
```

可直接编辑此文件，或用 `--webhook` 参数在安装时设置。

### 日志

桥接脚本的运行日志在 `~/.code-notify/bridge.log`：

```bash
# 实时查看
tail -f ~/.code-notify/bridge.log

# 查看最近活动
tail -20 ~/.code-notify/bridge.log
```

### 事件文件

等待 Hermes 定时任务投递的事件暂存在 `~/.code-notify/events/`。文件命名格式：`<unix时间戳>-<session_id>.json`。

## Hermes 集成

CodeNotify 可独立运行，但与 **Hermes Agent** 结合后体验最佳——将通知推送到你的即时通讯平台。

### 配置

安装 CodeNotify 后，在 Hermes 中加载 `claude-code-notify` 技能，然后说：

> **"setup claude code notify cron"**

Hermes 会创建一个定时任务：
1. 每分钟轮询 `~/.code-notify/events/`
2. 读取新的完成事件
3. 发送格式化消息到已连接的消息通道
4. 清理已处理的文件

### 支持的消息通道

通过 Hermes 的 `send_message` 工具：
- Telegram（频道、群组、私聊）
- Discord（频道、讨论串）
- Slack（频道）

### 自定义投递目标

> **"send claude code notify to telegram:#my-channel"**

Hermes 会更新定时任务，投递到你指定的通道。

## 对比 CodeIsland

| 特性 | CodeNotify | CodeIsland |
|---------|-----------|------------|
| macOS 系统通知 | ✅ | ✅ |
| 推送到聊天应用 | ✅（通过 Hermes） | ❌ |
| Webhook 投递 | ✅ | ❌ |
| macOS 灵动岛面板 | ❌ | ✅ |
| 权限审批 UI | ❌ | ✅ |
| 支持 AI 工具数 | 1（Claude Code） | 22 |
| 安装体积 | ~5 KB shell 脚本 | ~15 MB Swift 应用 |
| 跨平台 | ✅（Unix） | ❌（仅 macOS） |
| 开源协议 | ✅ MIT | ✅ MIT |

CodeNotify 刻意保持极简。它只做一件事——任务完成时通知你——零依赖（bash + curl + python3）。如果你需要带权限管理、灵动岛面板的丰富 macOS 原生体验，用 [CodeIsland](https://github.com/wxtsky/CodeIsland)。

## 文件结构

```
CodeNotify/
  README.md              本文档
  LICENSE                MIT 协议
  bridge.sh              钩子处理脚本（由 Claude Code 调用）
  install.sh             安装脚本（向 Claude 配置注入 Stop 钩子）
  uninstall.sh           卸载脚本（移除钩子）

~/.code-notify/          （运行时创建）
  events/                待投递的事件文件
  config                 用户配置（webhook 地址等）
  bridge.log             运行日志
```

## 故障排查

### "收不到通知"

1. **检查钩子是否安装成功：**
   ```bash
   cat ~/.claude/settings.json | python3 -m json.tool | grep -A5 bridge.sh
   ```
   输出中应该能看到 `code-notify-v1`。

2. **查看桥接日志：**
   ```bash
   tail -20 ~/.code-notify/bridge.log
   ```
   找 `ERROR` 条目。如果日志为空，说明钩子没被触发。

3. **手动测试桥接脚本：**
   ```bash
   echo '{"hook_event_name":"Stop","session_id":"test-123","cwd":"/tmp/test","model":"claude-sonnet","stop_reason":"end_turn","last_user_message":"你好","last_assistant_message":"你好！任务完成。","usage":{"input_tokens":100,"output_tokens":50}}' | bash ./bridge.sh
   ```
   应该立刻弹出一条 macOS 通知。

4. **Claude Code 版本：** 钩子系统需要 Claude Code v2.x+。用 `claude --version` 检查。

### "macOS 通知没弹"

- 检查「系统设置 → 通知」中是否禁用了终端（Terminal.app 或你用的终端模拟器）的通知权限。
- `osascript` 命令在所有 macOS 上都自带，一般不会有问题。

### "Webhook 收不到"

- 先用 `curl -X POST <url> -d '{"test":true}'` 验证 webhook 地址是否可达。
- 查看 `~/.code-notify/bridge.log` 里的连接错误。
- Webhook 投递是 fire-and-forget 模式，超时 10 秒。

## 贡献

欢迎提交 Bug 报告和 Pull Request。提交 PR 前请：

1. 手动测试桥接脚本（见故障排查章节）
2. 在干净配置上测试安装 + 卸载
3. 保持零依赖原则——只用 bash + python3 + curl

## 致谢

灵感来自 [CodeIsland](https://github.com/wxtsky/CodeIsland)——优秀的 macOS 灵动岛 AI 编码代理状态面板，率先展示了 Claude Code hook 监控的威力。

## 许可证

MIT — 详见 [LICENSE](LICENSE)
