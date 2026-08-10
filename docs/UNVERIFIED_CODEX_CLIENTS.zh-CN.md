# 未验证的 Codex 客户端兼容性

> [English](UNVERIFIED_CODEX_CLIENTS.md)

这里记录的是**可能兼容，不是正式支持**。维护者没有逐个验证下面这些客户端，也不打算把每一种 Codex 前端都追着适配一遍。愿意碰运气的话，可以自己试一次，有结果欢迎反馈。

## 为什么可能会“没适配却已经能用”

Codex Monitor HUD 并不会通过某个只属于 Codex Desktop、VS Code 或 CLI 的专用 API 去连接它们。正常运行时，它监视已启用的本地 `CODEX_HOME`，发现 Codex rollout/session JSONL，再读取受限的 `session_meta` 元数据以及用量/生命周期记录，最后把这些状态投影到 HUD。来源徽标只是后面的一层分类，主要依据 `originator`、`source`、Profile 和 Provider 等元数据。

因此，只要另一个本地 Codex 客户端把兼容的持久化会话写进 HUD 已经监视的本地 Profile，HUD 就可能**先会读，后知道该怎么叫它**。VS Code 就是现成例子：在加入正式 VS Code 支持以前，它的会话数据其实已经能被读取，只是来源分类被显示成了 Desktop。

所以真正的边界不只是“支持哪个前端”，而更接近：**这个本地 Codex 表面会不会把兼容的 rollout/session 数据写进 Windows HUD 能看见的 `CODEX_HOME`。**

## 比较可疑的候选

| 表面 | 为什么可能已经能读 | 当前可能显示成 | 维护者验证 |
| --- | --- | --- | --- |
| Cursor | OpenAI 把 Cursor 列在使用 Codex 扩展的 VS Code 兼容编辑器中。 | 大概率 VS Code | 未测试 |
| Windsurf | OpenAI 把 Windsurf 列在使用 Codex 扩展的 VS Code 兼容编辑器中。 | 大概率 VS Code | 未测试 |
| VS Code Insiders | 与同一 Codex 扩展体系兼容。 | 大概率 VS Code | 未测试 |
| `codex exec` | OpenAI CLI 用它做脚本和 CI；当前上游源码使用 `SessionSource::Exec` 和客户端名 `codex_exec`。 | 大概率 Unknown | 未测试 |
| TypeScript Codex SDK | 当前官方 TS SDK 底层启动 `codex exec --experimental-json`，并把 originator 设为 `codex_sdk_ts`。 | 大概率 Unknown | 未测试 |
| Python Codex SDK | 当前官方 Python SDK 通过 JSON-RPC 控制本地 `codex app-server`，客户端名为 `codex_python_sdk`。 | 可能能读，但来源可能标错 | 未测试 |
| 自定义 `codex app-server` 客户端 | App Server 本来就用于驱动富客户端，并允许调用方通过 `clientInfo.name` 自报身份。 | Unknown，或可能误分类 | 未测试 |
| JetBrains Codex 集成 | OpenAI 把 JetBrains 作为独立集成列出，并非 VS Code 扩展家族。 | Unknown | 未测试，不做兼容性假设 |

Xcode 同样属于独立集成，但本项目不发布或验证 macOS。Codex Cloud/Web 任务不符合“本地 session 落盘”这个前提，不应期待自动出现。Remote SSH、WSL、Dev Container 也一样：只有当对应 Codex 会话实际写进 Windows HUD 能访问并正在监视的本地 Profile 路径时才可能显示。

## 为什么来源徽标可能是错的

当前 HUD 有意只识别少量来源身份：Desktop、`codex_vscode`、CLI，以及单独的 DeepSeek Profile 约定。其他情况会落到 unknown/default 分类。

另外还存在一个上游歧义。`openai/codex` 的一个 open issue 记录了：umbrella `codex app-server` 路径可能把第三方客户端会话写成“真实 `originator` + `source=vscode`”。这意味着一个客户端的数据可能完全可读，但如果软件只相信 `source` 字段，就会叫错它。VS Code 当初在本 HUD 里被误认成 Desktop，本质上就是同一类问题。

因此，**对于未验证客户端，Token / 上下文 / 状态显示正确，并不能证明来源徽标也正确。**

## 这份判断依据什么

核对时间：2026-08-11。

- OpenAI Codex IDE 文档：VS Code 与兼容编辑器使用 Codex 扩展；Cursor、Windsurf、VS Code Insiders 被列在这一组，而 Xcode、JetBrains 是独立集成。  
  https://developers.openai.com/codex/ide/
- OpenAI Codex App Server 文档：App Server 用于驱动 VS Code 扩展这类富客户端，并要求客户端通过 `clientInfo.name` 标识自己；文档中的 VS Code 示例使用 `codex_vscode`。  
  https://developers.openai.com/codex/app-server/
- OpenAI Codex CLI 文档：`codex exec` 是脚本、可重复工作流和 CI 的非交互入口。  
  https://developers.openai.com/codex/cli/
- OpenAI Codex SDK 文档：TypeScript SDK 可启动/恢复本地 Codex thread；Python SDK 通过 JSON-RPC 控制本地 Codex app-server。  
  https://developers.openai.com/codex/sdk/
- 当前 `openai/codex` TypeScript SDK 源码：它启动 `codex exec --experimental-json`，并设置 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_ts`。  
  https://github.com/openai/codex/blob/main/sdk/typescript/src/exec.ts
- 当前 `openai/codex` Python SDK 源码：默认 `client_name` 是 `codex_python_sdk`，并启动 `codex app-server --listen stdio://`。  
  https://github.com/openai/codex/blob/main/sdk/python/src/openai_codex/client.py
- 当前 `openai/codex` exec 源码：非交互 runtime 使用 `SessionSource::Exec` 和客户端名 `codex_exec`。  
  https://github.com/openai/codex/blob/main/codex-rs/exec/src/lib.rs
- 上游 issue：记录 `codex app-server` 第三方客户端出现“正确 `originator` + `source=vscode`”的情况。这个只应当视为上游问题记录，不是兼容性保证。  
  https://github.com/openai/codex/issues/23442

## 如果你愿意碰运气

从你关心的客户端里只启动一个很小的本地任务，看看 HUD 是否出现新任务即可。如果 Token、上下文和状态正常，但来源徽标错了，这也算很有价值的结果。

反馈时请**不要**上传完整 rollout JSONL。对来源识别真正有用的通常只是 `originator`、`source` 和 `model_provider`；请删掉或打码 session ID、路径、工作区名、凭据、提示词、回复和工具输出。

这份文档不构成支持承诺。以后 Codex 如果改变本地 session 格式、元数据、存储位置或客户端行为，这些“碰巧兼容”也可能随时失效。