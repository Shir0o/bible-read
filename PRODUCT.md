# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Primary users are individuals and community groups (church small groups, families, friends, and reading cohorts) seeking to establish and sustain a daily Bible reading habit. They are often reading in busy daily routines, navigating variable life schedules, and balancing personal spiritual disciplines with group accountability.

## Product Purpose

Bible Read exists to help people build and sustain a lifelong Scripture reading habit alongside others. Success means readers consistently show up in the Bible, maintain accountability with their Circle without guilt, and experience steady progress through whole-Bible and testament read-throughs.

## Positioning

"Presence over performance": unlike conventional habit-tracking and reading apps that penalize missed days with punitive streak resets, guilt trips, or overwhelming backlogs, Bible Read frames engagement around daily presence and grace. Missed readings are caught up on with gentle, gold visual cues (never red or alarming failure states), streaks track presence without shame, and group members encourage each other through lightweight nudges.

## Operating Context

- **Daily Check-in**: A full-screen moment on launch when today's reading is unmarked, featuring an ambient sky that shifts naturally across dawn, day, dusk, and night based on local time.
- **Three-Tab Architecture**:
  - **Today**: Daily readings, check-in status, consistency glimpse, and quick catch-up access.
  - **Circle**: Reading feed and group members showing who has shown up today, with one-tap encouraging nudges.
  - **Path**: Lifecycle management for reading plans (solo and shared), read-through progress, and badge milestones.
- **Reading Rituals**: Readers mark assigned daily passages as read, optionally record a one-per-day Reflection, and see real-time updates as fellow group members check in.

## Capabilities and Constraints

- **Platform Architecture**: Cross-platform Flutter application targeting iOS and Android, backed by Firebase (Firestore, Auth, Cloud Functions, Messaging, Crashlytics, App Check).
- **Core Domain Terminology** (strictly enforced per `CONTEXT.md`):
  - *Reading*: One day's assigned chapters in a plan or group schedule (never "assignment" or "portion").
  - *Shown up*: Having marked today's reading — framing presence rather than performance (never "completed" or "done for the day").
  - *Check-in*: Full-screen daily greeting reflecting time of day (never "prompt" or "nudge").
  - *Reflection*: Optional daily thought following check-in (never "journal" or "note").
  - *Streak*: Consecutive days shown up.
  - *Catch-up*: Marking past unmarked readings in any order with gold/gentle UI (never "backfill" or "make-up").
  - *In step*: Group state where members are on track with today's reading marked.
  - *Plan*: Dated reading sequence (solo or shared; never "group plan").
  - *Circle*: Readers shared across groups, derived automatically from group membership (never "friends" or "contacts").
  - *Nudge*: Friendly prompt to a Circle member who hasn't shown up today (never "poke" or "ping").
  - *Read-Through & Lap*: Tracking full testament or whole-Bible completions with milestone Badges (never "achievements" reader-facing).
- **Technical UI Constraints**:
  - *Optimistic UI Updates*: High-frequency interactions (marking readings, toggling reactions) update immediately with local state overrides, background sync, and rollback on failure.
  - *Skeleton Loaders*: Minimum 1000ms duration to prevent flashing, with page/section headers remaining persistently visible during loading.
  - *Design System*: Warm-paper light mode and deep-aubergine night mode, pairing Spectral (serif headings/scripture) with Hanken Grotesk (sans body/UI).

## Brand Commitments

- **Tone & Voice**: Warm, reverent, encouraging, unhurried, and gracious. Free of gamified panic, aggressive red alerts, or competitive pressure.
- **Identity Assets**:
  - Serif typography: `Spectral` (Light, Regular, Italic, Medium, SemiBold).
  - Sans UI typography: `Hanken Grotesk` (Variable font).
  - Primary color: Lavender (`#6A53AD`), Accent: Warm gold (`#A0702F`).
  - Dark mode: Deep aubergine (`#141218` / `#231E2C`).
  - Hero and badge assets bundled in `assets/`.

## Evidence on Hand

- Canonical domain documentation and glossary: `CONTEXT.md`.
- Architecture and technical standards: `PROJECT.md` and `AGENTS.md`.
- Architectural Decision Records: `docs/adr/`.
- Information architecture specifications: `docs/community_journey_ia.md`.
- Theme definitions and color tokens: `lib/theme/app_theme.dart`.
- Reading plans and assets: `assets/plans/`, `assets/fonts/`, `assets/icons/`, `assets/images/`.

## Product Principles

1. **Presence, Not Performance**: Showing up matters more than speed or perfect streaks. Falling behind is met with gentle encouragement and frictionless catch-up, never red warning badges or demoralizing resets.
2. **Community Without Pressure**: Group reading provides quiet companionship and mutual visibility ("in step"), not competitive scoreboards or intrusive social bloat.
3. **Respect for Sacred Scripture**: Typography, layout, and pacing honor the reading experience with elegant editorial serif typography, ample whitespace, and focused, distraction-free reading surfaces.
4. **Zero-Latency Trust**: Optimistic updates and graceful offline handling ensure interactions feel instant, tactile, and dependable.

## Accessibility & Inclusion

- Adherence to WCAG 2.2 touch target minimums (48×48 dp / 44×44 pt).
- High-contrast, first-class light and dark modes with comfortable readable measure.
- Responsive to platform text scale settings (Dynamic Type on iOS, font scale on Android).
- Reduced-motion compliance for screen transitions and check-in sky animations.
