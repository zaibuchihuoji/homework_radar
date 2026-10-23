# Settings redesign implementation plan

**Goal:** Make settings feel deliberate and polished, with a calm yellow/white default and distinct existing themes.

**Approved design:** The user accepted the previous recommendation: simplify hierarchy, typography and rows; place detailed controls behind five clear entries. Preserve all features and old data. Extend the same treatment to settings details and dialogs.

**Architecture:** Add presentation-only settings components. Keep existing AppState, Storage, synchronization, notification, backup and update callbacks. Reorganize SettingsPage into five destinations without changing storage or platform code.

**Constraints:** No subagents, no release/push, no data migration or dependency changes. Work in the current clean trial checkout. Only targeted tests and a local Android runtime check; no cloud iOS rebuild or broad unrelated test suite.

- [x] Introduce shared settings scaffold, sections, rows, notes and dialog styling. Preserve theme materials via existing theme primitives.
- [x] Reorganize settings into appearance/widgets, reminders/timetable, sync/background, data, and about/help. Preserve every existing entry and confirmation.
- [x] Apply the same components to notification settings, background sync, section times, hidden work and archives. Refine settings dialogs and update presentation without changing behavior.
- [x] Update navigation regression coverage for the new hierarchy, run affected widget tests and static analysis.
- [x] Run the app in a newly created independent Android emulator, inspect default and alternate themes, details and dialogs. Retain screenshots; review the diff for unintended storage/logic changes.

## Verification scope

- Five entry points remain reachable and opening settings does not overwrite a seeded homework/hidden record.
- Existing theme switching, reminder toggles and Android notification settings remain usable, including narrow/enlarged layouts.
- Backup import cancellation remains non-destructive; original import/export/restore callbacks remain unchanged.
- Section time actions, update download/cancel/background actions retain original callbacks.
- Static analysis of affected source and tests; screenshot checks in the real Android runtime.

## Progress

- Initial worktree clean. Existing branch `fix/ios-sideload-build`; no new worktree or subagents needed.
- Emulator correction: an initial read-only `alantop` instance was closed after the user objected. All subsequent runtime verification uses `codex_settings_qa_20261023` on emulator-5564 with its own configuration and data directory under the audit folder. Do not reuse the user's AVD.
- Runtime build: child-process-only `jdk.net.unixdomain.tmpdir` workaround makes the JDK fall back to TCP for a broken local AF_UNIX selector. No global Java, network or Gradle configuration changed.
- Verification: 45 targeted settings/notification/section-time/update tests plus 13 selected existing modal/default-chooser/archive tests passed. Additional navigation verification checks hidden records and import cancellation against seeded old data.
- Runtime: Android 16 API 36; default, pixel, paper, terminal and green themes; settings details, notification page, section time picker, theme mode, widget guide and import confirmation inspected. No real account or user database used.
- Self-review: storage, models, AppState, platform implementations, synchronization and download services remain unchanged. pubspec adds only the existing app icon as a Flutter asset; no dependency or lockfile changes. No commit or release.
