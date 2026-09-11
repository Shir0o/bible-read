# Community / Journey IA — decisions before the visual redesign

_Settled 2026-09-05. Outcome of a design review prompted by watching a new user
fail to find how to join a group, invite others, or create a group._

Vocabulary in this document is the vocabulary in [CONTEXT.md](../CONTEXT.md).
The friend-graph removal has its own record in
[ADR-0003](adr/0003-circle-derived-from-groups.md).

## The diagnosis

The complaint was "it's hard to find where to do something." Three causes, in
order of how much damage they do:

1. **"Plan" meant three things.** A personal reading plan, a Group whose
   schedule was also called a plan (the pencil in `GroupDetailPage` is tooltipped
   "Edit Group Plan"), and the schedule itself. Creation was forked behind a
   modal (`showNewPlanPicker`) that made the user pick a taxonomy before they
   knew what they wanted.
2. **Actions were scattered and unlabelled.** Seven entry points to create a
   plan across three surfaces; the strongest one on the tab named after the
   user's reading journey was a `TextButton` reading "Manage". **Two different
   pages were both titled "My Reading Plans"** — `AllPlansPage` (good, from
   Home) and `ReadingPlansPage` (archive/delete only, from Journey) — reachable
   from different tabs with different capabilities under an identical heading.
3. **Two social graphs.** Friends and Groups, already crossing in code, with no
   way to tell which one connected you to the people you actually read with.

And one thing that was not a discoverability problem at all: **inviting someone
who wasn't already an app user was impossible.** The only outside path copied
the string `Join my group: <firestore doc id>` to the clipboard, and the app has
no deep-link handling of any kind to receive it.

## Decisions

### Model

- One **Plan** concept. A **Shared plan** is a Plan whose schedule a Group
  follows; nothing else differs. "Solo or with others" becomes a field inside
  plan creation, not a fork before it.
- **Progress** is always per-person, never pooled — and every member of a Group
  can see every other member's.
- **Circle** replaces Friends entirely: everyone you share a Group with. Group
  is the only relationship primitive. See ADR-0003.
- **Nudge** is person-to-person, not tied to a Group. `nudgeFriend` →
  `nudgeMember`.

### Navigation

- The bottom bar **stays** — three tabs, relabelled **Today / Circle / Path**,
  per the design bundle's register.
- What is generic is the execution, not the pattern: stock Material 3 pill
  indicator, default height, and `Icons.map` for Journey. Custom line glyphs and
  a restrained indicator on the existing warm-paper palette.

### Today

- Owns the daily reading outright. The reading hero leaves Circle.
- Keeps the two glimpses into Circle and Path, re-sourced from Group members
  now that friends are gone.
- Loses its plan-creation entry points to Path.

### Circle

Purpose, in the user's words: *tap the nav, see everyone I'm connected to and
what they've been doing, so that I'm encouraged.*

- **People-first**: one flat list of everyone in your Circle. Groups are
  secondary — a filter or a section beneath.
- Each person shows **today's status**, their **Progress**, an optional
  **Reflection**, and their **latest achievement**.
- Loses `CommunityReadingHero` entirely.
- The "Manage" `TextButton` is replaced by labelled actions: **Join a group**,
  **Create a group**, and per-group **Share code**.
- **Any member can invite**, not just the owner.

#### Reflections — per-entry opt-in

Reflections are private today, by explicit decision: `reflection.dart` calls it
"a user's private journal entry" and `firestore.rules:135` reads
`// Private daily journal entry — never readable by anyone but the owner`.

That stays the default. The reflect sheet gains a **"share with your circle"
toggle, default off**, decided at the moment of writing, while the person is
looking at the actual words. Not a global setting: consent given once and
forgotten is how a hard day's entry ends up in front of strangers — and under
ADR-0003 the Circle is auto-derived, so a group owner approving a join request
would otherwise be publishing someone else's journal on their behalf.

#### The feed already exists

`read_logs/{date}/entries/{userId}` is commented `// 🌐 Public reading feed` in
the rules, is written on every read, carries `likes` and `comments`
subcollections, and has `sendLikeNotification` / `sendCommentNotification`
cloud functions behind it. `ReadLogView`'s like action already toasts
**"Encouragement sent"**.

Nothing renders it. `readLogPageBuilder` is threaded `MainPage` →
`CommunityPage` and marked "Optional builder kept for compatibility", unused.
The app has been writing to a feed no one can see.

**Revive it as the Circle tab** rather than building fresh. This knowingly
reverses the Circle redesign's removal of Friends Activity
([design_diff.md](design_diff.md)). Two changes required:

- Scope reads to the Circle by **denormalizing entries per Group** — see
  [ADR-0004](adr/0004-per-group-reading-feed.md). The current rule is
  `allow read: if request.auth != null`, so every signed-in user can read
  everyone's feed today; that is a live privacy hole, not just a redesign gap.
- Drop threaded comments (see below), with their model, rules, and function.

#### Encouragement — Amen and Nudge

**Amen** (one tap, celebrates someone who read) and **Nudge** (reaches someone
who hasn't). `nudge_sheet.dart` already exists with written copy.

A Nudge is **not tied to a Group**. It means "come and read", not "you are
behind on our schedule". The code already assumes this: `NudgePerson` is
documented as working "for friends, community entries, and group members
alike", `kNudgePresets` as "a soft tap on the shoulder — never a reminder of
what someone missed", and nudges are stored at `users/{uid}/nudges/{recipientId}`
with no group dimension. Consent is unchanged either way, since a Circle is
exactly the union of your co-members.

**Threaded comments are dropped.** They turn a quiet encouragement surface into
a place with unread replies and social obligation, which is against the app's
voice everywhere else.

#### Achievements — currently non-functional

`users/{uid}/achievements/{id}` exists with `dateUnlocked` timestamps, and is
written in exactly two places: `nt_starter`
(`bible_progress_page.dart:267` — actually awarded for your *first book*, not
the NT) and `firstReader` (`read_log_page.dart:92`). Nothing reads them.

There is **no rules block for the subcollection** and no `{document=**}`
anywhere in `firestore.rules`, so Firestore denies by default — both writes have
been silently failing behind their `catch (_) { // Best-effort }`. "Finished the
NT" and "read 50 days" do not exist in any form.

> **Partly superseded on main (2026-09-06).** #782 added a rules block for the
> achievements subcollection, so writes are no longer denied — but it grants
> `read, write` to the owner, which fixes the denial while leaving the client able
> to grant itself a Badge. The remaining work is to tighten it to co-member read and
> server-only write. Separately, #784 shipped Read-Throughs and Badges, which already
> cover the completion family below (a book, the NT, the OT, the whole Bible); the
> catalogue here should defer to that rather than duplicate it, and the reader-facing
> word is **Badge**, not achievement.

Achievements are **awarded server-side by Firestore triggers** on `bible_books`
and read-log writes. A client must not be able to grant itself a trophy, and the
existing client-side attempt is already broken. The missing rules block is
required either way.

The catalogue is three families, all derivable from data that already exists:

| Family | Source | Examples |
|---|---|---|
| Completion | `bible_books` | finished a book, the NT, the OT, the whole Bible |
| Consistency | streak summary | 7, 30, 50, 100, 365 days |
| Plan | `UserPlanProgress` | finished a Plan |

**No social achievements.** `firstReader` already exists and rewards being early,
which quietly makes the habit competitive in an app whose copy insists it is not.
Retire it.

Naming bug to fix in passing: `nt_starter` is titled "NT Starter" but fires on
your first completed book, whatever it is.

### Path

- **Owns the plan lifecycle.** `AllPlansPage` — which already merges personal
  and group plans into one list — moves inline and becomes the tab. The stat
  tiles and consistency calendar sit below it.
- Editing a Plan means **adjusting pace only**, reusing the existing
  `AdjustDaysPage` that Groups already have. Full mid-flight editing of books or
  structure is out of scope: "edit my plan" in practice means "I've fallen
  behind and want the schedule to stop shaming me."

### Joining and inviting

- **Join codes**: a short, human-typable code per Group, plus a "Have a code?"
  entry on the Circle empty state. Needs no platform configuration and works
  over SMS or read aloud in person, which is plausibly how these groups form.
- Join code is the **only** invite surface. `InviteMemberPage`'s friend-list and
  user-search are both retired.
- **Public groups stay**, behind the existing join-request approval gate. The
  approval screen must state the consequence: approving grants the newcomer
  visibility of every member's named Progress.
- Real deep links are deferred and tracked in
  [#785](https://github.com/Shir0o/bible-read/issues/785).

## Delete list

| Target | Why |
|---|---|
| `friends_page.dart`, `add_friend_page.dart`, `friend_requests_page.dart`, `friends_view.dart`, `friend_service.dart` (~1,180 lines) | ADR-0003 |
| `acceptFriendRequest`, `deleteFriendRequestPair` + notification-prune trigger (`functions/index.js`) | ADR-0003 |
| `friends`, `friendRequestsSent`, `friendRequestsReceived`, `friendStreakLinks`, `friendStreakInvites` rules blocks | ADR-0003; the streak ones were already dead schema |
| ~~`reading_plans_page.dart`~~ | Done (#811): the duplicate "My Reading Plans" page and its view are deleted; archive, restore and permanent delete live on the hub's plan cards |
| ~~`new_plan_picker_sheet.dart`~~ | Done (#837): the personal-vs-group fork no longer exists |
| `community_reading_hero.dart` | Today owns the reading |
| `FriendService` passthrough in `ChallengesPage` | Never used |
| `readLogBuilder` passthrough in `MainPage` / `CommunityPage` | Dead plumbing; Circle renders the feed directly |
| `Comment` model, `comments` rules block, `sendCommentNotification` | Threaded comments dropped |

## To build

- Join codes (generate, display, share, redeem).
- Adjust-pace for personal Plans, reusing `AdjustDaysPage`.
- Consequence copy on the join-request approval screen.
- One-off: announce and drop existing friendships.
- "Share with your circle" toggle on the reflect sheet, default off.
- `achievements` rules block (nothing works without it).
- Firestore triggers that award achievements server-side.
- Per-Group reading feed + migration off the global `read_logs` (ADR-0004).
- Retire `firstReader`; fix the `nt_starter` naming bug.

## Screens to mock

The design system is **already implemented** — `lib/theme/app_theme.dart`
(warm-paper / aubergine, `#6A53AD` lavender, Spectral + Hanken Grotesk, 22px
cards, 52px buttons). Do not invent a new one. The prototype's register for
Circle and Path is in the handoff bundle (`circle.jsx`, `path.jsx`).

| Screen | State | Why it matters |
|---|---|---|
| Bottom bar | — | Four treatments to compare; Today / Circle / Path |
| Circle | populated | The encouragement payoff: person rows with status, Progress, optional Reflection, latest achievement |
| Circle | **empty** | The screen the observed user failed on. Must carry Join, Create, and "Have a code?" |
| Circle | person row, no shared Reflection | The common case — sharing is opt-in, default off |
| Path | populated | Unified plan list (`AllPlansPage` inline) + stat tiles + consistency |
| Path | **empty** | First plan, no fork between personal and group |
| Start a plan | — | Solo-or-shared as a **field**, not a modal fork |
| Join by code | — | Code entry, and the redeem confirmation |
| Share code | — | Reachable by any member, not just the owner |
| Adjust pace | — | Reuses `AdjustDaysPage`; the answer to "edit my plan" |
| Join request approval | — | Must state that approving grants visibility of every member's Progress |
| Reflect sheet | — | Gains the "share with your circle" toggle, default off |

Today is already design-complete per `design_diff.md`; it only loses its
plan-creation entry points and keeps its two glimpses.

## Open for the design skill

- Four bottom-bar treatments to compare: restyled-in-place, label-on-active-only,
  dot indicator, minimal-height. All with custom glyphs and Today / Circle / Path.
- **A Circle row has four things to show** — today's status, Progress, an
  optional Reflection, and the latest achievement — and most rows will be
  missing the Reflection, since sharing is opt-in and default off. The row needs
  to read well in both states.

---

# Second pass — what the first pass missed

_Settled 2026-09-10, after a review of the shipped redesign. Every decision
above was implemented (#786–#813). Nothing below contradicts them; it finishes
them._

## The diagnosis

**The delete list above omitted `GroupsPage`.** So the new surfaces were built
alongside the old ones instead of replacing them, and the app now carries two of
almost everything:

| Thing | Surfaces |
|---|---|
| A Group's schedule | `FullSchedulePage` has **7 push sites** — Today's card, the Path card's tap target, its catch-up row, the group page's progress card, the group page's catch-up row, `GroupsPage`, and the group page itself |
| A Group | `GroupDetailPage` has **7 push sites** |
| Marking a past reading | `PlanDetailPage`, `FullSchedulePage`, and `GroupCatchUpPage` ("Log Progress") |
| Creating a Group | `CreatePlanPage`'s "With a group" field (#809) **and** `CreateGroupPage` behind Menu → Groups |
| Your groups, on Circle | filter chips **and** a "Your groups" section — the spec said a filter *or* a section |
| Re-dating a schedule | `AdjustPacePage` (personal overlay) and `EditGroupPage` → `AdjustDaysPage` (the Group's schedule), with no names to tell them apart |

Two first-pass requirements also did not land:

- **The empty Circle carries no actions at all** — `EmptyGroupState` is an icon,
  "No active groups", and "Join a group to see progress here." This is the exact
  screen the observed user failed on, and the reason this whole document exists.
- **Path's header still reads "My Reading Plans"** — the string named in cause 2
  of the original diagnosis.

## Decisions

### Path owns the plan lifecycle outright

The Shared plan lives in the Path card and nowhere else. Group surfaces keep
nothing plan-shaped: no progress card, no today's-reading card, no catch-up row,
no pencil.

`PlanDetailPage` widens to accept a Group schedule and becomes **the** schedule
page; `FullSchedulePage` is deleted. Month-burst marking (#844) and Starting
point stop being solo-only privileges. Today's reading card opens that one page
whether the reading is solo or shared — the current split (solo →
`PlanDetailPage`, group → `FullSchedulePage`) is itself a violation of "nothing
else differs".

**"Log Progress" is deleted.** Catching up is marking a past day in the
schedule, which the schedule page already does. A dedicated page also reframes
catching up as a chore you go and do, against the voice recorded in `CONTEXT.md`
("growth, not failure").

### Circle is people only

The flat people list is the tab. The **filter chips stay** — they qualify
*people* ("who is this person to me?"). The **"Your groups" section goes**: two
representations of one set on one screen is the mess.

The empty state gains its three actions, with the code first:

> **No one here yet**
> Your Circle is everyone you share a group with.
> [Have a code?] · Find a group · Create a group

The body line is doing domain work — it is the only place the app explains what
a Circle *is*, and without it the title reads as a failure state rather than a
not-yet state.

### The legacy Groups surface is deleted

`GroupsPage`, `AllGroupsPage`, `all_groups_view.dart` and the Menu → Groups item
go. "Find a group" (public browse) and "Have a code?" rehome onto Circle;
`CreateGroupPage` becomes unreachable, since `CreatePlanPage` already creates the
Group itself.

A non-member browsing a public group gets a **minimal preview sheet** — name,
what the group is reading, member **count**, and "Request to join". No names and
no progress: those are exactly what the approval gate protects under ADR-0003,
and showing them before approval makes the gate decorative.

### `GroupDetailPage` dies

Once the plan content leaves, it is a members page with extra buttons.
`GroupMembersPage` becomes the group page — roster, share code, join requests,
settings — reached from the Path card's "Manage members" and from nothing else.
"Read together" as a *destination* was the conceptual bug: reading together is
what the Path card already shows.

Notification taps carrying a `groupId` land on that Group's Path card.

### Adjust pace and Reschedule are different operations

**Adjust pace** is always personal; **Reschedule** is the owner re-dating the
Group schedule for everyone. See
[ADR-0007](adr/0007-shared-plan-schedule-is-fixed.md) and the `CONTEXT.md`
entries. `EditGroupPage` survives, slimmed to group settings plus Reschedule,
reached from `GroupMembersPage`. Its pencil stops saying "Edit plan".

## Corrected delete list

| Target | Lines | Why |
|---|---|---|
| `groups_page.dart` | 414 | The legacy Groups surface — the omission that caused all of this |
| `all_groups_page.dart` + `views/all_groups_view.dart` | 285 | Public browse becomes a sheet from Circle |
| `create_group_page.dart` | 241 | Unreachable; `CreatePlanPage:535` creates the Group |
| `group_detail_page.dart` | 832 | `GroupMembersPage` is the group page |
| `full_schedule_page.dart` | 542 | Merged into `PlanDetailPage` |
| `group_catch_up_page.dart` | 342 | Catch-up is marking in the schedule |
| `widgets/community/community_group_progress_card.dart` | 380 | Already dead — rendered by nothing |
| `widgets/group_progress_card.dart` | 206 | Only consumer was the group page |
| `widgets/todays_reading_card.dart` | — | Same; Today owns the reading |
| "Groups" item, `app_menu_sheet.dart:169` | — | The doorway to the legacy surface |
| Circle's "Your groups" section | — | Groups are the filter chips only |

## To build

- Widen `PlanDetailPage` to a Group schedule source; retire `FullSchedulePage`.
- Circle empty state: the three actions and the copy above.
- Public-group preview sheet.
- Share code and join requests onto `GroupMembersPage`.
- Reschedule: owner-only, consequence copy, on the slimmed `EditGroupPage`.
- Rename Path's header off "My Reading Plans".
- Route `groupId` notifications to the Path card.

## Order

The deletions land **first**, as their own change. Every issue after is then
written against an app with one doorway per thing — which is the discipline the
first pass lacked.
