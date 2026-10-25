# Design QA Checklist

Use this at implementation review, to check that a build matches the design.
QA against the spec (the Claude Design prototype, `docs/community_journey_ia.md`
and the tokens in `lib/theme/app_theme.dart`), not from memory.

Tokens referenced below:
- **Color:** `colorScheme.*` (light/dark) and `AppColors.of(context)`:
  `primarySoft`, `primaryLine`, `accentSoft`, `border`, `borderStrong`, `bg2`,
  `scrim`, `sunLight`/`sunDeep`/`sunInk`.
- **Type:** `textTheme.*`. Spectral serif is used for `display`/`headline`/`titleLarge`,
  and Hanken Grotesk for everything else.
- **Spacing:** `AppSpacing.gap2…gap32`, `hPadding 20`, `cardPadding 18`.
- **Radius:** `rSmall 8 · rChip 12 · rButton/rField/rInset 16 · rCard 22 · rSheet 26 · rPill`.
- **Icon:** `iconSm 16 · iconMd 20 · iconLg 24`.
- **Size:** `buttonHeight 52`.

---

## 0. Developer self-review (before asking for design QA)

- [ ] `dart format lib test` and `flutter analyze` are clean.
- [ ] `flutter test test/design_tokens_guardrail_test.dart` passes. It rejects
      hex `Color(0x…)`, literal `BorderRadius.circular(n)` and heavy `FontWeight`
      values. Every `// token-exempt:` comment gives a real reason.
- [ ] No new `fontSize:` literal outside the type scale, and no new `BoxShadow`
      (use `AppSpacing.cardShadow`). The guardrail test does not catch either.
- [ ] Every bottom sheet goes through `showAppSheet`. No hand-rolled sheet chrome.
- [ ] Any golden that changed was regenerated on purpose
      (`flutter test --update-goldens test/goldens`) on the CI platform. The diff
      PNGs were looked at, not just accepted.
- [ ] You have 1–2 renders of the final state, in light and dark (AGENTS.md §5).
      No videos.

## 1. Visual accuracy

- [ ] All colors come from `colorScheme` or `appColors`. Nothing is hardcoded
      for one theme only (the past bug: light `tertiary` gold in dark mode,
      `reschedule_page`).
- [ ] The gold sun mark is drawn with `SunMark`, never a repeated gradient.
- [ ] Each text role uses the right font family. Serif is only for headlines
      and section titles (`titleLarge`). Meta and captions use
      `labelMedium`/`bodySmall` in `onSurfaceVariant`.
- [ ] Font weight is at most `w700`.
- [ ] Radii follow the scale: cards 22, sheets 26, buttons/fields/insets 16,
      chips 12. None of the old drift values (14, 20, 28).
- [ ] Cards use `cardPadding` (18) and `cardShadow`. The card surface matches
      its siblings on the same screen.
- [ ] Icons use `iconSm`/`iconMd`/`iconLg`. Each icon's color matches the text
      it labels.
- [ ] Dividers come from `dividerTheme`. No ad-hoc `Divider(color: …)`.
- [ ] Dialogs, snackbars and chips use the theme defaults (rCard, floating,
      rChip). Call sites don't override them.
- [ ] The auth hero image (`authHeroAssetPath`) is crisp on 3x screens and not
      stretched.

## 2. Layout

- [ ] The screen gutter is `hPadding` (20) on every tab: Today, Circle, Path.
- [ ] Section rhythm: 32 between sections, 12–16 between a section header and
      its content. Section headers use `SectionHeader`.
- [ ] Secondary rows line up on one left edge (icon column and text column).
- [ ] Content isn't hidden by the bottom `AppNavBar` or the system gesture bar.
      The last item can scroll fully into view.
- [ ] On wide screens (`ResponsiveScaffold`), the `NavigationRail` replaces the
      bottom bar and content has a sensible max width, not edge to edge.
- [ ] Nothing overflows. Watch for the yellow/black overflow stripe in debug
      builds, especially in rows that hold names, plan titles or book names.
- [ ] Rotation and split-screen don't clip sheets or dialogs.

## 3. Interaction & states

For each interactive component, check: **default · pressed · focused ·
disabled · loading · selected**.

- [ ] Touch targets are at least 48×48 dp on Android and 44×44 pt on iOS. This
      matters most for icon buttons, Amen/Nudge, calendar day cells and list
      row trailing actions.
- [ ] Buttons are `buttonHeight` (52) tall, and the disabled style is
      noticeably different from enabled.
- [ ] Optimistic UI: mark-as-read, likes/Amen and manual book tracking update
      at once. If the backend call fails (try airplane mode), the change rolls
      back and a SnackBar appears.
- [ ] Skeletons stay up for at least 1000 ms (`SkeletonLoader.minTime`).
      Page and section titles stay visible while their content loads.
- [ ] Haptics fire where expected and respect the Vibration setting.
- [ ] Sheets: the drag handle works, tapping the scrim dismisses, and the
      keyboard pushes the sheet up instead of covering inputs.
- [ ] Back gesture or button from every pushed page lands where you came from.
- [ ] Transitions feel consistent with other screens: same durations,
      `animatedPageRoute()` for pushes.

## 4. Content

- [ ] Uses real data: long display names, 3-digit streaks, long plan titles,
      "Song of Solomon", groups with 1 member and with 50+.
- [ ] Truncation is deliberate. Ellipsis on names and titles, no mid-word
      clipping, and nothing that should wrap is cut off.
- [ ] Empty states: new user with no reads, Circle with no group, Path with
      no plan, no notifications.
- [ ] Error states: offline (`AmbientSyncIndicator`), App Check failure, sign-in
      failure. The copy is human and says what to do next.
- [ ] Copy matches the agreed wording, for example "Reading counts as showing
      up". The design bundle may have older text.
- [ ] Casing follows conventions: sentence case for buttons ("Sign out") and
      title case only where the design uses it.
- [ ] The version label in Settings shows the release version.
- [ ] Dates, plurals ("1 day" vs "2 days") and the season vs. all-time totals
      are labeled correctly (#780).

## 5. Accessibility

- [ ] Text contrast meets WCAG AA (4.5:1 body, 3:1 large text and icons) in
      **both** themes. Check gold-on-`accentSoft` and `onSurfaceVariant` meta
      text in dark mode closely.
- [ ] TalkBack/VoiceOver: every icon-only button has a label, decorative
      images are excluded, and custom widgets (calendar, streak box, progress
      ring) announce what they mean, e.g. "Streak, 12 days".
- [ ] Reading order follows visual order, and grouped rows read as one item.
- [ ] Focus moves into a sheet or dialog when it opens and returns to the
      opener when it closes.
- [ ] **Reduced motion:** turn on "Remove animations" (Android) or "Reduce
      Motion" (iOS). Celebration, success and Lottie animations should be
      skipped or shortened. *Known gap: no code reads
      `MediaQuery.disableAnimations` yet.*
- [ ] State is never shown by color alone. "Read" and "missed" also differ in
      icon or text.

## 6. Cross-platform

- [ ] Check every reviewed screen on **iOS and Android**, in **light and dark**.
- [ ] Check text scale at **1.0, 1.3 and 2.0** (OS font size). Layouts reflow
      rather than overflow, and nothing gets clamped so small it can't be read.
- [ ] Check a small phone (≈360 dp wide), a large phone, and a tablet or
      foldable (the rail layout).
- [ ] Check screen density at 2x and 3x: badges, the sun mark and the auth
      hero are not blurry.
- [ ] Safe areas: notch and Dynamic Island, the Android gesture bar, and the
      keyboard on login, signup and feedback.
- [ ] Platform conventions: the iOS back swipe works, and the Android
      predictive back gesture doesn't skip a screen.
- [ ] Verify on emulators/simulators or renders before merge. Check on a real
      device only after the internal-track release.

## 7. Screen matrix

Fill in one cell per screen: ✅ pass, ⚠️ minor, ❌ blocking, — not applicable.

| Screen | Visual | Layout | States | Content | A11y | Light/Dark | Text 2.0 |
|---|---|---|---|---|---|---|---|
| Welcome / auth selection | | | | | | | |
| Login / signup | | | | | | | |
| Today (unread → read) | | | | | | | |
| Check-in / reflect sheet | | | | | | | |
| Circle (group, feed, Amen/Nudge) | | | | | | | |
| Join by code / share code | | | | | | | |
| Path (plans, read-throughs, badges) | | | | | | | |
| Plan detail / create plan / adjust pace / reschedule | | | | | | | |
| Bible progress | | | | | | | |
| Streak history / calendars | | | | | | | |
| Notifications center & settings | | | | | | | |
| Settings / profile sheet | | | | | | | |
| App menu & bottom sheets | | | | | | | |

## 8. Filing and prioritizing bugs

File each issue on GitHub (`gh issue create`) with a **design vs. build**
screenshot pair, the screen, the platform/theme/text scale, and the token
that should have been used.

| Severity | Meaning | Example |
|---|---|---|
| **P0** blocking | Broken, unreadable, or inaccessible | Contrast fails in dark mode, overflow stripe, target under 40 dp |
| **P1** visible | Clearly off-spec; users would notice | Wrong radius or sheet style, misaligned gutter, wrong copy |
| **P2** polish | Only noticeable side by side | A gap off by 2–4, icon 18 vs 20 |

Agent-ready fixes get `ready-for-agent` with acceptance criteria
(see `docs/agents/triage-labels.md`). Retest each fix on the platform and
theme where it was found, then close the issue.

## 9. Recurring issues (from the token audit) — check these first

1. A color hardcoded for one theme only.
2. Components built by hand instead of using the shared one (sheets, the sun
   mark, dividers, dialogs).
3. Radius drift (14, 20, 28).
4. Off-scale `fontSize` literals in older pages.
5. Icon sizes outside `iconSm`/`iconMd`/`iconLg`.
6. Motion durations hand-picked per widget. There is no motion token yet.

When something on this list keeps coming back, add a rule to
`design_tokens_guardrail_test.dart` instead of catching it by hand.
