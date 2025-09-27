# Reading Groups

Reading groups allow multiple users to follow a shared Bible plan. The data is stored under the `groups` collection in Firestore.

## Creating and Joining

Users can create a group from the app. All groups are visible and listed on the Groups page. Opening a group shows a **Join Group** button on the detail page. Selecting this button sends a join request that the group owner or an admin must approve before membership is granted.

## Collections

- `groups/{groupId}` – group document containing fields:
  - `name`: display name of the group
  - `ownerUid`: UID of the user who created the group
- `groups/{groupId}/members/{uid}` – membership documents for each user
- `groups/{groupId}/schedule/{date}` – daily schedule entries storing a list of chapter references for the given date
- `groups/{groupId}/schedule/{date}` – daily schedule entries storing a list of chapter references for the given date
- `groups/{groupId}/scheduleTemplates/{templateId}` – auto-schedule templates (MVP uses a single `default` template)
- `groups/{groupId}/progress/{date}/entries/{uid}` – per-group completion state for a given date. Presence of an `entries/{uid}` document indicates the member has completed that group's assignment for the date. This is independent from the global daily read log under `read_logs/`.
- `groups/{groupId}/progress/{date}/entries/{uid}` – per-group completion state for a given date, with optional `items/{index}` for per‑chapter checks and a `count` field reflecting checked items that day.
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

## Auto Schedule (MVP)

Group owners/admins can enable an "Auto-add daily schedule" option on the Group Details page (Edit mode). This stores a template under `groups/{groupId}/scheduleTemplates/default` with fields:

- `active: bool` – whether auto materialization is enabled
- `timezone: string` – IANA timezone, e.g., `UTC` or `America/Los_Angeles`
- `startTimeLocal: string` – HH:mm in the group's local time (informational in MVP)
- `rrule: string` – recurrence rule, defaults to `FREQ=DAILY;INTERVAL=1`

When enabled, a Cloud Function runs daily and creates an empty schedule document for the current local date if one does not exist yet. This is idempotent and safe to rerun.
