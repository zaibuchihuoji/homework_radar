# Homework calendar entry implementation plan

**Goal:** Simplify the homework home screen while preserving calendar, date filtering and homework workflows.

**Architecture:** Replace the inline date bar with a themed entry that opens the existing calendar page. Preserve month and week navigation there, and provide an explicit action to return to the homework list filtered by the selected date; make that filter visible and clearable. Keep the existing five-tab navigation and prior swipe-direction fix.

**Tech Stack:** Flutter, table_calendar, existing theme tokens and widget tests.

**Spec:** User-approved lightweight calendar entry discussed on 2026-10-28.

## Constraints

- Preserve homework and notes data, status/search/sort filters, date filtering, swipe gestures, long-press actions, calendar markers and details.
- Keep the full calendar available in all themes; support existing date ranges and the existing week/month views.
- Do not use subagents or an emulator; run only focused tests and analysis.

## Tasks

1. Write focused failing tests for the entry, navigation, week/month switching, date-filter handoff, clearing, themes and data preservation.
2. Replace the inline date bar with a compact entry and integrate the calendar's explicit date handoff.
3. Verify the calendar, homework gestures, theme layouts and navigation with targeted tests and static analysis.
