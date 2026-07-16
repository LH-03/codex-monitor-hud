# Package contents

- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.mcp.json`: local MCP lifecycle host configuration.
- `src/`: WPF HUD, parser module, XAML and MCP host.
- `scripts/`: install, start, settings, uninstall, source tests, real-WPF list/split tests, and isolated behavior tests.
- `skills/`: Codex-facing operational skill plus a distributable theme-authoring Skill.
- `locales/`: Simplified Chinese, English and symbol labels.
- `themes/`: ten data-driven theme definitions that forks can extend without editing runtime code.
- `docs/THEMING_AND_UI_EXTENSIONS.md`: public theme schema, status palette and XAML extension guide.
- `docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md`: deep project model for AI maintainers, macOS/Linux ports and other agent-runtime adapters.
- `assets/`: icon and synthetic preview screenshots.
- `GITHUB_PUBLISH_TEXT.md` and `RELEASE_NOTES_2.1.0.md`: copy-ready v2.1.0 GitHub metadata, release text and screenshot order. `GITHUB_RELEASE_NOTES.md` remains the historical v2 rename overview.
- `docs/PROJECT_STATUS.md`: current contracts, implementation state, verified display matrix, known limits, and migration boundary.
- `INSTALL_WITH_CODEX.md`: copy-and-paste installation prompts that keep first install basic and present advanced DIY features afterward as opt-in choices.
- `LOCALIZATION.md`: BCP 47 locale naming, human-review rules and steps for adding another language.
- `README.md` / `README.zh-CN.md`: public documentation.
- `COLOR_ATTRIBUTION.md`: Codex Micro display-reference source, values, mapping, and non-affiliation/color-matching limitations.
- `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`.
- `TEST_RESULTS.md` and `SENSITIVE_SCAN.md`: current verification evidence and privacy-oriented package scan results.
- `GITHUB_RELEASE_DRAFT_2.1.0.md` and `scripts/prepare-release.ps1`: copy-ready GitHub Desktop/Release fields and deterministic local ZIP/SHA-256 preparation. Generated output stays under ignored `artifacts/`.
- The installer creates on-demand desktop and Start menu settings shortcuts; no shortcut is placed in Windows Startup.

The package intentionally excludes `private/`, local settings, Codex logs, databases, test output, Git history, and machine-specific paths.
