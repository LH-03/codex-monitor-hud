# Install Codex Monitor HUD with Codex

This file is written for people who do not want to install a Codex plugin manually.

## 中文：复制给 Codex

先复制当前 GitHub 仓库的链接，然后把链接放进下面提示词的指定位置，整段发送给 Codex：

```text
请自动安装并配置以下 GitHub 仓库中的 Codex Monitor HUD：

仓库地址：<粘贴 GitHub 仓库链接>

安装要求：
1. 先读取仓库的 README.zh-CN.md、INSTALL_WITH_CODEX.md 和 PRIVACY.md。
2. 只从这个公开仓库下载项目，不登录 GitHub，不使用我的 GitHub 凭据。
3. 在独立临时目录检查插件结构和脚本；不要直接修改 Codex 应用本体。
4. Windows 下运行 scripts/install.ps1，把插件安装到个人插件目录并登记个人插件市场。
5. 不创建 Windows 登录自启动；悬浮条应由插件的本地 MCP 生命周期启动。
6. 运行 scripts/test.ps1，验证 PowerShell、XAML、JSON、MCP 和本机 Codex 日志读取。
7. 打开设置窗口，确认悬浮条不是空白，并验证桌面和开始菜单设置快捷方式可用；告诉我如何切换预设、语言、状态颜色和显示字段。
8. 不删除、修改或上传我的 Codex 日志、SQLite 数据库、配置、提示词、会话内容或 Token 明细。
9. 如果 Codex 需要重启或新建任务才能发现插件，请明确说明。
10. 最后告诉我安装目录、验证结果、如何卸载和如何恢复默认设置。
11. 这是 v2 全新插件身份。如果发现 `codex-token-strip`，请停止并提示我先卸载旧插件；不要迁移、复制或删除旧设置。
12. 首次安装只启用默认的基础实时监控。不要替我开启 Codex 主动通知、动态动效编排、成本估算、鼠标穿透或导入第三方主题；安装完成后再单独介绍这些可选 DIY 功能，由我决定是否启用。
```

## English: paste into Codex

```text
Install and configure Codex Monitor HUD from this GitHub repository:

Repository: <PASTE THE GITHUB REPOSITORY URL>

Read README.md, INSTALL_WITH_CODEX.md and PRIVACY.md first. Inspect the plugin in a
separate temporary folder, then run scripts/install.ps1 on Windows. Register it in the
personal plugin marketplace and run scripts/test.ps1. Do not modify the Codex application,
enable Windows login startup, log into GitHub, or upload/delete/modify my Codex logs,
databases, prompts, settings, conversations or token records. Open the settings window,
verify that the HUD contains visible text, and report the install path, test results,
restart/new-task requirement, uninstall steps and reset steps.
This is a fresh v2 identity. If `codex-token-strip` is present, stop and tell me to uninstall
the legacy plugin first; do not migrate, copy, or delete legacy settings.
Keep first installation on the safe basic-monitoring defaults. Do not enable proactive
Codex notices, expressive choreography, cost estimates, click-through, or third-party
themes for me. After installation, briefly explain those optional DIY features and let me
decide whether to use them.
```

## What a normal result looks like

- Plugin directory: `%USERPROFILE%\plugins\codex-monitor-hud`
- Settings directory: `%LOCALAPPDATA%\CodexMonitorHUD`
- Personal marketplace: `%USERPROFILE%\.agents\plugins\marketplace.json`
- No Windows Startup shortcut.
- Desktop and Start menu shortcuts open settings on demand.
- The HUD appears after Codex initializes the plugin in an active task.
- Proactive Codex notices, expressive animation control, API-equivalent cost, click-through, and imported themes remain optional. A normal first install does not enable them.

## Optional features to mention after installation / 安装后再介绍的可选玩法

- **Codex proactive notices / Codex 主动通知** — an opt-in, visibly CODEX-labeled mid-task cue. Text-only permission uses the configured style; expressive permission lets Codex compose bounded glow, pulse, breathe, and flow layers. It never runs animation code supplied by the model.
- **Theme Workshop / 主题工坊** — install shareable declarative themes by drag-and-drop; use the bundled theme Skill if the user wants AI to create one.
- **API-equivalent cost estimate / API 等价成本估算** — optional local estimate, not a bill or exact subscription credit accounting.
- **Advanced interaction / 高级交互** — multi-task split bubbles, layered transparency, reminder tuning, and mouse click-through with tray recovery.

Codex should describe these after the basic installation succeeds, not silently turn them on.

If any installer asks to upload your session logs or database, stop. This project does not require that.
