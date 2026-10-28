# Notes filter picker implementation plan

**Goal:** Improve the course and chapter pickers without changing note data or filtering behavior.

**Architecture:** Preserve the original filter controls and anchored popup menus. Use a short transition, position menus below the controls, and replace Flutter's full-width selected highlight with a checkmark; preserve category ordering and selection behavior.

**Tech Stack:** Flutter, existing theme palette and widget tests.

**Spec:** User-provided screenshots and request on 2026-10-28.

## Constraints

- Preserve note contents, attachments, history and existing workspace changes.
- Support every theme, narrow screens, large text, long names and empty categories.
- Do not use subagents or an emulator; run focused tests and visual checks.

## Tasks

1. Add focused tests for anchored menus, selection marks, category selection, cancellation and note data invariance.
2. Implement the shared themed popup without changing the surrounding layout or filter logic.
3. Verify theme variants, long lists, reduced motion and regression tests.
