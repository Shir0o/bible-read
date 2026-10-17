# The Circle tab is the Feed; group actions live behind its action slot

_Settled 2026-10-16._

The Circle tab is the **Feed**: a row of today's status across the reader's
Circle (with Nudge for anyone who has not Shown up), above a seven-day stream of
updates (each person's day with any shared Reflection, Milestones, Badges)
that readers react to with **Amen** only. Joining, creating and sharing a code
for a Group, and opening a Group's page, sit in one sheet behind the tab's
action slot. This reverses the 2026-09-10 second pass's "Circle is people only"
roster, which left a reader who already had a group with nowhere on the social
tab to invite or join, and gave the "encouraged by what others did" purpose from
the 2026-09-05 review no surface. The data already exists: the per-Group daily
entries, likes and badge mirrors of ADR-0004.

## Considered options

- **Roster, improved** (the second pass): rejected — status only, no updates,
  and still no home for group actions once a reader has a group.
- **Groups as rooms**, people inside each Group: rejected — reintroduces a
  group destination, the conceptual bug the second pass removed.
- **Feed with a status row** (chosen).

## Consequences

- Threaded comments stay dropped (2026-09-05); Amen is the only reaction.
- The Feed is bounded to today plus the last seven days, newest first.
- The Group page is reached from Circle's action sheet as well as from the Path
  card's "Manage members" — one page, two doorways.
- Badges come from a per-Group badge log, `groups/{g}/badge_log/{uid}_{badgeId}`,
  which the badge-awarding function writes once per award (the latest-badge
  mirror alone dropped earlier badges of the week). Each Badge is its own
  update with its own `likes`, so a Badge Amen never lands on the day's entry.
  The log is keyed by award, not by day: the server does not know the reader's
  local date, so the client places it by `dateUnlocked`.
- Amens are live: the Feed listens to the `likes` of each update in its week
  and drops a listener once its update leaves.
