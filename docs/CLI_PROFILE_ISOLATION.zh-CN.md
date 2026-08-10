# Codex CLI 配置与可选 Provider 隔离

> [English](CLI_PROFILE_ISOLATION.md) · Windows x64 · Codex Monitor HUD 3.0.0

Codex Monitor HUD 开箱即可监控正常安装的 Codex CLI。只想监控原生 Codex CLI 的用户，**不需要**创建第二套配置。本页的隔离方案只适合主动让 Codex CLI 连接另一套兼容模型 Provider，并希望把配置、认证状态、会话和 HUD 来源标识与正常 OpenAI 配置彻底分开的用户。

## HUD 能监控什么

| CLI 结构 | HUD 支持情况 |
| --- | --- |
| 使用普通 `CODEX_HOME` 的原生 Codex CLI | 默认支持 |
| 位于 `~/.codex-deepseek` 的第二套 Codex CLI Home | 可选支持，可独立识别和筛选 |
| 任意其他自定义 `CODEX_HOME` 路径 | 当前 HUD 尚不能自定义添加 |
| 不写入 Codex 会话记录的其他 CLI | 不支持 |

界面把第二种来源称为“DeepSeek CLI”，因为这是 v3.0.0 实测过的隔离约定。它仍然是 Codex CLI，只是 Provider 与配置根目录不同。Codex 或第三方 Provider 更新后，兼容性都可能改变；HUD 能显示 Codex 已经写出的会话，但不能让本来不兼容的 Provider 变得兼容。

## 先理解三层结构

```text
CODEX_HOME       -> Codex 配置、认证状态和会话
当前工作目录     -> Codex 实际操作的项目
模型 Provider    -> 该 Profile 选择的 API 后端
```

普通配置通常是：

```text
%USERPROFILE%\.codex
```

HUD 3.0.0 额外识别的隔离配置是：

```text
%USERPROFILE%\.codex-deepseek
```

不要合并这两个目录，也不要在它们之间复制认证文件。

## Windows 安全启动方式

在 PowerShell 中启动正常 OpenAI Profile：

```powershell
$env:CODEX_HOME = "$HOME\.codex"
Write-Host "Profile: OpenAI`nCODEX_HOME: $env:CODEX_HOME`n项目: $PWD"
codex
```

启动隔离 Profile：

```powershell
$env:CODEX_HOME = "$HOME\.codex-deepseek"
Write-Host "Profile: isolated provider`nCODEX_HOME: $env:CODEX_HOME`n项目: $PWD"
codex
```

如果想做成固定命令，又不想修改全局环境变量，可以把下面的函数加入 PowerShell Profile：

```powershell
function codex-openai {
    $env:CODEX_HOME = "$HOME\.codex"
    Write-Host "Profile: OpenAI`nCODEX_HOME: $env:CODEX_HOME`n项目: $PWD"
    codex @args
}

function codex-isolated {
    $env:CODEX_HOME = "$HOME\.codex-deepseek"
    Write-Host "Profile: isolated provider`nCODEX_HOME: $env:CODEX_HOME`n项目: $PWD"
    codex @args
}
```

这里的环境变量只影响当前 PowerShell 进程及其子进程，不会重写默认 Profile。

## 配置隔离 Provider

1. 新建 `~/.codex-deepseek`，不要修改 `~/.codex`。
2. 把隔离 Profile 的用户级 `config.toml` 放在该目录。
3. 按 Codex 当前配置参考设置 `model_provider` 与 `model_providers.<id>`。
4. 按 Provider 当天的官方文档确认 API 地址、模型名、协议和兼容限制。
5. 真实 API Key 应放进 Provider 文档要求的环境变量或其他受支持的密钥机制；绝不能写进本仓库、启动脚本、截图或教程。
6. 正式使用前做一次小型冒烟测试：读取临时文件、新建并回读临时文件、执行无害命令、连续完成数轮工具调用，再测试 `codex resume`。

Codex 配置格式会演进，不要从旧教程盲目复制 Provider 配置块。准备 v3.0.0 时，Codex 文档把 `responses` 列为受支持的自定义 Provider wire API；以后配置或升级 Codex 时应重新查看当天官方文档。

## 让 HUD 同时看到两套 Profile

1. 正常安装并启动 Codex Monitor HUD；原生 CLI 会自动使用普通 Profile。
2. 在 **设置 > 监控来源** 中同时开启 **Codex CLI · OpenAI** 与 **Codex CLI · DeepSeek**。
3. 用 `CODEX_HOME=$HOME\.codex-deepseek` 启动隔离 CLI。
4. 真正开始一个顶层任务；HUD 中应出现波形终端来源图标。

如果希望两套 Profile 中的 Codex 都能主动发送可选 HUD 通知，可以分别在两个 `CODEX_HOME` 中安装 HUD 插件/MCP 控制面。它不是只读会话监控的必要条件。

## 核对与恢复

每次启动前查看启动器打印的 Profile、`CODEX_HOME` 和工作目录；进入 Codex 后再用当前版本的状态/模型命令确认 Provider。

要回到原生 Codex CLI，关闭隔离终端，或执行：

```powershell
$env:CODEX_HOME = "$HOME\.codex"
codex
```

如果 Codex 或 Provider 更新后隔离配置失效，先停用隔离 Profile，保留普通 Profile 不动。不要通过迁移、合并或编辑 Codex 会话数据库来“修复”。

## 参考

- [Codex 配置参考](https://developers.openai.com/codex/config-reference)
- [DeepSeek API 快速开始](https://api-docs.deepseek.com/zh-cn/)

Codex Monitor HUD 是独立的非官方项目，不分发 Provider 凭据、不为第三方后端提供兼容性认证，安装 HUD 时也不会修改 Codex 配置。
