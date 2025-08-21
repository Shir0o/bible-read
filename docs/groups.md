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

Each schedule document stores its date (usually in `YYYY-MM-DD` format) and an array of chapter strings.

## Security Rules

Firestore security rules restrict modifications to group data:

- Only the user whose UID matches `ownerUid` may write to group metadata or the `schedule` subcollection.
- Members may read group details, member lists, and schedules but cannot modify schedules.
- Membership documents are read-only to members; only owners can add or remove members.

## UI

The app includes a `GroupsPage` listing all available groups (`lib/pages/groups_page.dart`). Selecting a group opens a `GroupDetailPage` (`lib/pages/group_detail_page.dart`) showing the member list and reading schedule. Any user can view a group's details and submit a join request, while group owners can add or edit schedule entries from this page.
