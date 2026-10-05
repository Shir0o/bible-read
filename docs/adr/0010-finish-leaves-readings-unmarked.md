# Finishing a plan early leaves its unread readings unmarked

A Plan whose dates have ended but still has unread readings stays on Home
indefinitely — the app never auto-closes a plan just because its window ran out.
Readers needed a way to say "I'm done with this one" without reading every last
day. We added **Finish**: a personal action that moves the Plan to Path's
Finished list (shown as "Finished · 208 of 260 read") and leaves the remaining
readings unmarked.

## Considered options

- **Archive it.** Rejected: Archive means shelved, not done — the plan would sit
  beside abandoned ones rather than in Finished.
- **Mark the remaining readings read**, so the plan completes on its own.
  Rejected: Coverage only changes through a reader's own marking of what they
  actually read, and bulk-marking unread chapters could fire a Read-Through the
  reader never earned.
- **A Finish state that leaves readings unmarked** (chosen).

## Consequences

- "Finished" no longer implies "every reading marked". Code that needs the
  latter must check the readings, not the list a plan sits in.
- On a Shared plan, Finish closes only the reader's own participation, in line
  with ADR-0007's "reader actions are personal" — the Group schedule and other
  members carry on.
- Path owns the plan lifecycle, but Home's "Plan ended" card carries a Finish
  shortcut too, because that card is where the lingering plan is felt.
