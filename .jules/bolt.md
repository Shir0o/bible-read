## 2024-10-31 - N+1 Query in Backfilling Reading Logs
**Learning:** We replaced a sequential N+1 query loop with a `Future.wait` and batching limit loop of 30 that used `collectionGroup('entries')` paired with `whereIn` to solve the N+1 issue.
**Action:** Always favor bulk fetching with bounded batch execution sizes (`whereIn` supports up to 30) paired with `Future.wait` over N+1 loops where document IDs are known and fetching by specific criteria like `uid`.

## 2024-11-20 - N+1 Query limit bottlenecks
**Learning:** Replaced the previous `whereIn` batching execution bounds logic for concurrent chunk maps that fetches exactly using concurrent `get()` with `Future.wait` via maps instead of being restricted to chunks limits on arrays, providing faster times especially when bypassing bounded overhead calculations and saving on payload.
**Action:** While chunking `whereIn` queries works for bounding network reads, mapping parallel `.get()` fetches locally for individual documents resolves network bounds without hitting Firestore multi-document query overhead, producing measurably faster executions.
