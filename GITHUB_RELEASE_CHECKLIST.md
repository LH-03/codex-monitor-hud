# GitHub release checklist

- [ ] Confirm product, plugin, MCP, Skill, runtime paths, shortcuts, icon and repository all use Codex Monitor HUD / `codex-monitor-hud`.
- [ ] Confirm v2 is a fresh identity: old `codex-token-strip` detection stops before any write and no legacy settings are imported or deleted.
- [ ] Run `scripts/test.ps1`.
- [ ] Validate `.codex-plugin/plugin.json`.
- [ ] Confirm locale key sets match.
- [ ] Confirm screenshots contain synthetic values only.
- [ ] Scan for local usernames, absolute paths, logs, databases and credentials.
- [ ] Verify `.gitignore` excludes settings, logs, archives and test output.
- [ ] Check `INSTALL_WITH_CODEX.md` from a clean copy.
- [ ] Test install, restart/new-task discovery and uninstall on Windows.
- [ ] Confirm a new task leaves the waiting state without restarting the HUD.
- [ ] Confirm weekly allowance updates without restarting the HUD.
- [ ] Test real click and wheel pass-through on Windows 10/11 where available.
- [ ] Test disabling click-through from the notification-area menu, settings shortcut and `monitor_hud_disable_click_through`.
- [ ] Test multiple monitors and mixed DPI before calling click-through fully validated.
- [ ] Confirm font size persists with 0.1 precision and all four status color schemes remain editable.
- [ ] Do not commit `~/.codex/sessions`, SQLite files or `%LOCALAPPDATA%\CodexMonitorHUD`.
- [ ] Let the repository owner rename the GitHub repository manually, then update GitHub Desktop's remote before creating the v2.0.0 Release.
