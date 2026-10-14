# Design Token Audit — 2026-10-14

Scope: `lib/` (178 Dart files, excluding `lib/theme/` and `firebase_options.dart`).
Tokens: `lib/theme/app_theme.dart` — `ColorScheme` (light/dark), `AppColors`
extension, `AppSpacing` (gap scale, radii, `buttonHeight`, `cardShadow`), and the
`TextTheme` type scale.

## Executive summary

| Category | Via token | Literal | Adoption | Verdict |
|---|---:|---:|---:|---|
| Color | 1,048 | 72 hex | **94%** | Healthy. 56 of the 72 are intentional illustration palettes. |
| Typography | 298 `textTheme.*` | 102 `TextStyle(` · 103 `fontSize:` | **~75%** | 25 distinct font sizes against a 12-step scale. |
| Radius | 83 | 128 | **39%** | 12 off-scale values; three sheet radii. |
| Spacing | 72 | ~870 | **8%** | 66% of literals already sit on the 4/8/12/16/20/24 scale. |
| Icon size | 0 | 150 | **0%** | 25 distinct sizes, no tokens. |
| Shadow | 1 `cardShadow` | 9 `BoxShadow` | **10%** | Each sheet/card hand-rolls its own. |
| Motion | 0 | 41 durations | **0%** | 16 distinct durations. |

**The visible inconsistency comes from components, not colors.** Color is
almost fully tokenized. What changes from screen to screen is shape (radii),
rhythm (spacing), and type size, plus a handful of components built three
different ways (bottom sheets, the gold sun mark, dividers, dialogs).

## Findings by priority

### P0 — visible bugs / duplicated components

1. **Hardcoded light-mode gold in dark mode.** `pages/reschedule_page.dart:340,345`
   uses `Color(0xFFA0702F)` (light `tertiary`) for the warning icon and title, so
   in dark mode it renders dark-gold on aubergine and fails contrast.
   → Replace with `colorScheme.tertiary`, or with `onTertiaryContainer` since it
   sits on `accentSoft`.

2. **The gold sun mark is implemented 4 times.** `widgets/sun_mark.dart` exists,
   but `widgets/feed_card.dart:219`, `widgets/journey/badge_strip.dart:160` and
   `pages/read_throughs_page.dart:325` each repeat the same gradient
   (`FFE9A8 → FFC24D`) and `0xFF2A2438` border. Border widths already differ
   (2 vs 1.5).
   → Reuse `SunMark` (add a `borderWidth` param if needed), or move the three
   colors into `AppColors` as `sunGradient` / `sunInk`.

3. **Three bottom-sheet styles.**
   | Style | Top radius | Files |
   |---|---|---|
   | `showAppSheet` (canonical) | `rSheet` 26 | start_chapter, group_preview, empty_group_state, reflect_sheet* |
   | Hand-rolled container | **28** + own `BoxShadow` | nudge_sheet, app_menu_sheet, group_members_page |
   | Material `showDragHandle` | M3 default (28) on `surface` | sync_sheet, create_plan_page, plan_detail_page |

   \*`reflect_sheet` hand-rolls the same chrome as `showAppSheet` at `rSheet`.
   → Migrate all 7 to `showAppSheet`.

4. **Missing component themes in `ThemeData`.** No `dialogTheme`,
   `snackBarTheme`, `bottomSheetTheme`, `chipTheme` or `dividerTheme`. As a result:
   - 15 `AlertDialog`s in 11 files use the M3 defaults (28 radius, tinted
     surface), which don't match the cards (22) or sheets (26).
   - 118 `SnackBar`s: only 1 is floating, the rest are fixed.
   - 14 `Chip`s use M3 default chip shape (8 radius) rather than `rChip` 12.
   - `Divider` is used 8 different ways (`outlineVariant`, `appColors.border`,
     `primaryLine`, default).
   → Adding five theme entries in `app_theme.dart` fixes ~160 call sites without
   touching them.

### P1 — off-scale values (shape & type)

5. **Radius drift.** Scale is `rChip 12 · rButton/rField/rInset 16 · rCard 22 · rSheet 26`.
   | Literal | Uses | Likely intent | Main files |
   |---|---:|---|---|
   | 16 | 45 | on-scale → use `rInset` | everywhere |
   | **14** | 22 | between chip/inset | plan_detail, nudge_sheet, plans_hub, bible_progress, group_members, community |
   | 12 | 17 | on-scale → `rChip` | |
   | **20** | 10 | between inset/card | create_plan, home, schedule_screen_view, feed_card, profile_summary_card |
   | 8 / 4 | 13 | small (progress bars, tiles) | bible_progress, login/signup, bible_library_grid |
   | **28** | 3 | should be `rSheet` | group_members, app_menu_sheet, nudge_sheet |
   | 13, 11, 10, 9, 32, 3.5 | 10 | noise | sync_sheet, nudge_sheet, feedback_admin, group_card, catch_up_status_row |
   → Snap 14 and 20 to the scale (decision below), add `rSmall = 8` and
   `rPill = 999`, then replace all literals with `AppSpacing.r*`.

6. **Type-scale drift.** 25 distinct `fontSize` literals. Off-scale sizes (10, 10.5,
   11.5, 12, 14.5, 15.5, 16.5, 17, 18, 20, 21, 22, 27, 28) concentrate in:
   `widgets/journey/consistency_calendar.dart` (7), `pages/create_plan_page.dart`
   (7, plus 27 raw `TextStyle(`), `widgets/journey/bible_library_grid.dart` (4),
   `pages/group_members_page.dart`, `pages/check_in_page.dart`.
   → Map these to the nearest `textTheme` slot. `create_plan_page.dart` is the
   biggest single cleanup.

7. **Weight drift.** 227 `fontWeight` overrides; `FontWeight.bold` (46) and
   `w700` (24) are both used for "bold". The heaviest `.bold` users
   (bible_library_grid, create_plan_page, consistency_calendar, login_page)
   are the same files as #6.
   → Standardize on `w600` (emphasis) and `w700` (strong), and remove `.bold`,
   `w800` and `w900`.

8. **Faint text via ad-hoc alpha.** `onSurfaceVariant.withValues(alpha: …)` ×31
   with 8 different alphas (0.7 ×16). The design already has `--text-faint` =
   `colorScheme.outline`.
   → Replace the 0.5–0.8 cases with `colorScheme.outline`.

9. **Static text theme bypasses dark mode.** `widgets/common_styles.dart:14` and
   `widgets/status_refresh_indicator.dart:220` read `AppTheme.textTheme`, the
   static *light* text theme, not `Theme.of(context).textTheme`.

### P2 — rhythm & small metrics (largest volume, lowest per-site impact)

10. **Spacing.** ~870 literal gaps vs 72 token uses. Off-scale values: 10 (58),
    14 (54), 6 (38), 2 (32), 13 (29), 18 (21), 11 (14), 3, 9, 15. `width: 13`
    appears 17 times, almost certainly copied from one place. Worst files:
    `home_page.dart` (44 SizedBox / 14 EdgeInsets),
    `create_plan_page.dart` (36 / 25), `journey/plans_hub.dart` (32 / 15),
    `schedule_screen_view.dart` (26 / 13).
    → Add `gap2`, `gap6`, `gap32`. Snap 10→8|12, 14→12|16, 13/11→12,
    18→16|20. Prioritize the four files above.

11. **Icon sizes.** 25 distinct values. 20/18/16 cover 57%. Near-misses 19, 17,
    15, 13, 23.
    → Add `AppSpacing.iconSm 16 / iconMd 20 / iconLg 24` and snap.

12. **Shadows.** 9 hand-rolled `BoxShadow`s (sheets, login, check-in,
    celebration, action button), and `cardShadow` is used once.
    → Add `sheetShadow`; the rest are illustration-specific and fine.

13. **Motion.** 16 distinct durations. 1000ms ×11 are the skeleton minimum (keep).
    The rest cluster at 200/250/300.
    → Optional `AppMotion.fast 200 / base 300`.

## Intentional (don't tokenize)

- `pages/check_in_page.dart` (33 hex) and `widgets/read_through_celebration.dart`
  (19 hex): illustration gradients (sunrise sky, confetti).

## Recommended new tokens

```dart
// AppSpacing
static const double gap2 = 2;
static const double gap6 = 6;
static const double gap32 = 32;
static const double rSmall = 8;
static const double rPill = 999;
static const double iconSm = 16, iconMd = 20, iconLg = 24;
static List<BoxShadow> sheetShadow(BuildContext context) => [...];

// AppColors
final List<Color> sunGradient; // FFE9A8 → FFC24D
final Color sunInk;            // 2A2438
```

Plus `ThemeData`: `dialogTheme`, `snackBarTheme` (floating, `rChip`),
`bottomSheetTheme` (`rSheet`, `surfaceContainerLowest`), `chipTheme` (`rChip`),
`dividerTheme` (`appColors.border`, 1px).

## Migration plan

| Step | Change | Sites | Risk |
|---|---|---:|---|
| 1 | P0 #1 dark-mode gold, #9 static text theme | 4 | trivial |
| 2 | P0 #4 component themes in `app_theme.dart` | ~160 implicit | low; check golden tests |
| 3 | P0 #3 sheets → `showAppSheet`, #2 sun mark → `SunMark` | 10 | medium (sheet layouts) |
| 4 | P1 #5 radii, #8 faint text | ~160 | low |
| 5 | P1 #6–7 type in the 5 hotspot files | ~60 | medium (text wrapping) |
| 6 | P2 spacing/icons in the 4 hotspot files, then a long tail | ~400 | low per site |
| 7 | Guardrail: a test that fails on new `BorderRadius.circular(<num>)` / `Color(0x` outside `theme/` and allow-listed illustration files | — | — |

## Status — 2026-10-14

Done:
- Component themes (dialog, snackbar, bottom sheet, chip, divider) in `app_theme.dart`.
- Sheets unified on `showAppSheet`; sun mark moved to `SunMark` / sun tokens.
- Radii tokenized (14 to 16, 20 to 22 or pill); faint text moved to `outline`.
- Type scale applied in the hotspot files; heavy weights (bold, w800, w900) to w700.
- Off-scale spacing and icon sizes snapped to the scale; `AppSpacing.cardPadding` (18, per DESIGN.md) restored on card surfaces.
- Guardrail: `test/design_tokens_guardrail_test.dart` fails on `Color(0x`, literal radii and heavy weights outside `lib/theme/`; deliberate literals carry `// token-exempt: <reason>`.

Remaining:
- On-scale spacing literals are intentionally not tokenized.
- 18px button icons kept as the Material default.
- About 20 `fontSize` literals outside the hotspot files.
- Illustration files (`check_in_page.dart`, `read_through_celebration.dart`) are exempt.
- Motion and shadow tokens (P2) not done.
