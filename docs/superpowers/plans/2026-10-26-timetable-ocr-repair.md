# Timetable OCR repair implementation plan

Implement inline without subagents. Preserve storage formats, import confirmation,
default union merge, account isolation and existing course edits. Do not commit.

- [x] Reproduce wrong single-section mapping, lost lower courses, short weekday
  headers and silently accepted unknown editor fields in targeted tests.
- [x] Parse explicit section ranges and single-section axes; keep ambiguous axes
  provisional and offer an explicit single/paired interpretation. Preserve text
  outside known axis coverage as unselected candidates.
- [x] Require explicit missing weekday/section/week values in the shared editor;
  retain normal defaults for manually added courses.
- [x] Keep OCR drafts and corrections for retry, expose original-image comparison
  and review counts, and enforce image-size limits for tall inputs.
- [x] Run focused parser/editor/import/data-preservation regression tests and
  analyzer; run the updated native flow on the isolated QA emulator. No release.

Ruling: short bare numeric axes remain provisional in auto mode. Explicit ranges,
single-section labels, or an axis extending beyond eight within the supported
1–16 periods can resolve the mapping; users can select single/paired mode without
rerunning OCR. Reinterpreting a manually corrected draft requires confirmation.

Evidence: audit-artifacts/20261026-timetable-ocr-fix (outside the repository).
77 related regressions passed; the final focused run passed 13 tests including
one additional axis/draft-cancellation scenario. Analyzer clean. Native QA
confirmed periods 3/10, original-image viewing, unknown-week blocking, edited
candidate import and preservation of the two existing courses. No commit/release.
