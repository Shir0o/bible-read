## 2024-05-19 - Firestore whereIn limit optimization
**Learning:** Firestore's `whereIn` array queries have a hard limit of 30 elements. Batching queries (like fetching user data by `uid`) using this maximum limit is a safe and robust way to mitigate N+1 query bottlenecks in a single Dart stream. Using smaller chunks (like 10) leaves performance on the table for no structural benefit.
**Action:** When working with Firestore `whereIn` queries, default to chunk sizes of 30 unless memory or network constraints dictate otherwise.

## 2026-03-09 - Parallelizing sequential async recalculations
**Learning:** Sequential `await` in for-loops across multiple Firestore collections can create significant latency. Parallelizing these operations using `Future.wait` on an iterable map is a straightforward yet highly effective architectural improvement. While `FakeFirebaseFirestore` might not demonstrate a timing speedup due to its synchronous execution model, the design pattern is essential for real-world Firestore efficiency.
**Action:** Always check for sequential `await` calls within loops that perform independent asynchronous operations and refactor them to use `Future.wait` when possible.

## 2024-05-20 - Sequential document fetches
**Learning:** Sequential `await` calls inside a loop for fetching individual Firestore documents create a severe N+1 query bottleneck.
**Action:** When a list of specific document paths is known (and `whereIn` cannot be easily used), use chunked `Future.wait` to fetch them concurrently, ensuring errors are caught within the individual futures so the entire batch doesn't fail.


## 2024-05-21 - Parallelizing group member notifications
**Learning:** Sequential `await` calls inside a loop for creating notifications (e.g., in `updateSchedule` for `GroupService`) create an unnecessary bottleneck, especially for larger groups. Parallelizing these operations using `Future.wait` improves performance.
**Action:** When creating notification documents for multiple users or processing independent asynchronous tasks, use chunked `Future.wait` or un-chunked `Future.wait` (if the limit isn't huge and independent execution is fine) to execute them concurrently instead of using sequential `await` within a `for` loop.
