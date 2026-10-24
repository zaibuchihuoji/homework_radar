# Home and homework detail polish implementation plan

**Approved direction:** User accepted the recommendation to improve home and homework detail first. Use the calmer settings visual standard, preserve every theme, and keep existing data and sync rules.

**Goal:** Make urgent work easier to find and existing homework operations accessible from detail.
**Architecture:** View-only today filter and compact clean masthead/overview; extract existing note/manual editors into shared dialogs, reuse AppState operations in detail. Detail accepts optional AppState while preserving notification/widget entry fallback.
**Constraints:** No commits, pushes or releases. No subagents or Kimi. No model/storage/service/platform changes. Current release source is clean; work on a local feature branch. Other sync/recognition recommendations are later work.

- [x] Add focused regression tests: today-only filter and return to all retain persisted work; detail edits preserve identity/status/source metadata; platform work cannot edit submission status; hiding is recoverable; enlarged text renders across themes.
- [x] Run new behavior tests to see the missing actions/filter fail, then implement the view filter and reuse editor dialogs.
- [x] Match detail typography, sections, notes and actions to existing themed settings primitives. Keep long titles/deadlines readable and manual/platform distinctions explicit.
- [x] Run relevant navigation/editor/layout regressions and affected-file analysis; inspect diff for domain/storage changes.
- [x] Run a signed release preview build on the independent codex_settings_qa_20261023 emulator, with synthetic records only; view default plus representative distinct themes and retain screenshots in the audit folder. Stop the emulator afterwards and show results.

**Review focus:** Empty today filter must have an exit; undated and non-today work must remain stored; editing must retain item IDs and source fields; external work status is read-only; long text and disabled/cold-entry actions must not overflow.

