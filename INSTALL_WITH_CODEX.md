# Install Codex Token HUD with Codex

This file is written for people who do not want to install a Codex plugin manually.

## 中文：复制给 Codex

先复制当前 GitHub 仓库的链接，然后把链接放进下面提示词的指定位置，整段发送给 Codex：

```text
请自动安装并配置以下 GitHub 仓库中的 Codex Token HUD：

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
```

## English: paste into Codex

```text
Install and configure Codex Token HUD from this GitHub repository:

Repository: <PASTE THE GITHUB REPOSITORY URL>

Read README.md, INSTALL_WITH_CODEX.md and PRIVACY.md first. Inspect the plugin in a
separate temporary folder, then run scripts/install.ps1 on Windows. Register it in the
personal plugin marketplace and run scripts/test.ps1. Do not modify the Codex application,
enable Windows login startup, log into GitHub, or upload/delete/modify my Codex logs,
databases, prompts, settings, conversations or token records. Open the settings window,
verify that the HUD contains visible text, and report the install path, test results,
restart/new-task requirement, uninstall steps and reset steps.
```

## What a normal result looks like

- Plugin directory: `%USERPROFILE%\plugins\codex-token-strip`
- Settings directory: `%LOCALAPPDATA%\CodexTokenHUD`
- Personal marketplace: `%USERPROFILE%\.agents\plugins\marketplace.json`
- No Windows Startup shortcut.
- Desktop and Start menu shortcuts open settings on demand.
- The HUD appears after Codex initializes the plugin in an active task.

If any installer asks to upload your session logs or database, stop. This project does not require that.
