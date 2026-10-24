# Focus workbench implementation plan

Selected visual target: third displayed ImageGen board, 聚焦工作台, exec-65cacbba-c7a1-4fd5-a361-c067871067a0.png. User authorized production implementation, other pages/dialogs unified, all functions/data retained, no subagents, necessary verification, real Android run, no commit.

Approach: implement in the existing Flutter app, not a web prototype. Preserve existing uncommitted home/detail/sync/capture work. No new dependencies, storage keys, data migration or sync/merge changes. Use the existing Material outlined icon family with consistent sizes and shared theme tokens. Screenshot preview uses the real chosen file; no generated artwork is needed in runtime.

- [x] Protect initial source state in an external audit archive. Add regressions for today grouping without omissions/duplicates and screenshot preview before review.
- [x] Shared foundation: neutral white/charcoal/yellow for sunny; consistent typography, headers, controls and dialogs; retain all other theme materials/fonts and green palette.
- [x] Home: underline status navigation, header add, yellow today group, compact assignment rows, preserve status/search/course sorting/swipe/long-press. No old overdue, undated or submitted work omitted.
- [x] Detail: compact metadata, deadline band and persistent manual command bar; notes/editor/score/hide/undo and cold routes preserved. Platform submission remains read-only.
- [x] Capture: screenshot/text modes with actual image preview, editable OCR text and optional reference date, recognize then existing editable review/duplicate/final-confirm flow. Picker cancellation/read failure preserve existing draft. Date ambiguity remains unchanged.
- [x] Extend shared visual rules to settings, accounts, calendar, timetable, course/manual editors, login/import/update dialogs. Preserve theme-specific frames and existing actions.
- [x] Focused tests, affected-source analysis, diff review; signed local Android preview installed over synthetic QA data in codex_settings_qa_20261023 only. Run primary flows and representative themes, compare actual app with selected board, save screenshot preview and QA report. Do not commit or publish.

Review focus: large text narrow width; yellow text contrast; no hidden or duplicated homework; no local submission changes for platform work; no accidental save before confirmation; all destination/actions still reachable. Mock screenshot-source thumbnail becomes a real local image preview, not a decorative asset. Existing filters/overdue groups and score/hide actions not shown in mock remain available.
