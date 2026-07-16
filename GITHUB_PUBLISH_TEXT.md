# Superseded GitHub publishing text for v2.1.0

> Use [GITHUB_RELEASE_DRAFT_2.1.0.md](GITHUB_RELEASE_DRAFT_2.1.0.md) for the current GitHub Desktop commit and Release fields. This retained file is historical draft material only.

## Repository name

`codex-monitor-hud`

## Repository description

`A local Windows HUD for current Codex task state, multi-task routing, and optional attention cues.`

## Commit message

`Release 2.1.0: stable multi-task HUD and runtime-path reductions`

## Release tag

`v2.1.0`

## Release title

`Codex Monitor HUD v2.1.0`

## Release body

Copy the contents of `RELEASE_NOTES_2.1.0.md`.

## Suggested Chinese announcement

```text
Codex Monitor HUD v2.1.0 是 Windows 版稳定 v2。它提供汇总、双行任务列表和独立气泡，加入按需设置进程、静默任务灯与上下文提醒，并减少无变化时的重复解析和 WPF 重建。处理仍在本地，不修改 Codex 会话。PowerShell/WPF 的提交内存高水位与测试边界已在文档中明确说明。
```

## Suggested English announcement

```text
Codex Monitor HUD v2.1.0 is the stable Windows v2 line. It provides summary, two-line task-list, and independent-bubble views; adds an on-demand Settings process, quiet task lights, and context alerts; and reduces unchanged parsing and WPF reconstruction. Processing remains local and does not modify Codex sessions. The PowerShell/WPF committed-memory boundary is documented explicitly.
```

## Screenshot order

1. `assets/hud-frost.png` — primary compact HUD screenshot.
2. `assets/settings.png` — Simplified Chinese settings and weekly allowance option.
3. `assets/color-picker.png` — HSV wheel and ARGB editor.
4. `assets/hud-cards.png` — metric-card layout.
5. `assets/settings-en.png` — English settings.
6. `assets/settings-reminders.png` — stackable status-dot and bubble reminders.
7. `assets/settings-reminders-en.png` — English reminder controls.
8. `assets/settings-behavior.png` — Simplified Chinese task navigation, quiet indicator and context thresholds.
9. `assets/settings-behavior-en.png` — English task navigation, quiet indicator and context thresholds.

All screenshots contain synthetic values and are safe to publish.
