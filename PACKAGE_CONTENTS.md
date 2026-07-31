# Package contents

- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.mcp.json`: local MCP lifecycle host configuration.
- `src-dotnet/` and `tests-dotnet/`: platform-neutral Core, compiled Windows WPF shell, and zero-dependency Core regression executable source.
- `runtime/win-x64/`: release builds contain the compiled application and private .NET Desktop runtime; source checkouts create it only after the compiled gate passes.
- `src/`: exact-compatible Settings host, emergency legacy HUD, XAML assets, parser module, and MCP host.
- `scripts/`: transactional Windows install/rollback, trusted-Release repository routing, compiled build/health gates, start/settings/uninstall commands, source tests, real-WPF list/split tests, and isolated behavior tests.
- `skills/`: Codex-facing operational skill plus a distributable theme-authoring Skill.
- `locales/`: Simplified Chinese, English and symbol labels.
- `themes/`: ten data-driven theme definitions that forks can extend without editing runtime code.
- `docs/THEMING_AND_UI_EXTENSIONS.md`: public theme schema, status palette and XAML extension guide.
- `docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md`: deep project model for AI maintainers and community source adaptations to other agent runtimes.
- `assets/`: icon and synthetic preview screenshots.
- Historical material remains for traceability. The `2.2.0` package is Windows x64 only; macOS is not supported or packaged.
- `docs/PROJECT_STATUS.md`: current contracts, implementation state, verified display matrix, known limits, and migration boundary.
- `INSTALL_WITH_CODEX.md` and `install-manifest.json`: canonical low-reasoning repository installation protocol, platform/asset routing, checksum stop rules, settings preservation and rollback operations.
- `LOCALIZATION.md`: BCP 47 locale naming, human-review rules and steps for adding another language.
- `README.md` / `README.zh-CN.md`: public documentation.
- `COLOR_ATTRIBUTION.md`: Codex Micro display-reference source, values, mapping, and non-affiliation/color-matching limitations.
- `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`.
- `TEST_RESULTS.md` and `SENSITIVE_SCAN.md`: current verification evidence and privacy-oriented package scan results.
- `GITHUB_RELEASE_DRAFT_2.2.0.md` and `scripts/prepare-release.ps1`: copy-ready GitHub Desktop/Release fields and deterministic local ZIP/SHA-256 preparation. Generated output stays under ignored `artifacts/`.
- The installer creates on-demand desktop and Start menu settings shortcuts; no shortcut is placed in Windows Startup.

The package intentionally excludes `private/`, local settings, Codex logs, databases, test output, Git history, and machine-specific paths.
