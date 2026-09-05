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

## Known conflict

The check-in payoff renders `seasonDays` under the label "days this season", but `home_page.dart` passes `_totalReadDays` — an all-time figure. Either the label or the value is wrong. Until that is settled, do not describe that number as a streak or as season-scoped.
