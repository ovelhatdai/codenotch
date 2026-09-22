# CodeNotch Pessoal — 2026-09-22

This branch is a personal macOS edition. It is not an upstream release and does not change the Windows application.

## Behavior

- Claude Code and Codex accounts can authenticate through their official CLIs into separate, user-selected credential directories. Registration checks the expected email. Existing profiles remain available; duplicate indicators can be hidden without signing those profiles out.
- Account names are editable. The indicator following the active Codex application identifies its current email; independent sessions retain their own identity. Responses spanning an identity change are discarded, and notification baselines reset when the identity changes.
- The bar supports minimum, compact and complete presentations, used or remaining percentages, session/week selection, and a coral Claude icon. Dragging repositions the bar along its selected screen edge.
- A separate dashboard groups accounts by service or display name. Cards use four, two or one columns according to available width; a compact list supports narrow windows. The window can move between monitors and remember placement per display.
- Reading status distinguishes current, previous, offline, expired, denied and mismatched identities. Displayed freshness ages with the source timestamp instead of remaining current indefinitely.
- Local history separates account/service/email, observed quota peaks, supplier-provided daily tokens, and costs by currency. Missing values are not zero. Budgets provide warnings; they do not enforce provider-side spending blocks.
- This edition has its own preference domain and application identity. It does not use the upstream Sparkle update feed. Portuguese release-note translations are included.

## Build and install

Use Xcode and XcodeGen as described in CONTRIBUTING.md. Run `make test-ci` for unsigned automated tests. Run `make install` to build, verify signing and install `/Applications/CodeNotch Pessoal.app`; the previous personal application is retained under a temporary backup directory. The original application is not replaced.

Credentials are created by the official CLI in the directory chosen at connection time. They are not part of this repository. Do not add credentials, preference exports, history files or login screenshots to a pull request.

## Validation and remaining work

- Complete test run before the final freshness correction: 1,769 tests, three skipped, no failures.
- Freshness correction: ten targeted history/reading-health tests, no failures; Release build and installation succeeded afterward.
- The installed application was reopened and retained eight enabled account indicators. Seven accounts were confirmed as independent sessions; one existing Codex profile remains in use while its independent login is deferred.
- Dashboard grouping, compact list, account history and the four-monitor menu were inspected in the installed application.
- Physical display disconnection/reconnection and startup after a full macOS restart remain unverified. Geometry tests do not substitute for these checks.
- Codex credential expiry requires reconnecting the independent account. This change does not implement new billing integrations for Gemini, WaveSpeed, Higgsfield or ZapSign.
- Personal screens currently use Portuguese copy. They are not yet localized to every language supported upstream. This personal branch should be adapted before proposing it as a general upstream contribution.
