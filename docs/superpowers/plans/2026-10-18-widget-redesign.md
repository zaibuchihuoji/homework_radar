# Desktop widgets implementation plan

Goal: implement the approved yellow-white homework / timetable widgets, preserving transparency, old caches and all business data. Execute inline without subagents as requested.

Design: the in-chat recommendation approved on 2026-10-18 and `../audit-artifacts/20261018-widget-design-audit/review.md`.

Constraints: reuse RemoteViews and home_widget; no new dependencies, no storage migrations, no assignment limit, no completed filler, no destructive data writes. Keep old tt_json and items_json readable. Keep this dirty checkout intact; do not commit unrelated changes.

1. [x] Write and run regression tests for overdue / undated / unknown assignments, >20 items, exact IDs and source immutability. Extract a snapshot builder and publish an atomic versioned cache with legacy keys retained.
2. [x] Test native cache readers, size calculation, short time labels and timetable focus across end-time / day / week boundaries. Rebuild both RemoteViews, shared yellow-white / glass styling, readable rows, honest timestamps and matching previews. Small widgets change content density, never shrink text to 9sp or hide classrooms. Lists remain scrollable.
3. [x] Test valid / invalid widget destinations, initial-launch race, splash delay and warm clicks. Add explicit activity PendingIntents with safe mutable list templates and per-row IDs. Resolve visible records only; deleted / hidden / account-switched IDs return to the list.
4. [x] Run full Flutter tests, analysis, native unit tests and release build. Upgrade the dedicated synthetic-data AVD, verify source records unchanged, inspect both widgets on its actual launcher in small / default / large sizes, transparent / white modes and large fonts; verify cold / warm clicks and multiple instances. Save screenshots, delivery APK and verification report, then shut down the dedicated AVD.

Review focus: old snapshots without IDs; overdue deadlines at exactly now; large datasets without truncation; unknown course times; orientation and font scale; stale links after hiding or switching accounts. Failures must preserve original source data. Use a separate author review pass, honoring the no-subagent instruction.
