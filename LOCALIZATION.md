# Localizing Codex Monitor HUD

Codex Monitor HUD ships with English (`en`), Simplified Chinese (`zh-CN`), and a
language-neutral symbol display (`symbols`). An install request written in any other language
uses English until a reviewed locale is added.

## Locale naming

Use a BCP 47 language tag for the file name, such as `ja`, `de`, `fr`, `pt-BR`, or `zh-TW`.
Use the language name that speakers normally see in their operating system and community:
`日本語`, `Deutsch`, `Français`, `Português (Brasil)`, `繁體中文`. Avoid flags: a language is not
always tied to one country.

## Add a locale

1. Copy `locales/en.json` to `locales/<language-tag>.json` and keep it UTF-8.
2. Translate every value without changing keys, placeholders such as `{0}` or `{tasks}`, units,
   JSON structure, or the `Codex` product name.
3. Prefer established operating-system and developer-community terminology. Keep HUD labels
   short; put necessary explanation in hints and tooltips.
4. Add the locale to the language selector in `src/SettingsWindow.xaml`, the preview validation
   set in `src/CodexMonitorHUD.ps1`, and the localization tests in `scripts/test.ps1`.
5. Run `scripts/test.ps1` and render both the settings page and HUD at common Windows scaling.
   Check clipping, line wrapping, symbol fallback, and light/dark contrast.

Translations should be reviewed by a fluent human before release. The installer deliberately
falls back to English instead of generating an unreviewed translation from a user's prompt.
