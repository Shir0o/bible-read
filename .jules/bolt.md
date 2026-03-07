## 2024-05-19 - Firestore whereIn limit optimization
**Learning:** Firestore's `whereIn` array queries have a hard limit of 30 elements. Batching queries (like fetching user data by `uid`) using this maximum limit is a safe and robust way to mitigate N+1 query bottlenecks in a single Dart stream. Using smaller chunks (like 10) leaves performance on the table for no structural benefit.
**Action:** When working with Firestore `whereIn` queries, default to chunk sizes of 30 unless memory or network constraints dictate otherwise.
