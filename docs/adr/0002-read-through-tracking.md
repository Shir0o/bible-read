# ADR 0002: Read-Through tracking

- Status: Accepted
- Date: 2026-09-05

## Context

Users wanted to know how many times they have finished the Bible, the Old
Testament, and the New Testament, with a date and an optional location for each
finish. Nothing in the app modelled this. Bible coverage was a single lifetime,
monotonic set of chapters (`BibleProgressService.completedChaptersByBook`),
which by construction can reach 100% exactly once and never again — so "how
many times" was permanently capped at one. Coverage also drew only on group
schedule entries and manually-toggled books, ignoring personal reading plans
(`users/{uid}/plan_progress`) entirely, so a user who finished a 365-day solo
plan showed near-zero coverage.

See [CONTEXT.md](../../CONTEXT.md) for the vocabulary (Read-Through, Lap, Scope,
Coverage, Milestone).

## Decision

**Two counters, not three.** Only the Old and New Testaments have Laps that
reset on completion. The whole-Bible count is derived as `min(OT, NT)` and is
never counted directly. Whole-Bible Read-Throughs are still stored as rows so
they can carry their own date and location, but they hold no Lap of their own.

**Coverage feeds on both reading surfaces.** Personal plan progress now counts
toward Coverage alongside group schedules. Plan progress is credited at day
granularity — completing plan day 47 credits every chapter that day listed —
because personal plans have no per-chapter marking and adding it was out of
scope.

**Detection is client-side, at marking time.** A Read-Through is detected the
moment a user marks the last chapter of a Scope. No Cloud Function is involved,
because a group schedule is a shared *assignment*, never shared *marking* — a
user's coverage can only ever change on that user's own device.

**The private ledger and the public announcement are separate objects.**
Read-Throughs live at `users/{uid}/read_throughs/{id}`, owner-only read. The
social announcement is a `milestone` field on that day's existing
`read_logs/{dateKey}/entries/{uid}` document.

**Only detected Read-Throughs are announced.** Backfilled ones (entered by hand
for reading done before or outside the app) and migrated ones (granted at launch
for coverage already earned) are silent.

## Considered options

- **Auto-detection only, or self-declaration only.** Rejected both. Pure
  detection cannot supply a location or a date for reading done years ago before
  the app existed; pure declaration throws away a signal the app already has.
  Detection proposes, the user confirms and annotates.
- **Three independent Lap counters including the whole Bible.** Rejected: it
  needs a rule for which OT pass pairs with which NT pass. Deriving from `min`
  makes the pairing question disappear.
- **A single global Lap** covering all 66 books. Rejected: a user reading the New
  Testament twice in a row would earn nothing for the second pass until they
  also finished the Old Testament.
- **Keeping the coverage grid lifetime-cumulative** and tracking Laps invisibly.
  Rejected: the grid would sit frozen at 100% for the most engaged users, so a
  whole second pass through the Bible would produce no visible change anywhere.
- **A separate public `milestones` collection** merged into the feed at read
  time. Rejected: piggybacking on the day's read_log entry inherits the existing
  likes and comments subcollections and their rules for free, and keeps the feed
  a single query.
- **Making `users/{uid}/read_throughs` world-readable to signed-in users**, as
  user profile documents already are. Rejected: it would leave backfilled rows —
  which we promised never to broadcast — readable by everyone anyway, and it
  would make free-text locations like "my grandmother's house" public by
  default. The private/public split is enforced by the rules, not by client
  convention.

## Consequences

- A user can see their whole-Bible count increase at the moment they finish *the
  New Testament*, because that is what closed the pair. Celebration copy must
  name the pairing rather than only the trigger.
- At most one Milestone per user per day can be announced, since it is a field
  on a document that is unique per user per day. This is consistent with
  collapsing simultaneous Read-Throughs into a single Celebration.
- Making the Bible Library grid Lap-scoped means existing users' visible
  progress would reset at launch. Migration therefore carries existing coverage
  forward as Lap 1 in progress and grants backdated, silent Read-Throughs to
  anyone already at 100% of a Scope, rather than zeroing anyone out.
- Badges depend on `users/{uid}/achievements/{id}`, which has no rule in
  `firestore.rules` and is currently rejected by default-deny. That must be
  fixed before any badge can be stored.
