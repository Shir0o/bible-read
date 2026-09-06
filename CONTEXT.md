# Bible Read

A group Bible-reading app: people follow a reading plan on their own and alongside a group, mark each day's reading, and see whether the people they read with have shown up too.

## Language

### Reading and marking

**Reading**:
One day's assigned chapters in a plan or a group schedule. The unit that is marked, missed, or caught up on.
_Avoid_: Assignment, lesson, portion

**Shown up**:
Having marked today's reading. The app's framing for the daily habit — presence, not performance.
_Avoid_: Completed, logged, done for the day

**Check-in**:
The full-screen "Did you read today?" moment that opens on launch when today is unmarked. Its sky shifts with the time of day (dawn, day, dusk, night).
_Avoid_: Prompt, daily modal, nudge

**Reflection**:
A short optional note the reader writes about a day's reading, one per day, offered after checking in. Never required, never scored.
_Avoid_: Journal entry, note, comment

### Progress

**Streak**:
Consecutive days a reader has shown up. Breaks on a missed day.
_Avoid_: Chain, run

**Days this season**:
Currently the reader's all-time total of days shown up (`totalReadDays`), despite the wording. **Not** a streak, and not scoped to a Season — see the note below.
_Avoid_: Using this interchangeably with Streak

**Season**:
A bounded period that owns Seasonal Challenges (`SeasonalChallenge.seasonId`). Unrelated to the "days this season" figure on the check-in payoff.

**Behind**:
Having one or more readings whose date has passed and that are still unmarked. Counted as `missedCount`, surfaced as "N readings behind".
_Avoid_: Late, overdue, failing, missed days

**Catch-up**:
Marking a behind reading after its date, in any order and with no penalty. The app treats this as growth, not failure — the UI is gold and gentle, never red.
_Avoid_: Make-up, backfill, recovery

**In step**:
A group state: nothing missed and today's reading marked. The group-side counterpart of being on track.
_Avoid_: Caught up, current

### People and plans

**Reading plan**:
A dated sequence of readings a reader follows personally. Owned by the reader.
_Avoid_: Program, course, track

**Group schedule**:
A group's own dated sequence of readings, separate from any member's personal plan. A reader can be on track in one and behind in the other.
_Avoid_: Group plan (the group's plan and its schedule are distinct)

**Group**:
A named set of readers reading a shared schedule together, with an owner and members.
_Avoid_: Team, circle, cohort

### Read-throughs

**Coverage**:
The set of Bible chapters a reader has marked in the current Lap, unioned across
group schedules and personal reading plans. Coverage is the signal a
Read-Through is detected from. Each reader's coverage only ever changes through
their own marking — a Group schedule is a shared assignment, never shared
marking.
_Avoid_: Progress (already overloaded with plan-day and group-member progress)

**Scope**:
The extent a Read-Through covers: Old Testament, New Testament, or whole Bible.
_Avoid_: Testament (excludes the whole-Bible case), section, portion

**Read-Through**:
A record that a reader finished a Scope end to end, carrying when it happened
and optionally where. Read-Throughs accumulate indefinitely; the count per Scope
answers "how many times have I read this?"
_Avoid_: Completion, finish, cycle

**Lap**:
One pass through a Scope. Only the Old and New Testaments have Laps of their
own, and each resets independently on finishing. The whole Bible has no Lap of
its own — it is derived.
_Avoid_: Cycle, round, iteration

**Derived Read-Through**:
A whole-Bible Read-Through, which is never recorded directly. A reader has read
the whole Bible as many times as they have read the lesser of the two
testaments — three New Testaments and two Old Testaments is two whole Bibles,
with a New Testament left over waiting for its pair.

**Detected Read-Through**:
A Read-Through inferred from Coverage covering the whole of a Scope at the
moment the reader marked the last chapter. The only kind announced socially.

**Backfilled Read-Through**:
A Read-Through the reader entered by hand for a pass finished before or outside
the app. Never announced socially, because it is a claim about the past rather
than an event that just happened. Distinct from Catch-up, which is about
marking a *reading* late and never uses this word.
_Avoid_: Using "backfill" for Catch-up

**Migrated Read-Through**:
A Read-Through granted to an existing reader when Read-Throughs shipped, for
reading they had already finished. Silent, like a Backfilled one.

**Location**:
Free text a reader optionally attaches to a Read-Through saying where it
happened. Deliberately unstructured — "Taipei", "my grandmother's house" and
"the Navy" are all valid.
_Avoid_: Place, venue, geo

**Milestone**:
The public announcement of a Detected Read-Through in the feed. Distinct from
the Read-Through itself, which is private to the reader — one is an event
everyone sees, the other a permanent private record.

**Celebration**:
The full-screen moment shown when a Read-Through is detected. One per marking,
however many Read-Throughs that marking completed.

**Badge**:
A durable award for reaching a Read-Through landmark. Earned once and never
lost, unlike a Lap, which resets.
_Avoid_: Achievement (the Firestore collection keeps that name; the reader-facing
word is Badge), trophy, reward (reserved for Seasonal Challenges)


## Known conflict

The check-in payoff renders `seasonDays` under the label "days this season", but `home_page.dart` passes `_totalReadDays` — an all-time figure. Either the label or the value is wrong. Until that is settled, do not describe that number as a streak or as season-scoped.
