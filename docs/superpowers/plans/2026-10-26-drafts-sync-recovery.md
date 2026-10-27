# Drafts, sync details and local recovery

> Execution: implement inline without subagents; leave changes uncommitted.

## Approved scope and design

The user accepted the three recommended improvements: recognition drafts, meaningful sync results, and data recovery. Preserve all themes, existing features, account isolation, old data and existing backup compatibility. Use existing Flutter components and storage, without new dependencies or cloud services.

### 1. Recognition drafts
- Keep source text, notice date, image preview reference, edited rows, explicit unknown dates and selection locally.
- Returning from review and reopening the page/app resumes the same edits. Changing source text/date invalidates old parsing rather than silently applying edits to unrelated input.
- Recheck duplicates against current data. Saving still requires final confirmation. Clear the draft only after a successful save; draft cleanup failure must not invite duplicate saving.
- A visible discard action clears only the draft, never saved homework.

### 2. Sync result details
- Persist per-platform factual added/changed/retained/archive counts and confirmed course-level failures.
- Derive counts from the committed merge, retaining existing identities and notes. Unknown failure causes stay unknown. Existing retry and last-success behavior remains.
- Present counts and actionable information using existing themed sync components. Old saved statuses remain readable.

### 3. Local recovery
- Add a manual-homework recycle bin; deletion and restore are journaled transactions, with ID collision protection and refresh of widgets/reminders.
- Keep up to seven local restore points, captured daily when local data is nonempty and before backup restoration. Never include credentials, raw network logs or recognition input.
- Preview backup counts and ownership handling before restore. Reuse the existing validated atomic import and account isolation policy, including read-only archiving for imported records of logged-in platforms.
- Retain existing hidden-work and account-archive flows. Recovery points are local only and do not protect against uninstall/device loss; keep external export available.

## Approach

Extend existing services and focused UI pages. Avoid a new database or cloud synchronization: they expand migration and ownership risk without being required for these local features. Work in the existing clean feature checkout to preserve its configured build and isolated QA environment; do not commit, publish, spawn agents or launch the user's daily emulator.

## Tasks and checks

- [x] Task 1: Add failing recognition round-trip/persistence tests; implement a versioned draft model/store and capture/review integration. Verify edited text, cleared deadline, unchecked row, changed source, restart, discard and successful save.
- [x] Task 2: Add failing result-summary merge/status tests; derive committed counts and confirmed course failures, persist and show them. Verify partial sync preservation, no-change sync, hidden records, platform identity collisions, old metadata and account reset.
- [x] Task 3: Add failing recovery tests; implement transactional manual recycle bin, bounded local backup points, import preview and recovery UI. Verify same-ID conflict, failed writes, restore rollback, corrupt backups, current-account isolation and old backup compatibility.
- [x] Task 4: Run affected regression tests and analyzer; broaden only for storage/merge concerns. Build once and exercise the three flows in the dedicated headless QA AVD with synthetic data; inspect screenshots, preserve baseline data and close the AVD. Record remaining device-only limits.

## Progress

- Baseline: clean `feat/home-detail-polish` at `e096a44` (1.3.2+11). No applicable AGENTS.md found. No implementation yet.
- Task 1 implemented: review edit/selection/date retention, new-source invalidation, reopen and discard checks passed.
- Task 2 implemented: factual committed diff counts and confirmed course failures, persisted optional summaries; 33 merge/scope/theme checks passed.
- Task 3 implemented: versioned compressed local points (7 / 8 MiB), atomic raw-preserving manual recycle operations, backward-compatible backup preview/restore. Rollback, ID conflict, account isolation and opaque-record cases covered.
- Final verification in progress. Initial full-suite run identified two test updates: structural map comparison and the intentionally changed file-picker-first import flow. No commits made.
- Full regression: 973 tests passed; analyzer clean. Signed x86_64 build installed over existing QA app; recognition edits/selection survived a real process restart; recycle deletion and restore and backup preview worked with original records retained.
- User added timetable daily-list swipe defect during verification. Reproduced natively: right swipe changed week 9 to week 8 but kept Monday and the same course. Added two failing regression tests, separated daily (210 day pages) from weekly (30 week pages) paging, and passed 26 focused timetable/theme/recovery UI checks. Final native retest pending.
