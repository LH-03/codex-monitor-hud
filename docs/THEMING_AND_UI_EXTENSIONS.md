# Themes and UI extension points

Codex Monitor HUD treats themes as bounded data, never executable code.

## Install and share

Open **Settings > General > Theme workshop** and either drop a theme file onto the card/window or choose **Import theme…**. Imported themes are validated and stored under `%LOCALAPPDATA%\CodexMonitorHUD\themes`, so a plugin update does not overwrite them.

Supported containers:

- `.json` or `.cmhud-theme` for declarative themes;
- `.cmhud-theme.zip` for `theme.json` plus optional local PNG/JPG files under `assets/`.

ZIP packs cannot contain scripts, fonts, DLLs, remote resources, arbitrary file types, or escaping paths. The importer limits package size, entry size, and file count.

## Rich visual surface

Themes may style:

- solid, gradient, or bounded local-image surfaces;
- ARGB foreground, muted, accent, border, and seven status colors;
- typography, font size, radius, opacity, border width, shadow, and status-dot size;
- metric layout, list style/density, and task-name visibility;
- summary/list/task-bubble automatic reminder appearance and independent dot rhythm;
- a separate proactive-Codex-notice mode, ARGB glow color/preset, and intensity without enabling the notice channel or granting Codex permission.

Themes may not change reminder triggers, monitoring scope, selected metrics, token accounting, log paths, privacy behavior, click-through safety, or executable behavior.

The complete schema, enums, limits, ZIP layout, and examples live in [`skills/create-monitor-hud-theme/references/theme-format.md`](../skills/create-monitor-hud-theme/references/theme-format.md). The callable creation workflow is [`$create-monitor-hud-theme`](../skills/create-monitor-hud-theme/SKILL.md).

## UI extension points

- `src/HudWindow.xaml`: summary and list shell.
- `src/TaskBubbleWindow.xaml`: independent task surface.
- `src/SettingsWindow.xaml`: organized settings, tooltips, and Theme Workshop drop target.
- `src/CodexMonitorHUD.ps1`: theme validation/import, runtime application, and WPF wiring.
- `src/MonitorHud.Core.psm1`: theme discovery and safe config normalization.
- `config.default.json`: public persisted configuration surface.
- `locales/*.json`: translated labels; every locale must keep identical keys.

When adding a theme capability, add a safe default, normalize/clamp it, add import validation, update the Skill schema, render both compact and concurrent-task previews, and run `scripts/test.ps1`. For deeper feature or platform changes, start with [AI_PORTING_AND_CUSTOMIZATION_GUIDE.md](AI_PORTING_AND_CUSTOMIZATION_GUIDE.md).
