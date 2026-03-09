## 2024-05-19 - Firestore whereIn limit optimization
**Learning:** Firestore's `whereIn` array queries have a hard limit of 30 elements. Batching queries (like fetching user data by `uid`) using this maximum limit is a safe and robust way to mitigate N+1 query bottlenecks in a single Dart stream. Using smaller chunks (like 10) leaves performance on the table for no structural benefit.
**Action:** When working with Firestore `whereIn` queries, default to chunk sizes of 30 unless memory or network constraints dictate otherwise.

## 2026-03-09 - Parallelizing sequential async recalculations
**Learning:** Sequential `await` in for-loops across multiple Firestore collections can create significant latency. Parallelizing these operations using `Future.wait` on an iterable map is a straightforward yet highly effective architectural improvement. While `FakeFirebaseFirestore` might not demonstrate a timing speedup due to its synchronous execution model, the design pattern is essential for real-world Firestore efficiency.
**Action:** Always check for sequential `await` calls within loops that perform independent asynchronous operations and refactor them to use `Future.wait` when possible.
