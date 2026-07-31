# Codex Monitor HUD

> [English](README.md) · 仅支持 Windows x64

Codex Monitor HUD 是一个完全本地运行的 Windows 实时悬浮监控器：只展示当前活跃的 Codex Desktop 任务。它不是聊天记录库、账单工具，也不是云端服务。

## 一句话让 Codex 安装

把本仓库链接交给 Codex，再说一句：**“帮我安装。”**

仓库内的 [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md) 与 [install-manifest.json](install-manifest.json) 已写好确定性流程。合格的安装代理会识别 Windows x64、优先选择已校验的 Release、保留你的设置、完成健康检查并保留回滚副本；安装时不需要读取对话正文。

手动安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -DefaultLanguage zh-CN
```

## 显示什么

- 活跃、监听、空闲、暂停、读取错误、已完成和已中止状态。
- 缓存/未缓存输入、输出、推理输出、本次合计、任务累计、上下文占用、模型和活跃任务数。
- Codex 本地 `rate_limits` 记录中最近一次出现的账号级周额度与 5 小时额度窗口。
- 稳定任务编号、工作区标签，以及来自 `session_index.jsonl` 的本地官方对话标题。
- 可选的公开 API 标价等价成本估算；它会明确标为估算，不是订阅账单或 credits 余额。

![中文任务列表示例，包含周额度和 5 小时额度](assets/hud-multitask.png)

周额度与 5 小时额度不会被猜测、不会按任务相加，也不会向账号 API 查询。HUD 只显示最新的本地观测值；当前 Codex 版本没有写出某个窗口时，已启用的指标会显示 `--`。

## 三种显示模式

| 模式 | 用途 |
| --- | --- |
| 汇总 | 一只轻量的聚合总气泡。 |
| 列表 | 在主 HUD 中显示稳定编号的任务行；支持行、卡片、轨道三种样式。 |
| 分裂 | 将任务拆成独立、可调整大小的小气泡，最多 12 个。 |

总气泡上的任务数量按钮只负责展开/收起内嵌列表。已经拆出的独立小气泡不会因收起列表而被合并或关闭；只有在 HUD/托盘菜单中明确选择“合并全部任务气泡”才会合并。

![中文指标设置：周额度和 5 小时额度可以分别开关](assets/settings-metrics.png)

## 日常操作

- 点击任务数量，展开或收起主 HUD 内的列表。
- 拆出单个任务，或从 HUD / 通知区域菜单选择“全部分裂”。
- 拖动主 HUD 保存自定义位置；双击主 HUD 打开设置。
- 移除某一行只影响当前 HUD 视图；对应对话开始下一轮时会自动回来。
- 透明度支持 **0% 到 100%**。0% 会让 HUD 故意完全不可见，请用通知区域菜单或设置快捷方式恢复。
- 开启鼠标穿透后，可从通知区域菜单关闭，或直接让 Codex 关闭。

## 隐私与边界

所有处理都留在本机。HUD 只读取显示当前状态所需的受限信息：用量计数、模型、生命周期事件、工作区末级名、会话 ID 和本地官方标题；不会保存提示词、回复、工具输出、原始转录或凭据，不会修改 Codex 会话文件，也没有遥测或网络请求。

任务发现最多扫描 64 个近期会话文件；重新打开的旧会话按最新写入时间识别。内部/子代理会话和超过保留时间的终态任务不会进入可见列表。

详见 [PRIVACY.md](PRIVACY.md) 与 [SECURITY.md](SECURITY.md)。

## 平台支持

- **Windows 10/11 x64：** 已支持并提供安装包。
- **macOS / Linux / 其他架构：** 不提供二进制、安装器、工作流或支持承诺。

本项目已明确放弃 macOS 适配。欢迎 macOS 用户自行基于公开源码进行移植，但本仓库只发布和验证 Windows 版本。

## 开发与发布准备

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1 -RunRuntimeTests
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-release.ps1
```

安装包自带私有 .NET 运行时。源码开发需要 Windows PowerShell 5.1+、供插件宿主使用的 Node.js，以及仓库中的工具链。

提交和发布时可直接使用 [GITHUB_RELEASE_DRAFT_2.2.0.md](GITHUB_RELEASE_DRAFT_2.2.0.md)：其中包括 GitHub Desktop 可复制的提交文案、Release 正文、资产名称、校验和流程和上传前检查表。

## 当前状态

`2.2.0` 是 Windows x64 Release 候选版。常驻监控已迁移为编译型 .NET/WPF 宿主；设置进程与 `-Legacy` 回退路径仍保留用于恢复。这是独立、非官方项目，与 OpenAI 没有隶属或背书关系。

MIT License.
