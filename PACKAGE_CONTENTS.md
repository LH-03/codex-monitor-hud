# Package contents

- `.codex-plugin/plugin.json`: Codex plugin manifest.
- `.mcp.json`: local MCP lifecycle host configuration.
- `src-dotnet/` and `tests-dotnet/`: platform-neutral Core, verified Windows WPF shell, independent functional Avalonia macOS host, and zero-dependency Core regression executable source.
- `runtime/win-x64/`: release builds contain the compiled application and private .NET Desktop runtime; source checkouts create it only after the compiled gate passes.
- `src/`: exact-compatible Settings host, emergency legacy HUD, XAML assets, parser module, and MCP host.
- `scripts/`: transactional install/rollback, trusted-Release repository routing, Windows/macOS compiled build and audit gates, start/settings/uninstall commands, source tests, real-WPF list/split tests, and isolated behavior tests.
- `skills/`: Codex-facing operational skill plus a distributable theme-authoring Skill.
- `locales/`: Simplified Chinese, English and symbol labels.
- `themes/`: ten data-driven theme definitions that forks can extend without editing runtime code.
- `docs/THEMING_AND_UI_EXTENSIONS.md`: public theme schema, status palette and XAML extension guide.
- `docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md`: deep project model for AI maintainers, macOS/Linux ports and other agent-runtime adapters.
- `assets/`: icon and synthetic preview screenshots.
- Historical 2.1/2.2 material remains for traceability. The local `3.0.0` candidate is not a macOS release until native Actions and interactive cloud-Mac gates pass.
- `docs/PROJECT_STATUS.md`: current contracts, implementation state, verified display matrix, known limits, and migration boundary.
- `INSTALL_WITH_CODEX.md` and `install-manifest.json`: canonical low-reasoning repository installation protocol, platform/asset routing, checksum stop rules, settings preservation and rollback operations.
- `.github/workflows/unsigned-macos.yml`: unsigned dual-architecture macOS build, host-smoke, privacy-audit and install-transaction workflow.
- `docs/MACOS_PORTABILITY_PHASE1.md`: portable-Core audit and the boundary between Actions evidence and required interactive cloud-Mac validation.
- `docs/MACOS_CLOUD_VALIDATION.md` and `scripts/measure-macos-runtime.sh`: interactive unsigned-release checklist and aggregate-only Mac process sampling without session-content inspection.
- `LOCALIZATION.md`: BCP 47 locale naming, human-review rules and steps for adding another language.
- `README.md` / `README.zh-CN.md`: public documentation.
- `COLOR_ATTRIBUTION.md`: Codex Micro display-reference source, values, mapping, and non-affiliation/color-matching limitations.
- `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `LICENSE`.
- `TEST_RESULTS.md` and `SENSITIVE_SCAN.md`: current verification evidence and privacy-oriented package scan results.
- `GITHUB_RELEASE_DRAFT_2.1.0.md` and `scripts/prepare-release.ps1`: copy-ready GitHub Desktop/Release fields and deterministic local ZIP/SHA-256 preparation. Generated output stays under ignored `artifacts/`.
- The installer creates on-demand desktop and Start menu settings shortcuts; no shortcut is placed in Windows Startup.

The package intentionally excludes `private/`, local settings, Codex logs, databases, test output, Git history, and machine-specific paths.
