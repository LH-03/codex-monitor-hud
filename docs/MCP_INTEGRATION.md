# MCP integration

> [简体中文](#简体中文) · Optional local control surface

Codex Monitor HUD bundles a local STDIO MCP server in `src/mcp-server.mjs`. The HUD itself does not require MCP; install the plugin only when a user wants Codex to operate the HUD or send opt-in, task-targeted notices.

## Protocol contract

- Preferred revision: `2025-11-25`.
- Compatible revisions: `2025-06-18`, `2025-03-26`, and `2024-11-05`.
- Initialization negotiates the requested supported revision; an unknown revision falls back to the newest supported revision.
- The server advertises concise instructions, tool titles/descriptions, annotations, output schemas, structured results, explicit `isError` tool failures, and `taskSupport: forbidden` because HUD operations are immediate local actions.
- `notifications/initialized` and cancellation notifications produce no response.

This follows the current [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) and [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) contracts. Codex's MCP configuration behavior is documented in the [OpenAI Codex MCP guide](https://developers.openai.com/codex/mcp).

## Tools

| Tool | Purpose |
| --- | --- |
| `monitor_hud_status` | Read HUD health, source filters, and privacy-safe active task source metadata. |
| `monitor_hud_open_settings` | Open Settings. |
| `monitor_hud_show` | Show or restart the HUD. |
| `monitor_hud_hide` | Hide the HUD without deleting settings. |
| `monitor_hud_pause` | Toggle live-update pause. |
| `monitor_hud_disable_click_through` | Recover a click-through HUD. |
| `monitor_hud_notification_capabilities` | Read notice permission and source-aware visible task numbers. |
| `monitor_hud_notify` | Send one bounded, visibly CODEX-labeled notice to one matching task surface. |

Before notifying, call `monitor_hud_notification_capabilities` and match `task_number`, `client`, `provider`, and `profile` to the current task. Do not guess when two tasks are ambiguous. A notice never completes, pauses, or changes the monitored task.

## Profile installation

The installed plugin is registered in the personal `local` marketplace. Install it in the normal profile:

```powershell
codex plugin add codex-monitor-hud@local --json
```

Install it separately in an isolated DeepSeek profile only when that profile is actually used:

```powershell
$previousCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = Join-Path $HOME '.codex-deepseek'
    codex plugin add codex-monitor-hud@local --json
}
finally {
    $env:CODEX_HOME = $previousCodexHome
}
```

The plugin already bundles `.mcp.json`; do not create a duplicate direct MCP entry. Start a new Codex task after installing or updating the plugin because an already-open task may not hot-load new MCP tools.

## Privacy boundary

The MCP server reads only HUD configuration, heartbeat, manual-exit state, and the privacy-safe task registry under `%LOCALAPPDATA%\CodexMonitorHUD`. Registry v2 contains a task number, workspace leaf, coarse status, update time, and bounded `client`/`provider`/`profile` labels. It contains no title, prompt, reply, tool output, transcript, credential, API key, or provider configuration. Commands and notice payloads are bounded local JSON files; model-supplied executable code is never accepted.

## 简体中文

Codex Monitor HUD 在 `src/mcp-server.mjs` 中附带一个本地 STDIO MCP Server。HUD 的基础监控不依赖 MCP；只有用户希望 Codex 操控 HUD，或发送已授权、按任务定位的提示时，才需要安装插件。

### 协议与能力

- 首选 MCP `2025-11-25`，并兼容 `2025-06-18`、`2025-03-26` 和 `2024-11-05`。
- 初始化会协商受支持的版本；未知版本回退到当前最新的受支持版本。
- 工具带有标题、说明、注解、输出 Schema、结构化结果和明确的 `isError` 错误。
- HUD 操作是立即完成的本地动作，因此声明 `taskSupport: forbidden`。

八个工具分别用于查看状态、打开设置、显示、隐藏、暂停、关闭鼠标穿透、查询通知权限和向指定任务发送通知。通知前必须先查询权限，并用任务编号、客户端、Provider 与 Profile 对齐当前任务；有歧义时不能猜。通知不会改变任务状态，也不会伪造完成。

### 双 Profile 接入

普通 Codex Profile 与 `~/.codex-deepseek` 是两套独立插件状态，安装命令见上方 **Profile installation**。插件已经包含 `.mcp.json`，不要再重复添加同名 MCP。安装或更新后请新开一个 Codex 任务，让新任务重新发现工具。

### 隐私边界

MCP Server 只读取 `%LOCALAPPDATA%\CodexMonitorHUD` 下的 HUD 配置、心跳、手动退出状态和隐私安全任务注册表。注册表不包含对话标题、提示词、回复、工具输出、完整转录、凭据、API Key 或 Provider 配置；它也不会读取或修改 Codex 会话文件。
