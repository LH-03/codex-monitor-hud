# macOS unsigned real-device validation

This is the community real-device gate that cannot be replaced by Windows cross-publish or GitHub Actions. A rented cloud Mac is not required. Use a disposable macOS test account and synthetic sessions first when practical. Do not upload session files or inspect prompt, response, or tool-output content.

## Entry conditions

- Both native GitHub Actions architecture jobs are green and their bundle audits, health checks, six-mode smoke matrix, checksums, and install transaction tests are available.
- Test the exact public preview asset after verifying `SHA256SUMS.txt`; record the filename and calculated hash.
- Keep the existing Windows 2.2 installation and its settings untouched.

## Mechanical evidence already owned by Actions

Do not repeat or overstate these results. Actions can establish only native restore/build, Core tests, Mach-O architecture, plist validity, bounded health output, bundle privacy scan, functional synthetic smoke, paired app/plugin install transactions, and artifact checksums.

## Interactive checklist

1. Start from a clean temporary account. Confirm that double-click is blocked if quarantine applies, then use only Control-click **Open** or **System Settings → Privacy & Security → Open Anyway**. Record the exact macOS version and user-visible steps. Never run `xattr -d`, disable Gatekeeper, or grant unrelated privacy permissions.
2. Run summary, list, split, quiet, settings, and notification cases using the repository's isolated synthetic test. Confirm Retina text, transparency, resizing, position persistence, task numbering, terminal colors, a maximum of 12 bubbles, and no real task identity.
3. Close the HUD window and recover it from the status item. Test Show, mode switches, Settings, pause/resume, disable click-through, and Exit. Confirm a second launch wakes the existing instance rather than creating another monitor.
4. Enable click-through with Settings still open, verify clicks reach the app below, then recover through the status item and `passthrough-off.signal`. Check keyboard access before considering a no-Dock (`LSUIElement`) mode.
5. Exercise multiple displays, changed display arrangement, Retina/non-Retina scaling, Spaces, Mission Control, maximized and full-screen apps, display disconnect/reconnect, and saved custom positions.
6. Test notification allow, deny, subsequent delivery, and re-enable paths. Confirm notices remain bounded, visibly attributed to Codex, and do not synthesize lifecycle completion.
7. Test sleep/wake, long idle, network interruption, fast user switching, normal quit, forced process termination, MCP restart budget, and stale-heartbeat cleanup.
8. Only with explicit local permission, verify live Codex task creation, official-title refresh, completion/abort retention, reopened old threads, and validated `codex://threads/` navigation. Observe the rendered result; do not copy or upload the underlying JSONL.
9. Run a 30-minute 1/5/12-task synthetic soak and a 60-minute idle soak. Sample aggregate process counters only:

   ```sh
   sh scripts/measure-macos-runtime.sh <pid> 1800 5 /tmp/codex-monitor-hud-active.csv
   sh scripts/measure-macos-runtime.sh <pid> 3600 10 /tmp/codex-monitor-hud-idle.csv
   ```

   Review RSS, VSZ, CPU and file-descriptor trends. Do not call a working-set change a leak without corroborating private-memory/resource evidence.

10. Re-run `sh scripts/install-macos.sh --verify`, upgrade/repair, successful rollback and uninstall in redirected roots. Confirm settings and unrelated marketplace entries survive.

## Deferred until the checklist passes

- Login-item registration is intentionally absent until launch, quit, status-item recovery, sleep/wake and single-instance behavior are proven.
- `LSUIElement` is intentionally absent until status-item and accessibility recovery are proven.
- Apple signing/notarization is not required for this free project; unsigned manual approval is the accepted distribution boundary.

Record every result as pass, fail, or not tested. A green Actions run must never be reported as proof of Gatekeeper behavior, visual fidelity, permission UX, deep links, multiple displays, sleep/wake, or long-lived resource stability.
