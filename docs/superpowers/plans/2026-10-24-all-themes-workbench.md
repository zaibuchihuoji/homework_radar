# All themes workbench layout

**Goal:** Apply the approved sunny workbench's page hierarchy, controls and spacing to every app theme while retaining their palette, typography and material details.

**Approach:** Reuse the current workbench widgets for all themes. Remove obsolete alternative page structures rather than changing persisted theme flags or forcing a sunny palette. Existing business actions, data models, storage and native widgets stay unchanged. Keep the pending activity-icon changes.

**Scope:** Home and homework rows/detail; timetable and course details; calendar; account list/details; settings and detail introductions; recognition/import/setup screens; app-owned forms/dialogs. Preserve the existing theme-specific navigation indicators and native widget visuals.

**Validation:** Widget regression covering every theme and the common page landmarks, narrow enlarged text, course/detail actions, and unchanged stored homework/course/hidden data. Analyze touched source and run affected UI tests. Inspect actual rendered Flutter screens in representative themes using isolated preview data. No new release or commit requested.

- [x] Shared workbench surfaces retain theme texture and typography without changing information positions.
- [x] Main page templates use the same header actions, filters, today group, weekly/day switch, calendar and account grouping.
- [x] Details, settings and import/recognition layouts use the approved workbench structure.
- [x] Necessary regression and rendered UI checks pass; data paths remain untouched.
