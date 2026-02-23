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

## 2026-02-23 - Feedback Form Polish
**Learning:** Multiline text inputs (like descriptions/steps) benefit significantly from 'Clear' buttons and sentence capitalization.
**Action:** Use `TextCapitalization.sentences` for free-text fields. Implement dynamic `suffixIcon` clear buttons for multiline inputs using controller listeners.

## 2026-02-26 - Scrollable Centered Empty States
**Learning:** To center content in a `RefreshIndicator` while keeping it scrollable (for pull-to-refresh), `ListView` can be restrictive.
**Action:** Use `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: constraints.maxHeight)` to center content while ensuring physics work.

## 2026-02-27 - Social Input Polish
**Learning:** Chat-like inputs should grow with content but have a maximum height to preserve context.
**Action:** Use `minLines: 1`, `maxLines: 4`, and `TextInputType.multiline` for inline comment fields, combined with `TextCapitalization.sentences`.

## 2026-03-01 - Social Login Accessibility
**Learning:** Icon-only social login buttons are invisible to screen readers without explicit labels.
**Action:** Wrap icon-only `InkWell` buttons in `Semantics(button: true, label: 'Sign in with X')` and include a `Tooltip` for mouse users.

## 2026-03-02 - Date Picker Accessibility
**Learning:** `GestureDetector` on input fields provides no visual feedback (ripple) and poor accessibility (no 'button' trait).
**Action:** Wrap tappable `InputDecorator` fields in `Semantics` (button: true) + `InkWell` (with matching border radius) for better touch feedback and screen reader support.

## 2026-03-03 - Group Member List Accessibility
**Learning:** Complex list items (Avatar + Text + Icon) are fragmented for screen readers, requiring multiple swipes per item.
**Action:** Wrap the entire list item `Row` in a `Semantics(container: true, label: "...")` widget to aggregate the information into a single, cohesive announcement. Exclude child semantics to reduce noise.

## 2024-05-22 - Nested Interactive Elements
**Learning:** Avoid nesting `InkWell` widgets or buttons inside other interactive elements like cards. It creates confusing semantics (buttons inside buttons) and unpredictable gesture behavior.
**Action:** Always structure interactive lists or cards so that secondary actions (like 'Like' or 'Comment') are siblings to the primary tap target, not children. Use `Semantics(excludeFromSemantics: true)` on inner `InkWell` widgets if wrapping them with a custom `Semantics` node to prevent duplicate accessible nodes.

## 2026-03-04 - Custom Radio Button Accessibility
**Learning:** Custom selection cards (e.g., Frequency) built with `InkWell` are inaccessible unless explicitly marked as radio buttons.
**Action:** Wrap custom radio widgets in `Semantics(checked: isSelected, inMutuallyExclusiveGroup: true, button: true, label: ...)` and verify states with screen reader tests. Add haptic feedback for better interaction.

## 2026-03-05 - Calendar Accessibility
**Learning:** Dense grids (like calendars) often have tiny touch targets (e.g., 12px icons) that are hard to explore with screen readers.
**Action:** Enforce accessible touch targets (min 48x48dp) using `Container` constraints inside `Semantics` wrappers, even for non-interactive status indicators, and allow layout to flex to fill available width.

## 2026-03-06 - Misleading Interactivity & Tooltips
**Learning:** List items that look tappable (ripple effect) but do nothing create confusion. Also, FABs must have tooltips for accessibility.
**Action:** Use `CommonStyles.buildCard` (without InkWell) for non-interactive items. Ensure every `FloatingActionButton` has a `tooltip`.
