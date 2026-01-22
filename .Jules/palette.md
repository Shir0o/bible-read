# Palette's Journal

## 2024-05-22 - Initial Setup
**Learning:** Initialized Palette's journal.
**Action:** Will record critical UX/accessibility learnings here.

## 2024-05-22 - LoginForm Accessibility
**Learning:** `TextField` widgets default to `TextInputType.text` and lack autofill hints, making mobile entry difficult.
**Action:** Always wrap forms in `AutofillGroup`. Set `keyboardType` (e.g. `emailAddress`), `textInputAction` (e.g. `next`/`done`), and `autofillHints` (e.g. `email`, `password`) for all input fields.

## 2026-01-21 - Signup Form Accessibility
**Learning:** Wrapped forms in `AutofillGroup` and configured `TextField`s with `keyboardType`, `autofillHints`, and `textInputAction` to improve keyboard navigation and password manager support.
**Action:** Always check form fields for these properties during reviews or when creating new forms. Use `dart format` if `flutter format` is unavailable.

## 2026-01-24 - Friends List Accessibility
**Learning:** Icon-only buttons (like "Nudge") in lists are ambiguous to screen readers. Context matters: "Send encouragement" is okay, but "Send encouragement to Alice" is better.
**Action:** Use `Semantics` with a dynamic `label` property to provide context-aware descriptions (e.g., including the item name) for actions in lists.
