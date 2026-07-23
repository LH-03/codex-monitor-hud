# Sensitive information scan

## Windows 2.2.0 release candidate - 2026-07-23

- Windows-only package staging excludes `private/`, local settings, session JSONL, logs, databases, test output, local agent directories, compiled source `bin/obj`, and the deferred macOS preview guide.
- No real session content was read, copied, packaged or uploaded; all runtime fixtures use synthetic paths and records.
- Final local ZIP audit: `657` files, exact archive/file-list parity, `0` Mac paths, `0` forbidden private/state/data paths, and `0` strict maintainer-path, GitHub-token, OpenAI-token, or private-key-pattern hits. The exact package hash is emitted with each freshly generated Release ZIP in `SHA256SUMS.txt`.

## 2.2.0 locally verified source - 2026-07-18

- Enumerated 144 public source candidates after excluding `.git`, `private`, `artifacts`, `.test-output`, compiled `bin/obj`, and the private staged runtime.
- Local username and machine repository/profile path hits: 0.
- OpenAI/GitHub credential prefixes and private-key header hits: 0.
- Candidate settings, `.env`, logs, session JSONL, databases, archives, certificates, and private keys: 0.
- Source tests now use synthetic session JSONL only. The install transaction gate redirects HOME/USERPROFILE/LOCALAPPDATA, proves post-switch failure recovery, and verifies `.agents`, `.codex`, `bin/obj`, settings, environment files, logs, archives, databases, and JSONL cannot enter the installed tree.
- The private `runtime/win-x64` was staged and installed only after the compiled gate passed. Source/install parity found no differences in the 144 non-runtime package files; key runtime hashes and installed health also passed. This is not a public-release ZIP scan and no ZIP or GitHub artifact was produced.

## 2.1.0 source scan - 2026-07-16

- Scanned 92 public source/package candidates after excluding `.git`, `artifacts`, `.test-output`, `private`, local workflow files and other installer exclusions.
- Local username, machine profile/repository path and host-name hits: 0.
- Credential, bearer token, private-key and common GitHub/OpenAI secret-pattern hits: 0.
- Included `.jsonl`, logs, databases, keys, certificates or ZIP archives: 0.
- Hidden bidi, zero-width and directional-control hits: 0.
- Behavior and context runtime fixtures use only `C:\Synthetic` workspaces, synthetic technical thread IDs and synthetic Token/context values. The refreshed behavior screenshots and quiet row/column visual previews are generated from default/synthetic state and contain no real task, account, session or machine data.
- `LOCALIZATION.md` contains language-tag examples only. The installer classifies no saved prompt or session text; Codex supplies `zh-CN` or `en` from the current install request.
- This is a source-candidate scan. A final staged ZIP and checksum still require a separate scan after the last package-affecting edit and before publication.

## 2.0.2-preview source scan - 2026-07-15

- Public candidates contain no local profile/repository paths, credentials, session JSONL, databases, logs, settings, archives, real task names or real Token values.
- New identity, completion-departure and theme-adaptive effect tests use synthetic workspaces, colors and lifecycle records only.
- Installer and local release procedure reject `private/`, `.test-output/`, generated artifacts and local-data extensions. The final exact ZIP is scanned again after the last public edit.

## 2.0.1-preview release scan - 2026-07-15

The release staging package was assembled from tracked public files plus the new public release notes only. It contains 85 files.

- Excluded local settings, sessions, databases, logs, `.test-output`, archives and generated artifacts through `.gitignore` and package staging rules.
- No maintainer path, user profile path or credential-shaped value was found in the staged package.
- The package checksum is published alongside the ZIP; test and runtime fixtures use synthetic values only.

## Unreleased proactive-notice and resumed-thread scan - 2026-07-15

Scanned 80 maintenance-source files after proactive Codex notices, bilingual settings screenshots, API-equivalent cost documentation and all-date resumed-thread discovery. Generated `.test-output` files and binary image contents were excluded from text matching.

- No maintainer username, temporary screenshot path or machine-specific absolute path was found in public text/source candidates.
- No bearer token, OpenAI-style key, GitHub token prefix or assigned API key was found; the sole matching phrase is this scan document's description of rejected credential shapes.
- Chinese and English reminder screenshots were generated from default/synthetic settings and contain no real task name, account value, session content or local path.
- The runtime task registry remains outside the project under local application state and contains only task number, workspace leaf, coarse status and update timestamp.
- No public clone, GitHub, Codex log, database or user-setting content was changed or uploaded.

## v2.0.0 rename source scan - 2026-07-15

Scanned the renamed maintenance source and release-text candidates after the Codex Monitor HUD identity change. Generated `.test-output` files and binary screenshots/icons were excluded from text matching.

- No maintainer username or maintenance-workspace absolute path was found in release candidates.
- No bearer token, OpenAI-style key, GitHub token prefix or assigned API key was found.
- No `.jsonl`, `.log`, database, credential, private-key, local settings or `.env` file is intended for the release package.
- The only legacy identity references are the explicit fresh-install warning and historical changelog/release explanation; runtime and current plugin identity use `codex-monitor-hud`.
- v2 was installed locally without adding logs, databases, credentials or user settings to the project or package; no public GitHub operation was performed.

## v1.4.2 maintenance-source scan

Scanned on 2026-07-15 after stackable reminder animation, bilingual reminder screenshots and unified icon work. Generated `.test-output` files and binary screenshots/icons were excluded from text matching.

- No maintainer username or maintenance-workspace absolute path was found in release text files.
- No bearer token, OpenAI-style key, GitHub token prefix or assigned API key was found.
- No `.jsonl`, `.log`, database, credential, private-key, local `settings.json` or `.env` file is included outside excluded synthetic test output.
- New reminder screenshots use synthetic task and Token data. The ICO is generated locally from deterministic drawing commands and contains no metadata or user data.

## v1.4.1 maintenance-source scan

Scanned on 2026-07-15 after list-density, persistent expand control, independent field selection, custom-position labeling and task-bubble resizing changes. Generated `.test-output` files and binary screenshots were excluded from text matching.

- No maintainer username or maintenance-workspace absolute path was found in release text files.
- No bearer token, OpenAI-style key, GitHub token prefix or assigned API key was found.
- No `.jsonl`, `.log`, database, credential, private-key, local `settings.json` or `.env` file is included outside excluded synthetic test output.
- Refreshed README screenshots were generated by the built-in synthetic preview path and contain no real task, log or account data.

## v1.4.0 maintenance-source scan

Scanned the maintenance source again on 2026-07-14 after the high-concurrency list styles, per-surface reminders, transparency modes and vector task-action controls. Excluded generated `.test-output` files and binary screenshots from text matching.

No matches were found for:

- the maintainer's Windows user path or maintenance workspace path;
- bearer tokens, OpenAI-style secret keys, GitHub personal-access-token prefixes or API-key assignments;
- copied prompts, assistant messages, tool output or real session-log content.
- included `.jsonl`, `.log`, database, local `settings.json`, credential or `.env` files outside the excluded synthetic test output.

New English and Chinese README screenshots for compact rows, information cards, status rails and settings were generated by the built-in synthetic preview paths. Task labels and Token/allowance values in those images are synthetic only. The 80-task churn fixtures and runtime log remain under `.test-output` and are not release content.

## Local v1.3.1 acceptance-build scan

Scan date: 2026-07-14

Result: pass for the 59 public-project files, excluding `.test-output`.

- Local username and machine-specific absolute path hits: 0
- Session-id pattern hits: 0
- Credential-shaped value hits: 0
- Included `.jsonl`, `.sqlite`, `.sqlite3`, `.db`, `.log`, `.pem` or `.key` files: 0
- Hidden bidi, zero-width and unexpected control hits: 0
- All generated validation screenshots use synthetic values and remain under `.test-output`.

This is a final maintenance-source scan before local installation. It must be repeated against a future public staging directory and ZIP before any GitHub release.

Scan date: 2026-07-13

Result: pass.

- Local username and machine-specific absolute path hits: 0
- Session-id pattern hits: 0
- Credential-shaped value hits: 0
- Included `.jsonl`, `.sqlite`, `.sqlite3`, `.db`, `.log`, `.pem` or `.key` files: 0
- Preview screenshots use synthetic Token values.
- Hidden bidi, zero-width and unexpected BOM controls: 0.
- Theme and extension documentation contains no local username, absolute machine path, session id or private Token data.
- `.test-output`, local settings and Git history are excluded from the release archive.

The scan is a release aid, not a substitute for reviewing the GitHub `Files changed` or upload list before publication.
