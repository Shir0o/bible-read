# A Shared plan's schedule is fixed; falling behind is solved per-reader

A reader who falls behind on a Shared plan has two plausible remedies: move the
Group schedule so the dates stop accusing them, or re-date their own copy and
leave the Group's dates alone. The app shipped both, wearing near-identical
affordances — an **Adjust pace** icon on the Path card
(`plans_hub.dart:_adjustSharedPace`) that writes a personal overlay, and a
pencil tooltipped **"Edit plan"** on the Group page
(`group_detail_page.dart` → `EditGroupPage` → `AdjustDaysPage`) that re-dates the
schedule for every member. Neither had a name in `CONTEXT.md`, which is how they
ended up looking like the same button.

**Adjust pace is always personal.** On a Shared plan it writes the reader's own
overlay and never touches the Group schedule or another member's progress.
Re-dating the Group schedule is a separate, owner-only operation with its own
name — **Reschedule** — and its own consequence copy.

## Considered options

- **Anyone can move the Group schedule.** Rejected: one member's bad week moves
  everyone's dates, and it is the member *least* able to judge the cost who is
  most motivated to do it.
- **No owner rescheduling at all** — every reader overlays, the Group schedule is
  immutable after creation. Rejected: a group that collectively agrees to slow
  down should not have to do it one person at a time, and the owner already holds
  the schedule during creation.
- **Personal overlay by default, owner-only Reschedule** (chosen).

## Consequences

- Two members of one Group can be looking at different dates for the same
  reading. This is accepted, and is already true of `Behind`: `CONTEXT.md` records
  that a reader "can be on track in one and behind in the other".
- Progress is stored against the reader's own dates, so a Reschedule after
  members have overlaid is a genuinely hard migration. That is the reversibility
  cost that makes Reschedule owner-only rather than merely discouraged.
- The Group schedule stays the shared reference point — what "In step" is
  measured against. An overlay never changes what the Group is reading together,
  only when this reader is due to read it.
- Reschedule needs consequence copy in the same register as the join-request
  approval screen (ADR-0003): it changes dates for people who are not in the room.
