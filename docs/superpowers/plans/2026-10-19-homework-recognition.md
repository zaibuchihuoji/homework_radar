# Homework Recognition Implementation Plan

User-approved scope: add Recognition under +, screenshot and paste, editable course/title/deadline, multi-select preview, ambiguity warnings, duplicate warning, explicit final confirmation, no old-data loss. Inline execution only, no subagents.

Architecture: local ML Kit OCR (existing dependency), pure conservative text/date parsing, transient review drafts, append-only batch storage transaction. No network or new dependencies.

1. [x] Add parser/date/duplicate tests first. Support explicit course labels and known course names, numbered or separated tasks, clear date/time only. Relative dates and missing years require an explicitly chosen notice date; ambiguous bare weekdays, missing times, conflicting/invalid dates stay unset. Keep source text.
2. [x] Add append-only storage and AppState batch tests: validate selected rows, one transaction/write, unique manual IDs, recheck duplicates, preserve hidden/all prior JSON rows including unknown fields, rollback write failures, distinguish committed data from reminder/widget refresh failure.
3. [x] Implement local OCR and themed input/review UI. + offers manual and recognition; screenshot OCR or clipboard input creates editable drafts. Duplicate drafts default unchecked. Confirmation states missing fields/duplicates. Disable double save; cancel never adds data.
4. [x] Run only parser, append, affected manual entry and new page widget checks; targeted analyze, release build. Android synthetic-device smoke: screenshot recognition, text recognition, edit/select/duplicate/confirm, compare existing data unchanged; restore fixture data.

Ruling: no cloud AI or account data changes. Unclear input remains visible for review, not silently discarded. Existing manual editor semantics stay unchanged. Source selections never commit automatically.
