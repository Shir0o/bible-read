# Feedback collections

The app stores bug reports and feature requests in two top-level Firestore collections:

- `bugReports`
- `featureRequests`

Each document shares the same schema:

| Field             | Type                | Description |
| ----------------- | ------------------- | ----------- |
| `uid`             | `string \| null`    | Firebase Authentication UID of the reporter when available. |
| `email`           | `string \| null`    | Email address from the authenticated user. |
| `displayName`     | `string \| null`    | Display name from the authenticated user. |
| `title`           | `string`            | Short title summarising the feedback. |
| `description`     | `string`            | Detailed description provided by the reporter. |
| `reproductionSteps` | `string \| null` | Optional steps to reproduce an issue. |
| `platform`        | `string`            | Platform identifier such as `android`, `ios`, or `web`. |
| `timestamp`       | `Timestamp`         | Creation time recorded by the client. |
| `status`          | `string`            | Workflow state for triage. New items default to `open`. |
| `updatedAt`       | `Timestamp`         | Last workflow update time. Set to the creation timestamp for new documents. |
| `resolvedAt`      | `Timestamp \| null` | When the item was resolved, or `null` while still open. |
| `resolutionNotes` | `string \| null`    | Optional notes describing how the item was resolved. |

## Backfilling legacy documents

Run the one-time Node script in `functions/backfill-feedback-status.js` with admin credentials to apply the workflow metadata to existing feedback entries:

```bash
cd functions
npm install
GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccount.json node backfill-feedback-status.js
```

The script updates both collections, adding default workflow fields only when they are missing. A sample run prints the number of documents touched per collection. After the backfill completes, downstream code can rely on every document exposing the workflow metadata above.
