# Offline-first habit tracking and guest reading

Bible Read prioritizes presence over ceremony: readers open the app to mark
their daily Scripture portion, whether solo or alongside a group. Previously,
the app required network connectivity for several high-frequency flows —
`firestore.runTransaction` was used to mark plan days, `user.reload()` was
called on status checks, and unauthenticated readers were held at a Welcome
gate requiring sign-in before any reading could begin.

We are adopting an **offline-first habit architecture** powered by Cloud
Firestore persistence and introducing **Guest reader** support with transparent
**Account linking**.

## Considered options

- **Dedicated local database (SQLite/Drift/Hive) with custom sync engine.**
  Rejected: Bible Read's domain models already map to Firestore documents and
  real-time streams (`snapshots()`). Introducing a duplicate local database
  would introduce massive schema boilerplate, bidirectional synchronization
  complexities, and high risk of race conditions, with no tangible benefit over
  Firestore's proven native disk persistence.
- **Mandatory authentication before first read.**
  Rejected: Forcing new readers through sign-in friction before they have
  experienced the reading habit conflicts with the app's core value of
  distraction-free presence.
- **Silent collision overwrite on account linking.**
  Rejected: When an existing account already has reading history, silently
  overwriting local guest progress causes data loss; silently replacing cloud
  data risks clobbering established records.
- **Firestore native persistence + Guest reader with dry-run merge** (chosen).

## Decision

1. **Firestore-native offline persistence**:
   - Eliminate all `runTransaction` calls on habit marking paths (e.g.
     `markDayComplete` in `ReadingPlanService` and `updateDailyReading` in
     `GroupService`) in favor of offline-safe atomic mutations (`arrayUnion`,
     `arrayRemove`, batch writes).
   - Configure Firestore with unbounded persistent cache.
   - Replace runtime `collectionGroup` queries during marking with locally
     cached membership records.

2. **Log-derived streak & calendar state**:
   - The dated reading documents (`reading/{dateId}`) are the immutable source
     of truth.
   - Streaks, missed days, and calendar presence are derived deterministically
     from the set of date keys on client and server alike, preventing summary
     document merge conflicts across offline periods.

3. **Guest reader lifecycle**:
   - A new reader can tap "Start Reading" on the Welcome screen and begin
     immediately without entering an email or password.
   - Under the hood, the app provisions an anonymous Firebase Auth session
     (`signInAnonymously`). If launched with zero connectivity on a fresh
     install, it initializes a synthetic local session (`guest_local_<id>`) and
     promotes it to Firebase Anonymous Auth once online.
   - Guest readers have full access to personal plans, daily check-in, streaks,
     reflections, and Bible progress. Social tabs (Circle, Group creation,
     friend invites) present a gentle Sanctuary sheet prompting account creation.

4. **Account linking & Merge dry-run**:
   - When a Guest reader signs in with Google, Apple, or email, the app links
     their credentials to the existing anonymous UID.
   - If the chosen account already exists in Firebase (`credential-already-in-use`),
     the app presents a **Merge dry-run** modal: displaying the union of read
     dates, recomputed streak, and a toggleable list of active personal plans,
     giving the reader full transparency before committing.

5. **Ambient sync indicator**:
   - The persistent error-styled `OfflineBanner` is replaced by an ambient
     indicator in the Home header: a quiet gold dot displaying "Saved locally"
     when mutations are pending, transitioning to a subtle "All synced" checkmark
     for 2.5 seconds when reconnected.

## Consequences

- Readers can mark personal and group readings completely offline (e.g. in
  airplane mode or subways) with zero UI interruption or failed writes.
- Write operations on marking paths must never use `runTransaction`.
- Social features (creating groups, joining by code, sending nudges, live Circle
  feed updates) gracefully degrade to inform the reader when an internet
  connection is required.
