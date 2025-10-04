# Reading Groups

Reading groups allow multiple users to follow a shared Bible plan. The data is stored under the `groups` collection in Firestore.

## Creating and Joining

Users can create a group from the app. All groups are visible and listed on the Groups page. Opening a group shows a **Join Group** button on the detail page. Selecting this button sends a join request that the group owner or an admin must approve before membership is granted.

## Collections

- `groups/{groupId}` – group document containing fields:
  - `name`: display name of the group
  - `ownerUid`: UID of the user who created the group
  - `manualPlanProgress`: optional map storing manual generator metadata
    - `nextChapterReference`: string reference for the next manual chapter
    - `defaultChaptersPerDay`: number of chapters to schedule per day when generating manually
    - `lastMaterializedDate`: date (timestamp) when manual content was last produced
  - `autoContent`: optional status map surfaced in the UI's manual scheduler section
    - `lastGeneratedAt`: timestamp/ISO string noting when the manual generator last ran
    - `missedDays`: number of upcoming days that still need assignments
    - `suggestedCatchUpDays`: optional override for the catch-up prompt (falls back to `missedDays`)
- `groups/{groupId}/members/{uid}` – membership documents for each user
- `groups/{groupId}/schedule/{date}` – daily schedule entries storing a list of chapter references for the given date
- `groups/{groupId}/progress/{date}/entries/{uid}` – per-group completion state for a given date, with optional `items/{index}` for per‑chapter checks and a `count` field reflecting checked items that day. Presence of an `entries/{uid}` document indicates the member has completed that group's assignment for the date. This is independent from the global daily read log under `read_logs/`.
- `groups/{groupId}/progressSummary/data/entries/{uid}` – cached per‑member aggregate for the group, with `completed` storing the total number of checked chapters across all dates. This is updated on each check/uncheck and used for fast overall progress.

Each schedule document stores its date (usually in `YYYY-MM-DD` format) and an array of chapter strings.

## Security Rules

Firestore security rules restrict modifications to group data:

- Only the user whose UID matches `ownerUid` may write to group metadata or the `schedule` subcollection.
- Members may read group details, member lists, and schedules but cannot modify schedules.
- Membership documents are read-only to members; only owners can add or remove members.
- Group progress is member-scoped: members can create or delete their own `progress/{date}/entries/{uid}` documents; other users cannot write on their behalf.

## Separation from Daily Read Log

The group completion checkboxes on the Group Details page now store state under `groups/{groupId}/progress/...` and do not write to the global feed at `read_logs/{date}/entries/{uid}`. The global daily log and the Home page streak are still based on `users/{uid}/reading/{date}` and `read_logs/` and are unaffected by toggling group-specific completion.

## UI

The app includes a `GroupsPage` listing all available groups (`lib/pages/groups_page.dart`). Selecting a group opens a `GroupDetailPage` (`lib/pages/group_detail_page.dart`) showing the member list and reading schedule. Any user can view a group's details and submit a join request, while group owners can add or edit schedule entries from this page.

## Manual Schedule Generation

Group owners (and any admins a group may have) are responsible for keeping the shared schedule stocked. The Group Details page exposes two ways to do that while in edit mode:

1. **Manual editing** – owners can open a specific day and type the references that should be read.
2. **Generate upcoming days** – an owner can press the *Generate upcoming days* button to request that Firestore fill in the next N days using the manual plan metadata described below.

The generator dialog suggests how many days to create by looking at `autoContent.suggestedCatchUpDays` and `autoContent.missedDays`. If neither value exists the UI falls back to `1`. After each successful run the backend should update:

- `autoContent.lastGeneratedAt` with the date that was just materialized. This is what the UI surfaces as “Last generated”.
- `autoContent.missedDays` with the number of days that still lack assignments after the run. This becomes the default catch‑up value the next time the dialog opens (unless `suggestedCatchUpDays` is provided to override it).
- `manualPlanProgress.lastMaterializedDate` with the latest scheduled date so contributors can see when content was last produced manually.

The `manualPlanProgress` map tracks defaults for future runs:

- `nextChapterReference` stores the starting reference the generator should use when filling the next batch of days. The UI exposes a shortcut to edit this field.
- `defaultChaptersPerDay` is used when the dialog is opened before a user has typed a value. Owners should keep this aligned with the plan they are following.
- `lastMaterializedDate` provides a coarse record of when the plan was last extended; this is distinct from `autoContent.lastGeneratedAt`, which is only for the status banner.

Because the process is manual, owners are expected to review the generated assignments and adjust them as needed. If a group pauses or wants to restart a reading sequence, update `nextChapterReference` (and optionally `defaultChaptersPerDay`) before running the generator again so the new schedule begins in the right place.

## Manual QA

To confirm optimistic updates for group chapter toggles remain visible until Firestore reports the change:

1. Open a group that has a schedule with multiple chapters and join as a member.
2. Toggle one chapter to mark it complete and watch the chip stay selected while the request is in flight.
3. Inspect the Firestore emulator/console and wait for the corresponding `items/{index}` document to appear; the UI should clear the pending override immediately after the snapshot updates.
4. Repeat with a bulk “Mark all done” toggle to ensure the read switch and all chapter chips remain active until the server responds, then settle without flicker once the remote state matches.
