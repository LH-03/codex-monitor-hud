# Themes and UI extension points

Codex Token HUD keeps visual customization data separate from runtime logic. Most visual variants can be added without editing PowerShell.

## Add a theme

Create a new UTF-8 JSON file in `themes/`. Files are loaded in `order`, then by `id`.

```json
{
  "id": "my-theme",
  "order": 50,
  "names": {
    "zh-CN": "My Theme 自定义",
    "en": "My Theme",
    "symbols": "◆"
  },
  "settings": {
    "background": "#EAF7F7F9",
    "foreground": "#FF101828",
    "accent": "#FF0A84FF",
    "border": "#22FFFFFF",
    "fontSize": 14,
    "cornerRadius": 22,
    "opacity": 1.0
  }
}
```

Required settings are `background`, `foreground`, `accent`, and `border`. Colors use `#AARRGGBB`. Supported optional theme settings are `muted`, `cornerRadius`, `opacity`, and `fontSize`. Themes intentionally cannot change layout, number format, language, monitoring scope or selected metrics; those are independent user choices.

## Status palette

Five monitored states are available under `statusColors`:

- `active`: a Token snapshot was appended recently;
- `listening`: the HUD is watching active task logs but no very recent snapshot arrived;
- `idle`: no recent snapshot is available;
- `paused`: monitoring was paused by the user;
- `error`: a session file could not be read recently.

Thresholds are in `statusTiming`. Users can edit them in Advanced status settings or in `%LOCALAPPDATA%\CodexTokenHUD\settings.json`.

## UI extension points

- `src/HudWindow.xaml`: HUD shell and metric host.
- `src/SettingsWindow.xaml`: settings layout. Named controls are wired in `src/CodexTokenHUD.ps1`.
- `src/ColorPickerWindow.xaml`: HSV wheel, value, alpha, and ARGB editor.
- `themes/*.json`: data-only visual presets.
- `locales/*.json`: translated UI labels. All locale files must keep identical keys.
- `config.default.json`: stable public configuration surface.

When adding a control, give it a unique `x:Name`, read it with `Find-Control`, keep the default in `config.default.json`, and preserve recursive config merging so older user settings continue to work. Run `scripts/test.ps1` before publishing. Do not read or package Codex conversation text.
