# Palette's Journal

## 2024-05-22 - Initial Setup
**Learning:** Initialized Palette's journal.
**Action:** Will record critical UX/accessibility learnings here.

## 2024-05-22 - LoginForm Accessibility
**Learning:** `TextField` widgets default to `TextInputType.text` and lack autofill hints, making mobile entry difficult.
**Action:** Always wrap forms in `AutofillGroup`. Set `keyboardType` (e.g. `emailAddress`), `textInputAction` (e.g. `next`/`done`), and `autofillHints` (e.g. `email`, `password`) for all input fields.
