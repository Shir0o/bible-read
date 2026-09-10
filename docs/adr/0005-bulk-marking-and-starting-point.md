# ADR 0005: Bulk marking and Starting point

- Status: Accepted
- Date: 2026-09-09

## Context

Three gaps in the marking experience:

1. **Undo is last-mark-only.** Every mark-as-read toggle shows its own Undo
   SnackBar, and each new mark hides the previous one (`hideCurrentSnackBar`
   first). Rapidly marking several readings leaves only the last mark
   undoable — the earlier ones are silently committed. The toasts also sit at
   the screen bottom, covering the "Enroll in a new plan" button at the bottom
   of the Path tab's plan list.

2. **No month-level marking.** The shared schedule view already groups days by
   month (`_buildMonthRule`), but there is no way to mark a whole month of
   readings at once. A reader who fell behind for a month must tap every day.

3. **No way to enter a starting position.** A reader migrating an existing plan
   from elsewhere has no way to say "I've already read up to X". Backdating the
   start date shifts the schedule but marks nothing; the only position input in
   the app is the group plan's `startRef` chapter picker.

See CONTEXT.md for vocabulary (Shown up, Catch-up, Coverage, Backfilled
Read-Through, Starting point).

## Decision

**Burst undo.** Marks made in quick succession coalesce into one floating
SnackBar — "N readings marked — Undo" — whose timer resets on each mark. One
Undo reverts the whole burst, restoring the exact pre-burst state: plan days
un-mark *and* today's habit write undone if the burst caused it (the
reading→habit coupling is part of the burst transaction). The coupling's
follow-up message is suppressed during bursts; the habit write still happens,
silently and idempotently.

**Month marking.** A month-header action on the shared schedule view marks every
unmarked day in that month up to and including today. Future days are never
marked. No confirm dialog — the burst undo is the safety net. Personal plans
only; group surfaces keep day-by-day marking.

**Starting point.** At plan creation, the reader may enter "I've read up to
[chapter]" via a chapter picker (reusing the group `startRef` pattern). The
plan's start date shifts so the day containing that chapter lands on today;
days 1..N are marked; duration is preserved. Any Read-Through the marks
complete is silent, like a Backfilled Read-Through — never a Milestone.

## Considered options

- **Per-mark toasts (status quo).** Rejected: last-mark-only undo, stacking,
  and the reported overlap.
- **Undo only the last mark of a burst.** Rejected: "I didn't mean to do that
  spree" is the real failure mode; re-marking the rest is cheap.
- **Marking every day in the month including future ones.** Rejected: "Shown
  up" is presence on the day; future days cannot be shown up for. Marking
  ahead is the Starting point's job.
- **Starting point as day number or date.** Rejected: day numbers don't
  transfer across plans (different chapters-per-day); a migrating reader knows
  what they read — chapters — not this plan's internal numbering.
- **Starting point as mark-only (schedule frozen).** Rejected: leaves the
  reader ahead with future days marked, which the app otherwise forbids
  (forward-only toggles).
- **Month marking on group surfaces.** Rejected: group schedules are shared
  assignments; bulk-marking a month is a bigger social claim, and the month
  seam doesn't exist there.

## Consequences

- The burst undo writes to two surfaces (plan progress + habit) when coupling
  is on; the rollback machinery exists per-surface and composes.
- A Starting point can silently complete a Read-Through via Coverage credit
  (ADR-0002: plan progress credits coverage at day granularity). It must
  never be announced — same rule as Backfilled Read-Throughs.
- The "Enroll in a new plan" button moves from the bottom of the active plan
  list to the top, right under the header; the archived-list copy stays where
  it is, contextual to that section.
- All marking toasts become floating with a bottom margin, so no marking toast
  can cover bottom-anchored controls on any screen.
