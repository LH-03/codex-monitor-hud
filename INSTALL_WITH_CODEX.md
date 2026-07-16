# Install Codex Monitor HUD with Codex

This document is for users who want Codex to inspect, test, and install the plugin rather than running the installer manually.

## 中文提示词

```text
请从下面的公开仓库安装 Codex Monitor HUD：

<粘贴仓库链接>

先阅读 README.zh-CN.md、INSTALL_WITH_CODEX.md 和 PRIVACY.md。在独立临时目录检查
插件结构，不要修改 Codex 应用本体。Windows 首次安装运行
scripts/install.ps1 -DefaultLanguage zh-CN；升级必须保留现有 settings.json。

运行 scripts/test.ps1，安装到个人插件目录并登记个人插件市场。验证 HUD 心跳、设置
快捷方式和插件版本。不要创建 Windows 登录自启动，不要上传、删除、移动或修改我的
Codex 会话、日志、数据库、提示词、回复、Token 记录或设置。

如果发现旧的 codex-token-strip，请停止并让我先处理；不要迁移或删除旧设置。首次安装
保持基础默认值，不要替我开启主动通知、动态编排、成本估算、鼠标穿透或第三方主题。
完成后报告安装目录、测试结果、是否需要重启 Codex/新建任务，以及卸载和恢复默认设置的方法。
```

## English prompt

```text
Install Codex Monitor HUD from this public repository:

<PASTE REPOSITORY URL>

Read README.md, INSTALL_WITH_CODEX.md, and PRIVACY.md first. Inspect the plugin in a
separate temporary directory and do not modify the Codex application. On a first Windows
install run scripts/install.ps1 -DefaultLanguage en; preserve an existing settings.json
on upgrade.

Run scripts/test.ps1, install the personal plugin, and verify its version, HUD heartbeat,
and settings shortcuts. Do not enable Windows login startup. Do not upload, delete, move,
or modify my Codex sessions, logs, databases, prompts, replies, token records, or settings.

If codex-token-strip is present, stop and ask me to handle it; do not migrate or remove its
settings. Keep optional notices, expressive choreography, cost estimates, click-through,
and third-party themes disabled. Report the install path, tests, restart/new-task requirement,
uninstall procedure, and reset procedure.
```

## Language selection

`-DefaultLanguage` affects only a first install:

- Simplified Chinese request: `zh-CN`;
- English request: `en`;
- other request languages: `en` until a reviewed locale exists.

The installer must not infer language from saved session content and must not replace an existing language preference. See [LOCALIZATION.md](LOCALIZATION.md) before adding a locale.

## Expected result

- Plugin: `%USERPROFILE%\plugins\codex-monitor-hud`
- Settings/state: `%LOCALAPPDATA%\CodexMonitorHUD`
- Personal marketplace: `%USERPROFILE%\.agents\plugins\marketplace.json`
- Desktop and Start-menu shortcuts open Settings on demand.
- No Windows Startup shortcut is created.
- The HUD starts through the local plugin/MCP lifecycle after Codex discovers the plugin.
- Existing settings remain unchanged during an upgrade.

Codex may need a restart or a new task before plugin tools are rediscovered.

## Optional features to explain, not enable

- proactive task-targeted Codex notices;
- bounded expressive notice motion;
- Theme Workshop and local theme packs;
- API-equivalent cost estimates;
- split bubbles, advanced transparency, quiet indicators, and mouse click-through.

If an installation workflow asks to upload local sessions, logs, or a database, stop. This plugin does not require an upload.
