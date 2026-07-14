# Sensitive information scan

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
