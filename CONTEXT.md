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

### Progress

**Streak**:
Consecutive days a reader has shown up. Breaks on a missed day.
_Avoid_: Chain, run

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

**Plan**:
A dated sequence of readings, either solo ("On your own") or shared — a Shared plan is a Plan whose schedule a Group follows; nothing else differs. One list (the Path tab) owns the plan lifecycle: enroll, adjust pace, and delete (or leave for group members).
_Avoid_: Group plan (a Group has a Shared plan; it is not a different kind of Plan), program, course, track

**Adjust pace / Reschedule**:
Re-dating a schedule after falling behind or changing the daily reading pace (e.g. from 2 to 3 chapters a day). Keeps all previously completed readings and their dates intact while re-slicing unread chapters starting from today. For solo plans, the reader adjusts their own pace. For a Group plan, the owner reschedules the group for everyone.
_Avoid_: Edit plan

**Guest reader**:
A reader who uses the app without signing in. Has full access to personal plans, daily check-in, streaks, and Bible progress. Upgrades to a full account via Account linking when joining a Group.
_Avoid_: Anonymous user, unauthenticated user, temporary account

**Account linking**:
Connecting a Guest reader's progress to a permanent Google, Apple, or email account. Preserves their existing reading history, streaks, and personal plans.
_Avoid_: Conversion, account upgrade, account migration

**Group**:
A named set of readers reading a single shared schedule together, with an owner and members.
_Avoid_: Team, cohort, and "circle" *as a name for a Group* — a Circle is a different thing (below)

**Circle**:
Everyone a reader shares at least one Group with. A reader in two Groups appears in their Circle once.
_Avoid_: Contact, follower

**Nudge**:
A gentle prompt one reader sends another in their Circle who has not Shown up today. It invites them to read; it never refers to a schedule they are Behind on, and it is not tied to any one Group.
_Avoid_: Poke, reminder, ping

**Feed**:
The stream of updates from a reader's Circle: each person's daily check-in (Shown up) and Milestones. Read only by the author's Circle.
_Avoid_: Timeline, activity, wall

**Amen**:
The one reaction a reader can give a Feed update. There are no comments.
_Avoid_: Like, heart, encouragement (as a noun for the reaction)

### Read-throughs

**Coverage**:
The set of Bible chapters a reader has marked in the current Lap, unioned across group schedules and personal reading plans. Coverage is the signal a Read-Through is detected from. Each reader's coverage only ever changes through their own marking — a Group schedule is a shared assignment, never shared marking.
_Avoid_: Progress (already overloaded with plan-day and group-member progress)

**Scope**:
The extent a Read-Through covers: Old Testament, New Testament, or whole Bible.
_Avoid_: Testament (excludes the whole-Bible case), section, portion

**Read-Through**:
A record that a reader finished a Scope end to end, carrying when it happened. Read-Throughs accumulate indefinitely; the count per Scope answers "how many times have I read this?"
_Avoid_: Completion, finish, cycle

**Lap**:
One pass through a Scope. Only the Old and New Testaments have Laps of their own, and each resets independently on finishing. The whole Bible has no Lap of its own — it is derived.
_Avoid_: Cycle, round, iteration

**Derived Read-Through**:
A whole-Bible Read-Through, which is never recorded directly. A reader has read the whole Bible as many times as they have read the lesser of the two testaments — three New Testaments and two Old Testaments is two whole Bibles, with a New Testament left over waiting for its pair.

**Detected Read-Through**:
A Read-Through inferred from Coverage covering the whole of a Scope at the moment the reader marked the last chapter. The only kind announced socially.

**Migrated Read-Through**:
A Read-Through granted to an existing reader when Read-Throughs shipped, for reading they had already finished.

**Milestone**:
The public announcement of a Detected Read-Through in the feed. Distinct from the Read-Through itself, which is private to the reader — one is an event everyone sees, the other a permanent private record.

**Celebration**:
The full-screen moment shown when a Read-Through is detected. One per marking, however many Read-Throughs that marking completed.

### Account and settings

**Account deletion**:
A reader-initiated, permanent purge of their Firebase Auth identity and personal data (summary, plan progress, and group memberships). Required by App Store Guideline 5.1.1(v) and Google Play policy.
_Avoid_: Deactivation, account wipe, unsubscribe

**Pre-submission assessment**:
An end-to-end verification pass and compliance audit of all app features, states, and store policies performed before submitting a release for review.
_Avoid_: Smoke test, release pass

## Pending the Community/Journey redesign

These are decided but not yet built. Until the work lands, the entries above describe the app as it is. See `docs/community_journey_ia.md`, [ADR-0003](docs/adr/0003-circle-derived-from-groups.md) and [ADR-0004](docs/adr/0004-per-group-reading-feed.md).

- **Reading plan and Group schedule are one term now.** They merged into **Plan** — solo or shared, differing only in who else follows the same schedule (#837, #838, #811). The single creation flow asks who is reading as a field, not a fork; the duplicate "My Reading Plans" page and the new-plan picker sheet are gone. "Group plan" remains a term to avoid.
- **Second pass (2026-09-10).** The first pass added the new surfaces without deleting the old ones, so a Group schedule had seven entrances. Path's plan card now owns the plan lifecycle outright; Circle is people only; the legacy Groups surface, the group detail page and the duplicate schedule and catch-up pages are deleted. See the "Second pass" section of `docs/community_journey_ia.md`.
- **Third pass (2026-10-16).** Circle becomes the Feed (ADR-0011); Path is one page; the avatar menu shrinks to notifications and Settings. Until built, the Circle tab is still the roster. See the "Third pass" section of `docs/community_journey_ia.md`.
- **The three tabs are Today / Circle / Path** (#813). The bar, the wide-layout rail and every user-facing string use the new names; internal class names (`CommunityPage`, `JourneyPage`, the `journey/` widgets directory) may lag. Nothing the reader sees still says "Community" or "Journey".
