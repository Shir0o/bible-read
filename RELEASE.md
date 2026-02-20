# Release 1.22.0

This release introduces a dedicated group search view, accessibility improvements across the app, and a major audit of test debt to ensure ongoing platform stability.

## Highlights

*   **Find Groups:** A new dedicated search interface for discovering reading groups.
*   **Full Reading Schedule:** A new screen to visualize the entire reading plan for a group.
*   **A11y & UX:** Improved accessibility for calendars, signup forms, and member lists, along with streamlined login haptics.
*   **Test Audit:** Remediated significant test debt and added gap coverage for core services.

## Features & Enhancements

*   **Group Management:** Refactored group detail navigation and optimized member daily completion calculations.
*   **Find Groups View:** Added search functionality and a new group card design with basic member data fetching.
*   **Full Schedule Page:** Introduced a dedicated page for group schedules, removing redundant optimistic update logic.
*   **Removal of Exercise Challenges:** Streamlined the app by removing the exercise challenges feature and related assets.

## Accessibility (a11y)

*   **Streak Calendars:** Enhanced contrast and labels for reading progress visualization.
*   **Forms:** Improved `SignupForm` and `LoginForm` with better interaction hints and assistive technology support.
*   **Member Lists:** Verified and improved local hierarchy and labels in the Group Member List.

## Stability & Integrity

*   **Test Remediation:** Performed a stress audit of the test suite, fixing 60+ failing tests and improving mocking patterns for `GroupService` and `LeaderboardPage`.
*   **Skeleton Loaders:** Refined loading states and restored the "Thank you for being here" screen for a smoother onboarding experience.

# Release 1.21.0

This release introduces a refined visual experience with font updates and expressiveness, implements the "Bible in a Year" reading plan, and streamlines the app by removing email summary features.

## Highlights

*   **Bible in a Year Plan:** A structured reading plan for reading the entire Bible in one year.
*   **Visual Refinements:** Updated to "IBM Plex Sans" for a cleaner look and deeper integration of Material 3 Expressive tokens.
*   **Expressive Feed:** Redesigned feed cards to match the new design language.
*   **Journey Tab Polish:** Improvements to the Journey tab layout and transitions.

## Features & Enhancements

*   **Reading Plans:** Added logic and data models for 'Bible in a Year', with Old and New Testament tracking.
*   **Typography:** Switched primary font to IBM Plex Sans and removed IBM Plex Mono.
*   **UI Polish:** Refined button styles, tab animations, and home screen skeleton loaders to match the new expressive theme.
*   **Removal of Email Summaries:** Removed the email stats summary functionality to simplify the user experience.

# Release 1.20.0

This release introduces a major visual redesign with a "Calm" menu structure, a new Book Tracker, and significant UI polish including a switch to Light Mode and IBM Plex Sans.

## Highlights

*   **UI Overhaul:** A shift to Material 3 Expressive design, Light Mode by default, and a new IBM Plex Sans typography. The home screen is minimal with skeleton loaders and subtle progress indicators.
*   **Calm Navigation:** Consolidated navigation into Home, Community, and Journey tabs for a more focused experience.
*   **Book Tracker:** Track your reading progress on a per-book basis.
*   **Optimistic UI:** Encouragement (nudges) and read logs now update instantly.

## Visual Design & UX

*   **Redesign:** The app now features a "Calm" aesthetic with warm clay colors, cleaner spacing, and improved card elevations.
*   **Home Page:** Completely redesigned with a minimal 'Mark as Read' UI, skeleton loading states, and no more loading bars using the new `StatusRefreshIndicator`.
*   **Typography:** Adopted IBM Plex Sans/Mono for a distinct, readable look.
*   **Haptics:** Refined haptic feedback to trigger on touch down for a more responsive feel.

## Features

*   **Book Tracker:** A new feature to visualize and track progress through individual books of the Bible.
*   **Community Tabs:** Improved state preservation and smart refreshing for the Community page tabs (Feed/Friends).
*   **Optimistic Updates:** Nudges and read status changes reflect immediately in the UI.

# Release 1.19.0

This release launches monthly reading summary emails with user opt-in controls, tightens Firestore permissions around feedback and leaderboard data, and polishes friendly streak and group interactions while improving refresh reliability.

## Highlights

*   Monthly stats emails now send automatically on the first of each month through a scheduled Cloud Function that compiles the prior month's reading totals and streaks.
*   Users can opt in or out of monthly summary emails during signup or from their profile thanks to a shared `EmailPreferencesService` and automatic default backfill.
*   Feedback moderation, leaderboard reads, navigation, and refresh entry points were hardened with more precise Firestore rules, permission messaging, and guardrails.

## Monthly Summary Emails

*   Added a `sendMonthlyStatsEmail` scheduled function (with helper utilities and tests) that gathers the previous month's days read, streak segments, and grace day usage before sending a SendGrid email to every verified user who stays opted in.
*   Introduced `EmailPreferencesService`, profile page controls, and a signup toggle for the `emailPrefs.monthlySummary` flag plus main-page backfills so every account stores an explicit default.
*   Documented the new job in `docs/functions.md`, covering scheduler details, SendGrid configuration, and emulator steps for maintainers.

## Feedback & Security

*   Updated Firestore rules so only the owner can read their personal `summary/*` docs while the leaderboard continues to access `summary/data`, and bug/feature submissions now validate payloads plus restrict reads to admins or the author.
*   The feedback admin inbox now handles Firestore permission errors inline, logs unexpected failures to Crashlytics, and avoids crashing when access is denied.
*   Firebase configuration and initialization order were refreshed alongside tighter Firestore syntax to keep the app aligned with the latest project settings.

## Navigation & Groups

*   Friendly streak banners and invite entry points use `NavigationMenuScope` so routing to the streak or friends tabs stays within the main navigation stack, and the streak limit card styling now matches the rest of the UI.
*   Schedule checkboxes, per-chapter chips, and read toggles remain hidden unless the viewer is a signed-in group member, and finishing a plan entry now refreshes book achievements to keep summaries accurate.
*   Group creation dialogs dispose controllers safely when cancelled, and the App Menu Sheet waits for the admin role check while ensuring its parent context is still mounted before presenting the modal.

## Stability

*   Home page pull-to-refresh now chains summary and book achievement reloads inside a try/catch, surfacing snackbars when a step fails while logging the stack trace.
*   Book achievement refresh helpers and friendly streak loaders handle Firestore failures gracefully without leaving the UI stuck, and related widget tests were updated to cover the tightened behavior.
*   Leaderboard summary access, feedback streams, and Firestore rule fixes reduce permission errors during normal navigation.

# Release 1.18.0

This release debuts Friendly Streaks with a dedicated management page, home banner, and invite workflow updates while tightening Firestore rules and coverage around the new flow.

## Highlights

*   Friendly Streak data is now surfaced on the Home page and has its own navigation destination without leaving the main shell.
*   Friends and Requests pages now support sending, accepting, and declining streak invites with enforcement of the five-partner limit.
*   Firestore rules and automated tests guard the new cross-user writes plus the updated UI states to keep streaks stable.

## Friendly Streaks

*   Added `FriendlyStreakService` and the `FriendStreakLink` model to fetch and sort active partners and pending invites with graceful fallbacks.
*   Introduced `FriendlyStreakPage` alongside the new `FriendlyStreakBanner`, complete with pull-to-refresh, empty/error states, and Navigation Menu integration so tapping the banner keeps MainPage in place.
*   Extended the navigation scope and menu sheet with a Friendly Streaks destination, ensuring deep links land inside the main tab stack.

## Friends & Invites

*   Expanded `FriendService`, `FriendsPage`, and `FriendRequestsPage` with start-streak actions, respond controls, busy state handling, and snackbars that surface invite success or limit violations.
*   Added `FriendStreakInviteList` so actionable invites stream into the Requests inbox, and empty states clearly communicate when no invites remain.
*   Updated Firestore security rules to allow either participant to create, update, or delete `friendStreakInvites` and `friendStreakLinks`, unblocking cross-user writes for the new service APIs.

## Stability & Coverage

*   Hardened the friendly streak experience with widget, service, and integration tests that cover navigation, banner rendering, error states, and invite acceptance/decline paths.
*   Added additional coverage around book achievement refreshes to ensure Home page refreshes continue triggering the expected background work.

# Release 1.17.0

This release separates exercise tracking from the Reading Hub, hardens Firestore permissions, and refreshes navigation to surface the new flow.

## Highlights

*   Daily exercise moves into its own dashboard page with dedicated refresh, logging, and challenge shortcuts.
*   Reading Hub now focuses solely on streak context while still linking into the exercise experience when needed.
*   Firestore security rules now allow signed-in users to manage their own `exerciseChallenges` and `exerciseProgress` documents, resolving permission-denied crashes.

## Exercise Tracking

*   Introduced `ExerciseDashboardPage` with the existing summary cards, retry handling, and challenge management actions.
*   Shared the `ExerciseTrackerService` instance across exercise surfaces to avoid redundant initialisation and haptic wiring.
*   Updated the navigation menu with distinct entries for Daily Exercise and Exercise Challenges.
*   Added inline logging controls with haptic feedback, success snackbars, and automatic refresh after recording progress or returning from challenge management.
*   Hardened empty and error states so signed-out users see a neutral dashboard, failures surface guidance, and Crashlytics receives full context.

## Stability

*   Fixed Crashlytics permission errors triggered when loading exercise summaries by aligning Firestore rules with the app collections.

# Release 1.16.0

This release introduces monthly grace credits to cushion streaks, streamlines group scheduling tooling, and refreshes navigation and notifications throughout the app.

## Highlights

*   Monthly grace credits automatically cover up to two missed days per month (plus bonuses for long streaks) and surface the remaining balance in streak history.
*   Navigation now uses a modal menu sheet with consistent bottom navigation highlights and refreshed animated action button motion.
*   Notification center adds a clear-all action, and Google Sign-In is configured with platform client IDs for smoother authentication.

## Streaks & Reading

*   Rebuilt the reading summary to track grace credits per month, granting bonus credits every 15 consecutive days while preserving streaks.
*   Streak history shows remaining grace credits alongside current, longest, and period totals, falling back to reading docs when cached data is incomplete.
*   Fixed streak reconstruction to include today's progress when recalculating summaries.

## Group Scheduling

*   Group schedules now list the newest entries first and reconcile pending sync flags after local edits to avoid duplicate rows.
*   Plan management tools are limited to group owners, and the deprecated manual plan service, models, and Firestore rules have been removed to simplify maintenance.

## Navigation & UI

*   Replaced the app drawer with a modal menu sheet, alphabetized navigation destinations, and aligned the highlighted tab with the active content.
*   Tweaked common styles, home interactions, and button haptics to keep the experience responsive.

## Notifications & Auth

*   Added a `Clear all` control to the Notification Center along with coverage to verify the new behavior.
*   Provided platform-specific Google Sign-In client IDs so Android and Apple platforms negotiate the correct OAuth flow.

# Release 1.15.1

Release notes forthcoming.

# Release 1.15.0

This release launches Auto Content Plans to automate schedule generation,
refreshes group management flows, and polishes navigation and typography
throughout the app.

## Highlights

*   Auto Content Plans let admins create, edit, activate, and reset automated
    reading schedules with built-in Old Testament, New Testament, and Psalms
    presets.
*   Group join requests move into a dedicated surface with tighter navigation,
    optimistic schedule toggles, and more reliable editing.

## Auto Content Plans

*   Replace the legacy auto-template toggle with a full plans list supporting
    add/edit/delete, default plan editing, active state, schedule cadence, and
    cursor management.
*   Extend the ScheduleTemplate model with plan types, timezone-aware start
    references, and per-plan chapter targets.
*   Cloud Functions now materialize Old/New Testament and Psalms content,
    combine multiple plans into a single day, expose callable
    `materializeToday`/`resetPlanCursor`, and fall back gracefully when Firestore
    indexes are missing.

## Groups & Notifications

*   Move join requests into their own page, surface an app bar shortcut for
    admins, and streamline navigation from notifications.
*   Make schedule toggles optimistic, ensure transactional reads succeed, and
    clean up the legacy plan service from the group detail page.
*   Dedupe friend and join notifications, attach helpful messages, deep link to
    the relevant group, and unlock the 30-day streak on refresh.

## UI & Stability

*   Unify typography, spacing, and ink responses across buttons, chips, drawers,
    and list tiles for a more consistent look.
*   Capitalize comment inputs, widen tap targets for comments and switches, and
    tighten bottom navigation and drawer layouts.
*   Fix signup flows that could see a transient null user and harden schedule
    editing tests along with related widget coverage.

# Release 1.14.0

This release overhauls Group Details progress, adds per‑chapter tracking with
cached overall completion, improves the Groups list UX (refresh, counts, and
delete), strengthens Firestore rules, and fixes streak/leaderboard accuracy.

## Highlights

*   Group progress is now group‑scoped and independent from the daily public feed.
*   Per‑chapter chips let you check/uncheck individual chapters for each day.
*   Overall member progress shows percentage across all scheduled days, backed
    by a cached summary that updates instantly on every toggle.

## Group Details

*   Per‑chapter chips under each schedule date with transactional writes to:
    *   `groups/{groupId}/progress/{dateId}/entries/{uid}/items/{index}`
    *   Maintains per‑day `count` on `entries/{uid}`
    *   Updates cached overall `completed` counter at
        `groups/{groupId}/progressSummary/data/entries/{uid}`
*   Overall progress bar now reflects sum of checked chapters across all dates
    divided by total scheduled chapters (not just one day).
*   Owner always appears in the Members list (read‑only unless owner/admin).
*   Removed the "(for yyyy-mm-dd)" suffix from the Members header.

## Groups List

*   Live member counts include admins and owner (streams `members` and adjusts
    count if the owner doc is missing).
*   Pull‑to‑refresh now:
    *   Reloads user session
    *   Validates and fixes the cached `progressSummary` for the signed‑in user
      by summing per‑day items and backfilling missing per‑day counts
*   Owners can delete groups (with confirmation). Deletion cleans up:
    members, schedule, joinRequests, progress (entries/items), and the group doc.

## Parsing & History

*   ReferenceParser: supports shorthand like `deut 28-31` expanding to each
    chapter.
*   History week/month views backfill from `read_logs` when per‑user reading
    docs are missing, avoiding undercount until navigation.

## Leaderboard & Streaks

*   Writing to the public feed also updates `users/{uid}/reading/{date}` to keep
    streak calculations accurate.
*   Summary/streak backfills from `read_logs` to avoid "1‑day" streaks when
    history exists only in the feed.

## Firestore Rules

*   Allow group creation by any signed‑in user; restrict updates/deletes to
    owner/admin.
*   Group progress:
    *   Read/write for `progress/{date}/entries/{uid}` and `items/{index}`
      (members write own, owner/admin can read/delete for cleanup)
    *   Cached summary at `progressSummary/data/entries/{uid}` (member write own,
      owner/admin can delete)
*   Join Requests: allow the requesting user to read their own join requests via
    collectionGroup queries.

## Cleanup & Integrity

*   Schedule deletion decrements affected users' cached totals and removes per‑day
    entries/items.
*   Leaving a group removes the user's `progressSummary` entry and their per‑day
    progress entries/items.

## Miscellaneous Fixes

*   Non‑members viewing a group no longer see member load failures (graceful
    fallback when progress permissions are denied).
*   Fixed a typo in progress stream initialization.

# Release 1.13.0

This release launches seasonal challenges with limited-time rewards and richer
notifications.

## Features

*   **Seasonal Challenges Tab:** Adds a dedicated Seasonal page and home dashboard
    summary fed by Firestore so players can join rotating challenges, monitor
    progress, and claim bespoke rewards without app updates.
*   **Reward Claim Flow:** Introduces the `SeasonalChallengeService` and a
    `claimSeasonalChallengeReward` Cloud Function to gate reward eligibility,
    record claims under each user, and surface a confirmation notification.

## Notifications

*   **Seasonal Challenge Alerts:** New `seasonalChallenge` notification type with a
    matching preference toggle so users control whether reward-ready push messages
    are delivered.

# Release 1.12.0

This release adds haptic feedback across the app, improves notification handling for friend requests, streamlines group join requests, and enhances navigation behavior and test coverage.

## Features

*   **Haptics and Vibration Service:** Introduces a centralized `VibrationService`, a reusable `VibrationButton` widget, and a user setting to enable/disable vibrations. Haptic feedback is now wired into main navigation, app drawer, friends and groups pages, add friend flow, auth pages, notification center, and common controls like menu/notification buttons and read switch tiles. Haptics are enabled by default.
*   **Notification Handling:** Creates and prunes friend request notifications to avoid stale entries, and covers empty/failure cases.
*   **Group Join Requests:** Adds join-request flow and owner notifications, with corresponding Firestore rules and service methods.
*   **Navigation Behavior:** Tracks navigation history, handles back button behavior, and hides the bottom navigation on non-core pages when appropriate.
*   **Crashlytics (iOS):** Integrates Firebase Crashlytics into the iOS build.

## Enhancements

*   **Tests & Stability:** Expands widget and service tests (navigation visibility, Firebase messaging token caching, daily notification behavior, error logging edge cases, achievements/streak widgets, drawer interactions). Initializes Firebase in tests and prevents unintended network calls in vibration tests.
*   **Dependencies:** Adds `device_info_plus` to support platform-specific behavior (locked in `pubspec.lock`).
*   **UI Polish:** Small refactors to keep bottom navigation visible when expected and to smooth navigation transitions.

## Fixes

*   **Stale Notifications:** Cleans up outdated friend request notifications.
*   **Daily Reminder Scheduling:** Fixes scheduling edge cases to improve reliability.

## Documentation

*   Clarifies vibration capabilities and settings, group joining workflow, and programmatic checks; adds a quick-fix guide and streamlines setup docs.

# Release 1.11.0

This release includes a major refactoring of the codebase, new features, bug fixes, and documentation updates.

## Features

*   **Network-hosted assets:** The app now uses network-hosted assets for images and animations, reducing the app size and improving performance.
*   **History Page:** A new history page has been added to view your reading history.
*   **"More" Sheet:** A new "More" sheet has been added to the main navigation for less frequently used items.
*   **Network Achievement Icons:** The app now supports network-hosted achievement icons.

## Enhancements

*   **Refactored Calendar Widgets:** The calendar widgets have been refactored for better performance and maintainability.
*   **Simplified Home Page:** The home page has been simplified to improve the user experience.
*   **Improved Data Migration:** The data migration script has been improved for better robustness.
*   **Updated Dependencies:** Dependencies have been updated to their latest versions.

## Fixes

*   **Hero Tag Conflicts:** Fixed hero tag conflicts that were causing issues with animations.
*   **Comment Drawer Tests:** Fixed issues with the comment drawer tests.
*   **Group Creation Exception:** Fixed an exception that was occurring when creating a new group.

## Documentation

*   **Updated README.md:** The README.md file has been updated with information about the new features and changes.
*   **New Documentation:** New documentation has been added for the new features.

# Release 1.10.0

This release introduces group reading challenge functionality so you can read with others and track progress together.

## Features

* **Group Reading Challenge:** Create or join a group challenge to follow the same reading plan and see collective progress.
* **Group Pages and Widgets:** New pages and widgets to display group information and reading schedules.
* **Group Service:** A new service to manage group data and interactions.
* **Group Models:** New data models for groups and schedules.

## Enhancements

* **Improved Testing:** Added a significant number of new tests for group functionality, friend requests, notifications, and UI components.
* **UI Improvements:** Refactored the comment section with scrolling and a new button style.

## Documentation

* **Updated AGENTS.md:** Added new instructions for Flutter analytics and Cloud Functions testing.



# Release 1.9.1

This release introduces comprehensive error reporting with Crashlytics, a major overhaul of the testing infrastructure, and several new features and improvements.

## Features

*   **Crashlytics Integration:** Integrated Firebase Crashlytics for advanced error reporting and monitoring to help identify and resolve issues faster.
*   **Comment Drawer:** The reading feed now includes a drawer to display comments, improving the user interface for discussions.
*   **Test Coverage Reporting:** Implemented code coverage reporting for both the main application and Cloud Functions to ensure better test quality.

## Enhancements

*   **User-Friendly Error Messages:** Replaced technical error messages with clearer, more helpful notifications.
*   **Improved Testing:** Migrated Cloud Functions tests to the Mocha framework and added a significant number of new unit and widget tests across the app.

## Fixes

*   **Silent Sign-In Notifications:** Ensured that notifications are scheduled correctly during silent sign-in, even if the Google sign-in process doesn't return a new user object.
*   **Friend Request Permissions:** Updated Firestore rules to allow users to manage their own friend requests.
*   **Cloud Function Tests:** Resolved several issues to improve the reliability of tests for Cloud Functions.

# Release 1.9.0

This release adds commenting to the reading feed, notifications for new comments, and an achievements page.

## Features

*   **Comments:** Users can now leave comments on reading log entries.
*   **Comment Notifications:** The new `sendCommentNotification` Cloud Function notifies you when someone comments on your reading.
*   **Achievements Page:** A new page to display earned badges.
*   **BadgeIcon Widget:** A new widget to display badges.

## Fixes & Enhancements

*   Improved error handling and messaging for friend requests.
*   The nudge button is now disabled if a nudge has already been sent to that friend today.
*   Emails are now stored in lowercase to prevent duplicate accounts.

# Release 1.8.0

This release introduces daily reminder notifications to help you stay consistent with your reading.

## Features

*   Users can now customize their notification preferences.

# Release 1.7.0

This release introduces a Notification Center, enhances the user experience with visual cues for first readers, and includes several under-the-hood improvements.

## Features

*   **Notification Center:** A new page to view and manage notifications.
*   **First Reader Recognition:** A trophy icon is now displayed for the first reader of the day.

## Enhancements

*   The friend requests button has been updated to a more general notification button.
*   Improved data handling with a new `AppNotification` model and `NotificationService`.

## Fixes

*   Resolved an issue with tests by properly injecting the `NotificationService`.
*   Removed unused code related to achievements.

## Security

*   Updated Firestore rules to support the new notification system.

# Release 1.6.0

This release introduces achievements and notification preferences.

## Features

*   **Achievements:** Users can now earn achievements for reading streaks and being the first to read for the day.
*   **Notification Preferences:** Users can now customize which notifications they receive.

# Release 1.5.3

This release introduces several new features, enhancements, and bug fixes to improve the user experience.

## Features

*   **First Reader of the Day:** The first person to read each day will now be specially marked.
*   **Signup Notifications:** New users will receive a notification upon signing up.
*   **Nudge Tracking:** The app now tracks sent nudges, disabling the button for the rest of the day to avoid spamming.
*   **Customizable Notifications:** Users can toggle which notifications they receive.

## Enhancements

*   **UI Animations:**
    *   Page transitions are now animated for a smoother experience.
    *   Navigation icons, the like icon, and the friend request badge are now animated.
    *   A new animated switch tile has been added.
*   **Friend Requests Button:** The friend requests button icon has been updated.
*   **Nudge Notification Status:** The app now returns a status from nudge notifications.
*   **Race Condition Prevention:** A transaction is now used when writing a read log to prevent race conditions.
*   **Leaderboard:** The signed-in user is now included in the friends leaderboard.

## Fixes

*   **Like Removal:** Users can no longer remove a like.
*   **Leaderboard Test:** The leaderboard friends tab test has been fixed.
*   **App Check:** The app now uses `appAttest` for the Apple provider in App Check.

# Release 1.5.2

This release includes minor updates and fixes.

## Updates

*   Updated `google-services.json` file.

# Release 1.5.1

This release includes bug fixes and improvements.

# Release 1.5.0

This release introduces a nudge feature and includes several important security and stability improvements.

## Features

*   **Nudge Notifications:** You can now send a "nudge" notification to a friend to remind them to read.

## Enhancements

*   **Improved Error Handling:** Added more robust error handling for various features, including Firestore writes, FCM messaging, and sign-out.
*   **Security Rules:** Updated and improved Firestore security rules for better data protection.

# Release 1.4.0

This release focuses on improving the user experience with a new friends leaderboard and optimistic UI updates for key interactions.

## Features

*   **Friends Leaderboard:** A new "Friends" tab has been added to the leaderboard, allowing you to see how you rank among your friends.

## Enhancements

*   **Optimistic UI Updates:**
    *   Liking a read log now provides immediate visual feedback, updating the UI before the network request completes.
    *   Toggling the "read" status is now instantaneous, making the interface feel more responsive.

# Release 1.3.0

This release introduces email and password authentication, allowing users to sign up and log in without a Google account. It also includes other enhancements and bug fixes.

## Features

*   **Email and Password Authentication:** Users can now create an account and log in using their email and password.
*   **Permanent Likes:** Likes on the reading feed are now persistent.

## Enhancements

*   **Home Page Optimization:** Improved the performance of the home page by avoiding unnecessary loading indicators when toggling the reading status.
*   **Refactored App Bar:** The app bar style has been updated to use theme colors for better consistency.

## Bug Fixes

*   **Sign-out:** Improved sign-out functionality and error logging.

# Release 1.2.3

This update introduces a complete friends system.

## Features

* Dedicated **Friends** page accessible from the bottom navigation bar.
* Floating **+** button to send friend requests by email.
* Notification icon shows the number of pending requests and opens the request list.
* Accept or decline requests directly from the new Friend Requests page.

# Release 1.2.2

This release introduces push notifications when your read log receives a like.

## Enhancements

* Stores the user's FCM token in Firestore after sign‑in.
* Cloud Function `sendLikeNotification` sends a push when another user likes your log.
* Incoming messages are shown using local notifications while the app is running.

# Release 1.2.1

This release includes minor updates and fixes.

## Updates

*   Updated `google-services.json` file.

# Release 1.2.0

This release focuses on improving the user experience by addressing loading states and ensuring consistent messaging across different sections of the app.

## Enhancements

*   **Improved Loading States:** Removed infinite loading indicators on the Feed, Leaderboard, and Home pages when the user is not signed in.
*   **Clear User Authentication Messaging:** Implemented a clear "User not signed in" message on the Feed, Leaderboard, and Home pages when the user is not authenticated, replacing previous loading states.
*   **Font Consistency:** Ensured the "User not signed in" message across all relevant pages uses the consistent `IBMPlexMono` font family.

# Release 1.1.0

This is the initial release of the Bible Reading Challenge app. This app is designed to help you stay motivated and consistent with your Bible reading. You can track your daily reading, build a streak, and see how you rank on the leaderboard.

## Features

*   **Daily Reading Tracker:** Mark each day that you read the Bible to build your streak.
*   **Weekly and Monthly Views:** See your reading progress at a glance with weekly and monthly calendar views.
*   **Leaderboard:** See how your reading streak compares to others.
*   **Reading Feed:** See who else has read the Bible today and give them a like to encourage them.
*   **User Profile:** Manage your profile information and sign in with your Google account.
