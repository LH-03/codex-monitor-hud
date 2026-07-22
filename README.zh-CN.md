# Codex Monitor HUD

> [English](README.md) · 简体中文

## 让 Codex 安装

只需把本仓库链接加“帮我安装”交给 Codex。安装代理必须遵循精简、确定性的 [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md) 和 `install-manifest.json`，不得读取对话正文，也不得自行猜测安装命令。

> macOS 当前状态：未签名 Avalonia v3 候选版仅面向 Apple 芯片（`arm64`），并已通过原生 GitHub Actions 的构建、架构、合成宿主及安装事务门禁，但真实 Mac 交互验证仍不完整。macOS 可能要求用户 Control 点按应用选择“打开”，或在“系统设置 → 隐私与安全性”中手动同意；安装器不会清除 quarantine 或削弱 Gatekeeper。

Codex Monitor HUD 是面向 Windows 和 macOS 版 Codex Desktop 的桌面监控浮层。它只读取近期本地 Codex 会话记录中受限的一部分数据，并将当前状态显示为汇总 HUD、可展开任务列表或独立任务气泡。

它的定位是实时监控，不是历史分析平台、账单工具或对话数据库。

## 显示内容

- 活跃、监听、空闲、暂停、读取错误、已完成和已中止状态；
- 缓存输入、未缓存输入、输出、推理输出、本次合计、任务累计和上下文占用；
- 本地 Codex 记录中最近一次出现的周额度观测值；
- 稳定任务编号和两行任务标识；
- 可选的公开 API 等价成本估算，并明确标注为估算。

每个任务列表项都有项目/工作区主标题和副标题行。默认“悬停”模式始终显示时间，鼠标经过时展开官方 Codex 对话标题；“始终显示”会一直保留对话标题；“隐藏”只保留项目和时间。标题来自 Codex 本地 `session_index.jsonl`，不会从提示词或回复正文中提取。

## 显示模式

| 模式 | 行为 |
| --- | --- |
| 汇总 | 一个紧凑的聚合 HUD，不创建逐任务窗口。 |
| 列表 | 在主 HUD 内显示稳定编号的任务行；支持行、卡片、轨道三种样式，以及简洁、标准、详细三档信息密度。 |
| 分屏 | 最多 12 个独立且可调整大小的任务气泡，共用同一份会话状态。 |

任务发现最多检查 64 个近期会话文件。重新打开的旧对话即使仍位于原创建日期目录，也会按最近写入时间重新发现。内部/子代理会话和超过保留时间的终态任务不会进入用户可见列表。

![使用合成数据渲染的任务列表](assets/hud-multitask.png)

## 可选行为

以下能力默认关闭，应由用户主动开启：

- 双击任务行或气泡，通过校验后的 `codex://threads/<id>` 深链打开对应任务；
- 长时间安静后收缩为一个总状态灯，或带编号的横向/纵向任务灯；
- 完成、中止/错误、自然安静和上下文阈值提醒；
- 面向指定任务的 Codex 主动通知，可选择仅文字或受限动态权限；
- 鼠标穿透，并保留托盘菜单和设置快捷方式作为恢复入口；
- API 等价成本估算和本地主题导入。

HUD 不会从自然语言猜测任务是否完成。只有明确生命周期事件才会显示“已完成”或“已中止”；普通活动超时只会变为空闲。

## Codex Micro 颜色参考

可选的 `codexMicro` 方案使用从 OpenAI 公开 Codex Micro 页面取样的五个展示参考值。它不是 OpenAI 官方 HUD 调色板，不代表 OpenAI 认可本项目，也未校准为复现网页或硬件灯光。显示器、色彩管理、辅助功能和主题差异都可能改变可见结果。来源、数值、映射和限制见 [COLOR_ATTRIBUTION.md](COLOR_ATTRIBUTION.md)。

## 运行时与性能边界

未发布的 `3.0.0` 源码线保留已验证 Windows 2.2 WPF 行为，并增加独立 Avalonia macOS 宿主。跨平台的解析、受限发现、JSONL 增量读取、状态机、配置、价格和展示规则位于 `CodexMonitorHud.Core`。Windows 继续使用 WPF/Windows Forms/Win32 外壳和按需 PowerShell 设置兼容进程；macOS 的生命周期、菜单、窗口、通知和深链适配只放在 Mac 宿主内。

普通文件变化只轮询受影响路径；只有目录结构变化、watcher 溢出或定期校准才重新发现。没有变化的生命周期 tick 不再逐个查询全部会话文件；首轮尾读和新增记录都有限额，列表结构不变时原位更新 WPF 控件。

## 隐私

所有处理均在本机完成。HUD：

- 只读取显示所需的顶层用量、模型、生命周期、工作区末级名称、会话 ID 和本地官方标题；
- 不保存提示词、助手回复、工具输出、原始对话或凭据；
- 不修改 Codex 会话文件；
- 不发起网络请求，也没有遥测；
- MCP 任务注册表只包含任务编号、工作区末级名称、粗粒度状态和更新时间。

详见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

## 运行要求

- Windows 10/11；HUD 应用本身的最低目标为 macOS 13；
- OpenAI 当前说明中，整合 Codex 的新版 ChatGPT 桌面应用要求 macOS 14；
- 能提供本地会话记录的 Codex Desktop；
- 安装版自带私有 .NET 运行时，不要求系统全局安装 .NET；
- Windows PowerShell 5.1 或更高版本，用于完全兼容的设置宿主和紧急旧版回退；
- Codex 插件宿主可以使用 Node.js。

## 平台状态

- **Windows x64：**稳定实现；v3 候选版保留已验证的 Windows 2.2 行为。
- **macOS arm64：**Apple 芯片预览目标；原生 Actions 已通过，正在征集真实设备验证。
- **其他操作系统和处理器架构：**当前发布线不支持。

GitHub Actions 能证明原生构建和合成行为，不能证明 Gatekeeper 提示、视觉效果、菜单栏恢复、通知、多显示器、Spaces、睡眠唤醒、真实 Codex 集成或长期资源表现。欢迎提交经过隐私清理的测试报告、缺陷和拉取请求。

- [下载 macOS 预览版](https://github.com/LH-03/codex-monitor-hud/releases/tag/v3.0.0-macos-preview.1)
- [阅读 macOS 测试指南](docs/MACOS_PREVIEW_TESTING.md)
- [报告 macOS 测试结果](https://github.com/LH-03/codex-monitor-hud/issues/5)

## 手动安装

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -DefaultLanguage zh-CN
```

Windows 首次安装可使用上面的 PowerShell 命令；macOS 使用 `sh scripts/install-macos.sh`，应用位于 `~/Applications`、插件位于 `~/plugins`、设置保留在 `~/Library/Application Support/CodexMonitorHUD`。两端都先验证再切换并保留回滚材料；不会开启登录启动。

## 日常操作

- 点击任务数量可以展开或收起列表。
- 可拆出单个任务，或从 HUD/托盘菜单选择“全部分屏”。
- 拖动主 HUD 可以保存自定义位置。
- 双击主 HUD 打开设置。
- 开启鼠标穿透后，可从托盘图标关闭穿透。
- 清理某一行或气泡只影响当前 HUD 视图；同一对话开始下一轮后会重新出现。

设置保存在 `%LOCALAPPDATA%\CodexMonitorHUD\settings.json`，不会被打包进插件。

## Token 口径

```text
未缓存输入 = 输入 Token - 缓存输入 Token
本次合计   = 输入 Token + 输出 Token
```

推理输出属于输出细项，不会再次加入本次合计。周额度是最近一次本地观测值，不是账号 API 实时查询。成本估算使用本地价格数据，不代表订阅账单、实际扣款或精确 credits 换算。

## 开发与验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-dotnet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -HostMode compiled -Mode list -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -HostMode compiled -Mode split -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-runtime-performance.ps1 -TaskCount 12 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

测试使用合成会话和隔离状态目录。另见[架构说明](docs/ARCHITECTURE.md)、[项目状态](docs/PROJECT_STATUS.md)、[测试结果](TEST_RESULTS.md)和[贡献指南](CONTRIBUTING.md)。

## 项目状态与声明

当前未发布源码候选版为 `3.0.0`。Windows x64 继续使用已经验证的 2.2 WPF 实现；Avalonia macOS arm64 宿主已具备汇总/列表/分屏/安静模式、设置、菜单、通知、深链和生命周期代码，并通过本地合成测试、Windows 交叉发布及 Apple 芯片原生 Actions。真实 Mac 交互结果仍明确标为未验证。项目是独立的非官方开源项目，与 OpenAI 没有隶属或背书关系。

MIT License。
