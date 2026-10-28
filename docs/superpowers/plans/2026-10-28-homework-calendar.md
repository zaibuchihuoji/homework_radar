# Homework calendar integration implementation plan

**Goal:** Combine homework and calendar under one bottom navigation entry while retaining the existing calendar and theme styles.

**Architecture:** Add a compact themed week/month date bar to the homework screen. Date selection filters the existing list and can be cleared; retain the full calendar as a secondary route for its statistics, legend and detailed view. Remove the calendar bottom tab and adjust dependent indices without changing stored data.

**Tech Stack:** Flutter, table_calendar, existing theme tokens and widget tests.

**Spec:** User-approved expandable date strip discussed in chat on 2026-10-28.

## Constraints

- Preserve homework data, existing filters, search, swipe actions and widget navigation.
- Support all themes and preserve access to calendar month navigation, event markers and old calendar detail.
- Keep undated and other-semester items available through the appropriate views.
- No subagents; run only targeted tests and analysis.

## Tasks

1. Add focused interaction coverage for date selection, clearing, month expansion and five navigation entries.
2. Implement the date bar and integrate it with homework filtering; retain the full calendar as a secondary route.
3. Adjust bottom navigation and any dependent indices, then run focused interaction, theme and navigation verification.
