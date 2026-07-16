# Contributing

Contributions are welcome.

1. Fork the repository and create a focused branch.
2. Keep the local-log parser read-only.
3. Do not add telemetry, prompt capture or raw transcript storage.
4. Run `scripts/test.ps1` before opening a pull request. For display/state changes, also run affected list and split modes of `scripts/test-runtime-isolated.ps1`; for quiet/context behavior, run `scripts/test-behavior-isolated.ps1`.
5. Use synthetic values in screenshots and fixtures.
6. Describe Windows and Codex versions used for visual testing.
7. Separate private committed memory from physical working set when reporting performance, and include the sample duration and task count.

Please keep localization keys aligned across `locales/zh-CN.json`, `locales/en.json` and `locales/symbols.json`.
