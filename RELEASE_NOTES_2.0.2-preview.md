# Codex Monitor HUD v2.0.2-preview

Codex Monitor HUD is a local-first, lightweight real-time task monitor for Codex Desktop on Windows. This remains a preview release.

## What changed

- **Stable task identity from first appearance:** a new session waits briefly for its own identity metadata instead of showing an incomplete primary title. Delayed official titles update in place, and internal auto-review sessions stay out of the user-task list.
- **Visible, configurable completion departure:** after the existing retention period, each completed list row or independent bubble can use natural fade, a gentle cue, a focused exit or a deliberately obvious bounded beacon. A new turn cancels departure and resumes monitoring immediately.
- **Light/dark theme-aware effects:** status-dot reminders, automatic surface reminders, proactive CODEX notices and completion departure now share surface-polarity detection. Dark themes receive a lighter, broader bounded glow; light themes receive a darker, tighter treatment, while the user's selected intensity remains in control.
- **More reliable workspace labels:** `session_meta.cwd` can restore the privacy-safe workspace leaf when recent Token records no longer include turn context.

## Privacy and boundaries

- Processing remains local. The HUD does not read prompt text, replies or tool output to name a task.
- The release package excludes local settings, sessions, databases, logs, test output, private handoffs, archives and generated local artifacts.
- Proactive CODEX notices remain opt-in. Theme packages may style their bounded visuals but cannot enable them or grant permission.

## Validation

PowerShell, XAML, JSON, locale and Node checks pass. Synthetic delayed-identity regressions pass in isolated list and split modes. Dedicated real-WPF list and split runs confirm that the strongest completion departure remains target-local, stays visible for its bounded duration and then removes the completed task. Synthetic light, dark, gradient and image-theme profiles verify adaptive effect direction and ceilings.

## Install or update

Give the repository URL to Codex and ask it to follow `INSTALL_WITH_CODEX.md`, or run `scripts/install.ps1` on Windows. Restart Codex or open a new task if plugin discovery does not refresh immediately.
