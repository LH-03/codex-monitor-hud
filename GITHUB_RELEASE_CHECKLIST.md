# GitHub release checklist

- [ ] Run `scripts/test.ps1`.
- [ ] Validate `.codex-plugin/plugin.json`.
- [ ] Confirm locale key sets match.
- [ ] Confirm screenshots contain synthetic values only.
- [ ] Scan for local usernames, absolute paths, logs, databases and credentials.
- [ ] Verify `.gitignore` excludes settings, logs, archives and test output.
- [ ] Check `INSTALL_WITH_CODEX.md` from a clean copy.
- [ ] Test install, restart/new-task discovery and uninstall on Windows.
- [ ] Do not commit `~/.codex/sessions`, SQLite files or `%LOCALAPPDATA%\CodexTokenHUD`.
