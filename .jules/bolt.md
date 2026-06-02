## 2024-10-31 - N+1 Query in Backfilling Reading Logs
**Learning:** We replaced a sequential N+1 query loop with a `Future.wait` and batching limit loop of 30 that used `collectionGroup('entries')` paired with `whereIn` to solve the N+1 issue.
**Action:** Always favor bulk fetching with bounded batch execution sizes (`whereIn` supports up to 30) paired with `Future.wait` over N+1 loops where document IDs are known and fetching by specific criteria like `uid`.
