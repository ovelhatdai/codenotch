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

## Appearance and dashboard follow-up

- Dashboard has a direct sidebar entry and a prominent Appearance button. Display scope and the fixed-monitor picker are at the beginning of Appearance, with numbered monitors and orientation labels.
- A portrait-monitor shortcut moves the dashboard while preserving its visual layout; ring cards adapt to narrow windows. The bar can be mirrored on every display; the dashboard remains one movable window.
- Appearance includes explicitly simulated, live previews using the actual ring/cell views. Secondary rings now also render in compact and complete presentations. Weekly selection keeps the real all-models week when daily pacing is enabled.
- Bar organization supports individual accounts ordered Claude then Codex (preserving relative order within each service), one group per service, Claude only, or Codex only. Groups show account counts, individual quota rows on hover, and open a filtered dashboard on click. No aggregate percentage is invented; source polling and history remain unchanged.
- Missing Portuguese settings and tooltip translations were added, including weekly rings, extra Codex limits and reset-credit labels.
- Cards and compact lists show extra reset credits and expiry when supplied. Missing data says “Não informado”; zero is shown only when reported. No reset redemption is implemented by this display.
- Follow-up verification: 39 targeted tests passed, covering grouping, quota selection, display geometry and Codex usage/reset-credit parsing. Release build and installation succeeded.
- Installed UI verification: Portuguese labels, direct Dashboard entry and reset-credit rows were inspected. All-display bar scope was exercised; the user subsequently returned to one display. The portrait shortcut changed the saved dashboard monitor. Physical cable disconnection and login startup still require their separate checks.
- Opening Dashboard from Settings brings it onto the Settings window monitor. Ring-panel/list and grouping choices use segmented controls under the organization button; the portrait shortcut still moves the standalone window afterward.

- The dashboard ring panel reuses ProviderRing and TooltipCard: enlarged rings, numeric transitions, native glass cards, hover emphasis, and hover/click details. It follows the selected bar quota and percentage mode. Controls are collapsible, while filters, history and monitor selection remain accessible. Reduced-motion settings suppress card scaling. The portrait shortcut retains this panel instead of forcing a plain list.

## Dashboard parity: activity, alerts and daily pace

- The dashboard observes the fleet menu model directly. Live activity stays scoped to the provider/profile ID and feeds the same ProviderRing and TooltipCard activity inputs used by the bar, including working/waiting/completion states and session details. No separate activity poller or inferred account attribution is introduced.
- Permitted reset, session-limit and weekly-limit events fan out to the dashboard through the existing fleet alert method. It renders UsageResetCard, respects the existing notification/mute/sound decisions, and offers dismiss/automatic expiry without generating an extra sound. Alerts can appear with the bar hidden; macOS fallback behavior is preserved. Generation checks prevent an old timeout from clearing a newer repeated event.
- The dashboard applies DailyPace to the source snapshots with the same calculation as the bar. An explicit session/week choice still takes precedence for the large ring, and the real weekly quota remains in the account details. Disabling daily pace returns to the original source readings; stored history is not transformed.
- Validation: 43 targeted activity-coordinator, dashboard, daily-pace and usage-alert tests passed. Coverage includes profile isolation, all three alert kinds without a visible notch, replacement/expiry, daily-pace parity, and explicit week/session choices.

## Responsiveness during configuration

- Full-screen detection no longer waits on `CGWindowListCopyWindowInfo` on the main thread. One utility queue services a shared cache across monitors, with at most one request in flight, a two-second refresh interval and five-second stale-data expiry. A delayed reply is discarded. If WindowServer stalls, no additional requests accumulate and the bar stays available instead of folding on expired data.
- Local Makefile builds default to two concurrent jobs (`BUILD_JOBS` can override); test targets disable parallel test runners. The targeted validation was also run at reduced process priority.
- Validation: 60 targeted tests passed with no failures, including a blocked-query test that keeps the main queue responsive through 100 repeated reads, cache reuse/expiry, existing full-screen fold behavior, and the 43 dashboard/activity/alert tests above.
- The measured memory pressure after the incident did not establish memory exhaustion (64 GiB installed; the system reported 90% free). This is a point-in-time measurement, not evidence of the earlier peak or a guarantee that other applications cannot stall.
