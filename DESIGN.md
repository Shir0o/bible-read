---
name: Bible Read Design System
description: "The Sanctuary Liturgy & Canonical Hours: sacred stillness, canonical light, and gentle presence for daily Scripture reading."
colors:
  primary: "#6a53ad"
  primary-dark: "#c6b4ec"
  primary-press: "#5b449e"
  accent: "#9e7428"
  accent-luminous: "#e5be78"
  accent-soft-light: "rgba(212, 163, 89, 0.16)"
  accent-soft-dark: "rgba(229, 190, 120, 0.18)"
  surface-light: "#fffffa"
  surface-dark: "#1e1a26"
  bg-light: "#f4f0e8"
  bg-dark: "#16141d"
  text-light: "#231e2c"
  text-light-dim: "#6c6577"
  text-dark: "#ece7f3"
  text-dark-dim: "#a39cb3"
  border-light: "rgba(43, 33, 58, 0.085)"
  border-dark: "rgba(255, 255, 255, 0.11)"
typography:
  display:
    fontFamily: "Spectral, Georgia, serif"
    fontSize: "32px"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Spectral, Georgia, serif"
    fontSize: "24px"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "-0.3px"
  title-serif:
    fontFamily: "Spectral, Georgia, serif"
    fontSize: "19px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "-0.2px"
  title-sans:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  button:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.2
  chip:
    fontFamily: "Hanken Grotesk, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.2px"
rounded:
  card: "22px"
  button: "16px"
  field: "16px"
  inset: "16px"
  chip: "12px"
  sheet: "26px"
spacing:
  unit: "8px"
  gap4: "4px"
  gap8: "8px"
  gap12: "12px"
  gap16: "16px"
  gap20: "20px"
  gap24: "24px"
  hPadding: "20px"
  vPadding: "16px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#ffffff"
    rounded: "{rounded.button}"
    height: "52px"
  button-accent:
    backgroundColor: "{colors.accent}"
    textColor: "#ffffff"
    rounded: "{rounded.button}"
    height: "52px"
  card-surface:
    backgroundColor: "{colors.surface-light}"
    rounded: "{rounded.card}"
    padding: "18px"
---

# Design System: The Sanctuary Liturgy & Canonical Hours

## Overview

Bible Read embodies **The Sanctuary Liturgy & Canonical Hours**: an aesthetic world rooted in monastic rhythm, contemplative stillness, and reverent sacred text. It replaces transactional, high-anxiety gamification with graceful daily habits.

- **Presence over Performance**: No red warning badges, guilt-inducing streak breaks, or alarmist copy. Missed days are caught up on gently with warm gold feedback.
- **Canonical Light**: Time-of-day sky transitions (Dawn, Day, Dusk, Night) anchor the daily Check-in moment to the real world's natural liturgical rhythm.
- **Sacred Typographic Pairing**: Classical, warm-serif `Spectral` carries Scripture passages, titles, and celebrations; crisp humanist `Hanken Grotesk` carries UI chrome, labels, and actions.

## Colors

The palette derives from monastic stone cloister materials, liturgical beeswax candles, and twilight vestments.

### Light Mode (Sanctuary Limestone)
- **Background (`surface`)**: `#F4F0E8` (warm natural limestone / parchment).
- **Cards (`surfaceContainerLowest`)**: `#FFFFFA` (bright warm paper) with subtle hairline border.
- **Primary Accent (`primary`)**: `#6A53AD` (vesper lavender).
- **Grace & Habit Accent (`tertiary`)**: `#9E7428` (warm beeswax gold, high-contrast solid) and `#D4A359` (beeswax gold tint for containers).
- **Text (`onSurface`)**: `#231E2C` (iron stone charcoal, >12:1 contrast ratio).
- **Muted Text (`onSurfaceVariant`)**: `#6C6577` (incense slate, >4.5:1 contrast ratio).
- **Borders & Dividers**: `rgba(43, 33, 58, 0.085)` hairline (`AppColors.border`).

### Dark Mode (Compline Aubergine)
- **Background (`surface`)**: `#16141D` (deep aubergine stone).
- **Cards (`surfaceContainerLowest`)**: `#1E1A26` (raised dark stone panel).
- **Primary (`primary`)**: `#C6B4EC` (soft illuminated lavender).
- **Grace & Habit Accent (`tertiary`)**: `#E5BE78` (luminous candle gold).
- **Text (`onSurface`)**: `#ECE7F3` (soft night vellum, >11:1 contrast ratio).
- **Muted Text (`onSurfaceVariant`)**: `#A39CB3` (night slate, >5:1 contrast ratio).
- **Borders & Dividers**: `rgba(255, 255, 255, 0.11)` hairline (`AppColors.border`).

## Typography

Typographic hierarchy cleanly separates reading from UI operation.

- **Spectral** (Serif): Used for all literary, reflective, and sacred text.
  - Display / Celebration: 32px / Medium (500) / tracking -0.5px.
  - Headlines: 24–26px / Medium (500) / tracking -0.3px.
  - Section Titles (`titleLarge`): 19px / Medium (500) / tracking -0.2px.
- **Hanken Grotesk** (Humanist Sans): Used for navigation, inputs, and button actions.
  - Screen Titles / UI Headers (`titleMedium`): 16px / SemiBold (600).
  - Body Large: 15px / Regular (400) / 1.5 line height (65–75 character measure).
  - Body Medium: 14px / Regular (400) / 1.45 line height.
  - Button Text (`labelLarge`): 15px / SemiBold (600).
  - Chips & Tabs (`labelMedium`): 13px / SemiBold (600) / tracking +0.2px.
  - Metadata / Kicker (`labelSmall`): 11px / Bold (700) / tracking +1.6px uppercase.

## Layout

A unified 3-tab architecture optimized for focused thumb interaction:

- **Today**: Daily readings, full-screen ambient sky Check-in access, consistency glimpse, and quick catch-up access.
- **Circle**: Community presence showing who has shown up today with one-tap encouraging nudges.
- **Path**: Reading plan lifecycle management (solo & shared), whole-Bible book coverage, and read-through badges.
- **Responsive Adaptation**:
  - Compact widths (<600dp): Clean bottom navigation bar with customized icon glyphs (`TodayGlyph`, `CircleGlyph`, `PathGlyph`).
  - Wide widths (≥600dp / tablets): Left navigation rail with unselected state dimming and primary-colored active glyphs.

## Elevation & Depth

- **Tonal Layering**: Depth is created primarily through tonal contrast between the limestone ground and paper card surfaces.
- **Soft Shadows**: Card shadows use a 12px blur with a 4px vertical offset at low opacity (`rgba(0,0,0,0.05)` in light, `rgba(0,0,0,0.25)` in dark).
- **Hairline Framing**: Surfaces are bounded by a 1px border (`AppColors.border`) to ensure edge definition on high-DPI displays.

## Shapes

Generous, organic rounded geometry conveys softness and approachability without feeling childish:

- Cards: `BorderRadius.circular(22.0)`.
- Buttons & Text Fields: `BorderRadius.circular(16.0)`.
- Bottom Sheets: `BorderRadius.vertical(top: Radius.circular(26.0))`.
- Interactive Chips & Tabs: `BorderRadius.circular(12.0)`.
- Touch Targets: Buttons maintain a strict minimum height of `52.0` (exceeding WCAG 2.2 and HIG minimums).

## Components

- **SunMark**: A golden sun disc icon indicating daily presence (`done: false` as a clean gold disc; `done: true` with an inscribed checkmark).
- **Check-in Sky**: Ambient morning-to-night gradient changing dynamically by time of day (Dawn, Day, Dusk, Night) with gentle sun illumination.
- **Read-Through Cards**: Tracks whole-Bible and Testament laps with illuminated magnitude indicators.
- **Badge Strips**: Durable milestone badges awarded for completed passes through Scripture, rendered with letterpress seal aesthetics.
- **Catch-up Banners**: Golden, guilt-free callouts highlighting unread past passages with zero red or overdue styling.

## Do's and Don'ts

### Do:
- **Do** frame habit tracking as "showing up" rather than a score or test of performance.
- **Do** use warm gold (`#9E7428` / `#D4A359`) and gentle encouraging copy when a reader is behind schedule.
- **Do** ensure all interactive controls have at least 48×48 dp / 44×44 pt accessible touch targets.
- **Do** keep page and section headers persistently visible during skeleton loading (minimum 1000ms duration).

### Don't:
- **Don't** use red warning colors, broken chain graphics, or alarmist notifications for missed readings.
- **Don't** use generic hard-drop shadows, neon glowing borders, or arbitrary gradients.
- **Don't** introduce gamified confetti explosions, scoreboards, or competitive ranking among Circle members.
- **Don't** violate domain terms from `CONTEXT.md` (never use "assignment", "portion", "achievements", or "group plan").
