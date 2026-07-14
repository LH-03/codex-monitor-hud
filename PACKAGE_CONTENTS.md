# Package contents

- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.mcp.json`: local MCP lifecycle host configuration.
- `src/`: WPF HUD, parser module, XAML and MCP host.
- `scripts/`: install, start, test, settings and uninstall helpers.
- `skills/`: Codex-facing operational skill plus a distributable theme-authoring Skill.
- `locales/`: Simplified Chinese, English and symbol labels.
- `themes/`: ten data-driven theme definitions that forks can extend without editing runtime code.
- `docs/THEMING_AND_UI_EXTENSIONS.md`: public theme schema, status palette and XAML extension guide.
- `docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md`: deep project model for AI maintainers, macOS/Linux ports and other agent-runtime adapters.
- `assets/`: icon and synthetic preview screenshots.
- `GITHUB_PUBLISH_TEXT.md` and `GITHUB_RELEASE_NOTES.md`: copy-ready GitHub metadata, release text and screenshot order.
- `docs/PROJECT_STATUS.md`: concise maintenance state and dormant 5-hour re-enable checklist.
- `INSTALL_WITH_CODEX.md`: copy-and-paste installation prompts that keep first install basic and present advanced DIY features afterward as opt-in choices.
- `README.md` / `README.zh-CN.md`: public documentation.
- `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`.
- `TEST_RESULTS.md` and `SENSITIVE_SCAN.md`: release verification evidence.
- The installer creates on-demand desktop and Start menu settings shortcuts; no shortcut is placed in Windows Startup.

The package intentionally excludes local settings, Codex logs, databases, test output, Git history and machine-specific paths.
