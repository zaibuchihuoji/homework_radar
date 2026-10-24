# Sync status and recognition polish

User explicitly requested continuing the approved home/detail visual direction, all themes, no functional/data regressions, no subagents, necessary checks and actual Android run, no commits.

Design: reuse SettingsScaffold/Section materials and typography. Home sync notice stays compact with access to details. Sync page distinguishes persisted complete success, retry, expired login and rejected signature, with separate attempt/success times. Recognition keeps the existing parser, draft selection, duplicate checking and final confirmation; improve source actions, optional reference date, editable review cards and fixed primary actions.

Architecture: presentation components only, existing state and service calls retained. No changes to AppState, models, services, native platform code, dependencies or persisted keys. Continue current local branch with previous uncommitted home/detail changes intact.

- [x] Implement themed sync status presentation and details entry; test status meanings and progress separately from success.
- [x] Restyle capture/review/confirmation using shared theme primitives, preserving keys and action semantics.
- [x] Run existing recognition parser/save/page tests plus focused sync/layout regressions and affected-file analysis.
- [x] Build local signed preview, install over QA records in dedicated codex_settings_qa_20261023 emulator; exercise text and screenshot recognition through review and cancellation/save. Inspect default and representative themes. Show actual screenshots.

Review focus: unknown dates stay unset; duplicate defaults remain unchecked; saving still requires confirmation; busy state prevents repeat submission; small width/large text and every theme retain usable controls; no successful-looking sync result is invented without persisted success.

