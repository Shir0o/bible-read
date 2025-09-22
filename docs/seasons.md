# Seasonal Challenges

This guide explains how seasonal challenges are modeled in Firestore, how the Flutter
app loads them, and what happens when a user claims a reward. Share it with designers
or content editors so new seasons can be launched without code changes.

## Firestore data model

Seasonal content lives entirely in Firestore. The client looks for the most recent
season whose dates include today and streams its challenges in real time.

```text
seasons (collection)
  {seasonId} (document)
    title: string
    description: string
    startDate: Timestamp
    endDate: Timestamp
    bannerImageUrl: string (optional)
    challenges (subcollection)
      {challengeId} (document)
        seasonId: string (defaults to parent id)
        title: string
        description: string
        metric: string (unit displayed to users, e.g. "reads")
        goal: number (total required to finish)
        dailyCap: number (optional max progress per day)
        repeatable: bool (whether users can finish multiple times)
        reward: map (optional)
          id: string (optional, used for analytics)
          type: string (category, e.g. "points" or "badge")
          title: string (headline shown in UI)
          description: string (optional details)
          iconUrl: string (optional artwork URL)
          amount: number (quantity or score value)
users (collection)
  {uid} (document)
    seasonChallenges (subcollection)
      {seasonId}_{challengeId} (document, created automatically)
        uid: string
        seasonId: string
        challengeId: string
        dailyProgress: map<yyyy-MM-dd, number>
        totalProgress: number
        updatedAt: Timestamp
        completedAt: Timestamp (set when the goal is reached)
        rewardClaimedAt: Timestamp (set after claiming)
    seasonRewards (subcollection, created automatically)
      {seasonId}_{challengeId} (document)
        seasonId: string
        challengeId: string
        challengeTitle: string
        reward: map (copied from the challenge definition)
        claimedAt: Timestamp
    notifications (subcollection, created automatically)
      {notificationId} (document)
        type: "seasonalChallenge"
        message: string
        read: bool
        timestamp: Timestamp
```

### Creating or updating seasons

1. Open the Firebase console (Firestore) and add a document in the `seasons`
   collection. Set the `startDate` and `endDate` to cover the promotional
   window; the app automatically picks the active season with the latest
   `startDate` that
   includes today.
2. Add one or more challenge documents in the `seasons/{seasonId}/challenges`
   subcollection. Provide the copy you want to show in the app and define the
   `goal`, `metric`, and optional `reward` map. Rewards are displayed in the
   Seasonal tab even before completion, so include a short headline and optional
   artwork.
3. (Optional) Update or archive past seasons by adjusting their `endDate`. The
   client only shows seasons that are active, so you can stage upcoming content
   ahead of time without affecting current users.

No code changes or deployments are required—the Flutter app reacts immediately to
Firestore updates. If you need to preview content before the dates start, temporarily
set `startDate` to today and switch it back after reviewing the UI.

## `SeasonalChallengeService` API

`SeasonalChallengeService` centralizes all seasonal reads and writes:

* `Future<Season?> fetchActiveSeason()` – loads the most recent active season.
* `Stream<List<SeasonalChallenge>> streamChallenges(String seasonId)` – watches
  the challenge definitions for updates.
* `Stream<SeasonalChallengeProgress?> streamProgress({ uid, seasonId, challengeId })`
  – observes an individual user's progress document.
* `Future<SeasonalChallengeProgress> incrementDailyProgress({ uid, challenge })`
  – increments progress, clamping to the challenge goal and creating the document
  if necessary.
* `Future<void> claimReward({ uid, progress })` – calls the Cloud Function to mark
  the reward as claimed and refreshes caches.

Pages such as the home dashboard and the dedicated Seasonal tab subscribe to
these streams so progress bars, remaining time labels, and claim states update
live as Firestore changes.

## Cloud Function reward flow

The callable Cloud Function `claimSeasonalChallengeReward` enforces business rules
when a user taps **Claim reward**:

1. Validate authentication and the `seasonId` / `challengeId` payload.
2. Read the challenge definition, the user's
   `seasonChallenges/{seasonId}_{challengeId}` progress document, and any existing
   reward entry in a single transaction.
3. Ensure the challenge exists, the user has finished it (`totalProgress >= goal`),
   and the reward has not been claimed yet.
4. Write a `seasonRewards/{seasonId}_{challengeId}` document with the challenge
   title, reward payload, and `claimedAt` timestamp, and set `rewardClaimedAt` on
   the progress document.
5. Create a `notifications/{notificationId}` entry with `type: 'seasonalChallenge'`
   and send a push notification when the user's preferences allow it.

If any validation fails the transaction aborts and the app surfaces an error
SnackBar, leaving progress untouched.

## Designer workflow (no code deploys)

* **Plan ahead:** Schedule upcoming seasons by adding documents in advance—the app
  ignores them until their `startDate` arrives.
* **Update copy instantly:** Edit challenge descriptions, rewards, or artwork in
  Firestore and the UI will refresh automatically for all signed-in users.
* **Retire content gracefully:** Push the `endDate` into the past to hide a
  season, or delete the document once all rewards have been distributed.
  Historical progress and rewards remain under each user for reporting purposes.
* **Test in staging:** Use a secondary Firebase project for QA. Populate the
  same collections, log in with a test account, and confirm that claiming a
  reward drops a `seasonalChallenge` notification and updates the home seasonal
  summary.

By managing seasons directly in Firestore, the product and design teams can
iterate on challenge pacing, copy, and rewards without waiting for a new app
release.
