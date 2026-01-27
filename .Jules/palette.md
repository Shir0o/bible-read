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

## 2026-02-14 - Add Friend Form Polish
**Learning:** Single-field forms (like Add Friend) often get overlooked for standard accessibility features.
**Action:** Enforce `TextInputType.emailAddress`, `AutofillHints.email`, and `textInputAction` even for simple, one-off inputs. Added `prefixIcon` for immediate visual recognition.

## 2026-02-18 - Password Visibility
**Learning:** Password fields without a visibility toggle cause user frustration and errors.
**Action:** Always add a toggle `IconButton` with `tooltip` (e.g., 'Show password') in the `suffixIcon` of password `TextField`s.

## 2026-02-19 - Empty States
**Learning:** Default text-only empty states (e.g., "No friends yet") are missed opportunities for engagement.
**Action:** Use rich empty states with an icon, encouraging text, and a primary call-to-action button to guide users.

## 2026-02-21 - Clearable Text Fields
**Learning:** Users often struggle to clear long inputs (like emails) on mobile without a clear button.
**Action:** Implement a `suffixIcon` with an `IconButton` (icon: `Icons.clear`, tooltip: 'Clear') that appears only when `controller.text.isNotEmpty` to allow one-tap clearing.
