# Reading Groups

Reading groups allow multiple users to follow a shared Bible plan. The data is stored under the `groups` collection in Firestore.

## Collections

- `groups/{groupId}` – group document containing fields:
  - `name`: display name of the group
  - `ownerUid`: UID of the user who created the group
- `groups/{groupId}/members/{uid}` – membership documents for each user
- `groups/{groupId}/schedule/{date}` – daily schedule entries storing a list of chapter references for the given date

Each schedule document stores its date (usually in `YYYY-MM-DD` format) and an array of chapter strings.
