# Bible Read

A Flutter app for tracking daily Bible reading, individually and in groups. This
glossary fixes the language of the domain; it is not a spec.

## Reading

**Marking**:
The act of a user recording that they read something — a chapter in a group
schedule, or a day in a personal reading plan. Each user marks only their own
reading; a group schedule is a shared assignment, never shared marking.
_Avoid_: Checking off, logging (collides with the Read Log feed)

**Coverage**:
The set of Bible chapters a user has marked read in the current Lap, unioned
across group schedules and personal reading plans. Coverage is the signal a
Read-Through is detected from.
_Avoid_: Progress (overloaded with plan-day and group-member progress)

## Read-Throughs

**Scope**:
The extent a Read-Through covers: Old Testament, New Testament, or whole Bible.
_Avoid_: Testament (excludes the whole-Bible case), section, portion

**Read-Through**:
A record that a user finished reading a Scope end to end, carrying when it
happened and optionally where. A user accumulates Read-Throughs indefinitely;
the count per Scope is the answer to "how many times have I read this?"
_Avoid_: Completion, finish, cycle

**Lap**:
One pass through a Scope. Only the Old and New Testaments have Laps of their
own, and each resets independently on finishing. The whole Bible has no Lap —
it is derived (see Derived Read-Through).
_Avoid_: Cycle, round, iteration

**Detected Read-Through**:
A Read-Through the app inferred from Coverage reaching the whole of a Scope at
the moment the user marked the last chapter. The only kind announced socially.

**Derived Read-Through**:
A whole-Bible Read-Through, which is never read directly. A user has read the
whole Bible as many times as they have read the lesser of the two testaments —
three New Testaments and two Old Testaments means two whole Bibles, with a New
Testament left over waiting for its pair.

**Backfilled Read-Through**:
A Read-Through the user entered by hand for a pass that happened before or
outside the app. Never announced socially, because it is a claim about the past
rather than an event that just happened.

**Migrated Read-Through**:
A Read-Through granted to an existing user at the moment Read-Throughs shipped,
for reading they had already finished. Silent, like a Backfilled one.

**Location**:
Free text the user optionally attaches to a Read-Through saying where it
happened. Deliberately unstructured — "Taipei", "my grandmother's house", and
"the Navy" are all valid.
_Avoid_: Place, venue, geo

## Recognition

**Milestone**:
The public announcement of a Detected Read-Through, shown in the feed. Distinct
from the Read-Through itself, which is private to the user — one is an event
everyone sees, the other is a permanent private record.

**Celebration**:
The full-screen moment shown when a Read-Through is detected. One Celebration
per marking, however many Read-Throughs that marking completed.

**Badge**:
A durable award for reaching a Read-Through landmark, shown on the user's
profile. Earned once and never lost, unlike a Lap, which resets.
_Avoid_: Achievement (the existing collection name is retained, but the
user-facing word is Badge), trophy, reward (reserved for seasonal challenges)
