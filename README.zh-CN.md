# Codex Monitor HUD

> [English](README.md) · 简体中文

Codex Monitor HUD 是面向 Windows 版 Codex Desktop 的桌面监控浮层。它只读取近期本地 Codex 会话记录中受限的一部分数据，并将当前状态显示为汇总 HUD、可展开任务列表或独立任务气泡。

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

当前实现基于 Windows PowerShell 5.1、WPF、用于托盘图标的 Windows Forms，以及少量 Win32 互操作。它不建立数据库；会话发现后只读取新增字节；语言、外观和可见投影会缓存；没有变化时不会重建 WPF 控件树。

Windows PowerShell/WPF 在解析或渲染高峰后可能保留较高的私有提交内存。HUD 会在更新后把未使用的工作集页面归还给 Windows，因此物理常驻内存会下降，但私有提交高水位不会凭空消失。[TEST_RESULTS.md](TEST_RESULTS.md) 记录了本机实测，数值只代表测试环境，不是所有电脑的统一承诺。若要继续明显降低私有提交底座，需要未来把常驻宿主迁移到编译型 .NET。

## 隐私

所有处理均在本机完成。HUD：

- 只读取显示所需的顶层用量、模型、生命周期、工作区末级名称、会话 ID 和本地官方标题；
- 不保存提示词、助手回复、工具输出、原始对话或凭据；
- 不修改 Codex 会话文件；
- 不发起网络请求，也没有遥测；
- MCP 任务注册表只包含任务编号、工作区末级名称、粗粒度状态和更新时间。

详见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

## 运行要求

- Windows 10 或 Windows 11；
- 能提供本地会话记录的 Codex Desktop；
- Windows PowerShell 5.1 或更高版本；
- Codex 插件宿主可以使用 Node.js。

## 使用 Codex 安装

把仓库地址交给 Codex，并要求它先阅读 [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md)。可直接使用：

```text
从这个仓库安装 Codex Monitor HUD。先阅读 INSTALL_WITH_CODEX.md。
首次安装使用简体中文，升级时保留现有设置；运行项目测试并安装个人插件。
未经我确认，不要开启主动通知、成本估算、鼠标穿透、第三方主题或 Windows 登录自启动。
```

首次中文安装对应 `-DefaultLanguage zh-CN`。

## 手动安装

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -DefaultLanguage zh-CN
```

升级会保留现有设置。安装器会创建桌面和开始菜单设置快捷方式，不会开启 Windows 登录自启动。

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode list -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode split -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

测试使用合成会话和隔离状态目录。另见[架构说明](docs/ARCHITECTURE.md)、[项目状态](docs/PROJECT_STATUS.md)、[测试结果](TEST_RESULTS.md)和[贡献指南](CONTRIBUTING.md)。

## 项目状态与声明

当前源码版本为 `2.1.0`。项目只支持 Windows，是独立的非官方开源项目，与 OpenAI 没有隶属或背书关系。当前版本摘要见 [RELEASE_NOTES_2.1.0.md](RELEASE_NOTES_2.1.0.md)。

MIT License。
