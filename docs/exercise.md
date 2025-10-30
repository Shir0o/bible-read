# Exercise tracker data model

The exercise tracker feature stores user-defined challenges alongside daily progress totals. All documents live underneath the
authenticated user's document.

## Collections

- `users/{uid}/exerciseChallenges`
  - `name` (`string`): Display name of the challenge.
  - `unit` (`string`): Unit label shown in the UI (for example `minutes`).
  - `dailyGoal` (`number`): Amount required to count the day as complete.
  - `targetType` (`string`): Comparison applied to the daily goal. One of `atLeast`, `atMost`, or `exactly`.
  - `categories` (`array<string>`): Optional list of tags used to group challenges.
  - `archived` (`bool`): When true the challenge is hidden from active lists.
  - `createdAt` (`timestamp`): When the challenge was created.
  - `updatedAt` (`timestamp`): When the challenge definition was last updated.

- `users/{uid}/exerciseProgress/{yyyy-MM-dd}`
  - `date` (`timestamp`): Calendar day represented by the document (normalized to midnight local time).
  - `totals` (`map<string, number>`): Totals recorded for each challenge keyed by challenge id.
  - `updatedAt` (`timestamp`): Time when the progress document was last changed.

`ExerciseTrackerService` automatically computes streaks by scanning the recent `exerciseProgress` documents. The streak resets
as soon as a day is missed, so challenges no longer include monthly grace credits.
