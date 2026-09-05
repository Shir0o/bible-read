# Store assets

App Store and Play Store screenshots, built from **real captures of the running
app** rather than redrawn mockups. Everything here is regenerable from what is
committed — you should never have to start from scratch.

## The short version

| I want to… | Do this |
|---|---|
| Change a caption | Edit `ARTBOARDS` in `build_artboards.py`, then `python3 render_store_assets.py` |
| Re-render all PNGs | `python3 render_store_assets.py` |
| Update the design canvas | `python3 build_artboards.py`, then re-seed (see below) |
| Change what a screenshot *shows* | Edit the seed in `integration_test/store_capture_test.dart` and re-capture |
| Add a store size | Add a call in `render_store_assets.py::main()` |

Only the last one needs a device. Everything else runs offline in seconds off
the committed captures.

## Layout

```
captures/            full-resolution phone captures (COMMITTED — see below)
captures/tablet/     full-resolution tablet captures (COMMITTED)
build_artboards.py   captions + canvas geometry; writes the .dc.html artboards
composite.py         diagonal / vertical splits, and canvas-sized shrinks
render_store_assets.py   final PNGs at store resolution + the zip
out/                 rendered output (generated, gitignored)
*.dc.html, *.jpg     generated for the canvas (gitignored, except DirectionC)
```

**Captions live in exactly one place** — `ARTBOARDS` in `build_artboards.py`.
`render_store_assets.py` imports them, so the canvas and the shipped PNGs cannot
drift apart.

## Why captures are committed

They are date-stamped: the frames bake in the capture day ("SATURDAY ·
SEPTEMBER 5") and day 14 of the plan relative to that date. Re-running the
harness later reproduces the *design* but not the *images*. Committing them
keeps caption edits and new store sizes a one-command job forever. They are
~6 MB total; the rendered output is not committed because it is deterministic
from these plus the scripts.

## Sizes, and the traps

| Asset | Size | Note |
|---|---|---|
| App Store 6.9" | 1290×2796 | **Confirmed accepted** by App Store Connect. Apple's docs list conflicting numbers — trust this one. |
| Play phone | 1080×2160 | Play caps the long edge at **2× the short edge**. A raw 20:9 capture (Pixel 10 Pro is 1080×2410, 2.23:1) is rejected. |
| Play 7" tablet | 1080×1920 | **Exactly** 16:9 or 9:16 — stricter than the phone slot. Sides 320–3840. |
| Play 10" tablet | 1440×2560 | Exactly 9:16, and both sides must be ≥1080. |
| Play feature graphic | 1024×500 | PNG/JPEG, under 15 MB. |

Tablet slots need their own captures: `ResponsiveScaffold` switches to a side
`NavigationRail` above 600dp, so a tablet screenshot showing the phone's bottom
nav bar would show a UI the app never renders at that size. Both 7" and 10"
land on the same side of that single breakpoint, so one tablet capture serves
both slots.

### Tablet captures

`captures/tablet/` comes from the `Play_Tablet` AVD (medium_tablet, android-36)
in portrait at 1600x2560. The AVD's natural orientation is landscape and the app
locks no orientation, so rotation is forced before capturing:

```sh
~/Library/Android/sdk/emulator/emulator -avd Play_Tablet -no-snapshot-load &
adb -s emulator-5554 shell settings put system accelerometer_rotation 0
adb -s emulator-5554 shell settings put system user_rotation 1
flutter drive -d emulator-5554 --no-enable-impeller \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/store_capture_test.dart
```

The AVD needs roughly 7.4 GB free to boot — it refuses outright below that.

## Re-capturing

```sh
flutter drive -d <device> \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/store_capture_test.dart
```

Then move the PNGs from `screenshots/` into `captures/`, rebuild the splits with
`composite.py`, and re-render.

Two capture traps, both real and both already handled in the harness:

1. **Android freezes its capture surface.** After the first screenshot the
   `FlutterImageView` stops refreshing and every later frame is a duplicate.
   Pass `--no-enable-impeller`. iOS needs no surface conversion and is unaffected.
2. **`HomePage` auto-opens `CheckInPage`** on launch when today is unmarked, and
   it covers every screen you are trying to capture. The harness dismisses it
   through its `onClose` before the Home/Journey/Community frames.

`flutter drive` exits non-zero on the tablet run even when every capture is
good: `firebase_auth_mocks` gives its mock user a photo URL on i.stack.imgur.com
that 403s, and the resulting image exceptions are reported at teardown. The
avatar falls back to a plain circle. Check the PNGs before assuming a failure.

The seed also makes the user the **owner** of the group. That is a workaround for
[#779](https://github.com/Shir0o/bible-read/issues/779) — `groupsForUser()` emits
an empty list first, and `HomePage._loadGroup` samples only that first event, so
a non-owned group silently never reaches "Today's reading". Remove the workaround
when that is fixed.

## Design canvas

`build_artboards.py` writes `.dc.html` artboards plus `canvas.json` for a Claude
Design canvas. The seeded `bible-read-store-screenshots.html` is a ~3 MB
generated payload and is gitignored — re-seed it from these sources rather than
committing it.

## Copy caveat

Captions are drafts, and the cast (Sam, Naomi, Elias, Ruth, Jonah, Miriam;
"Morning Light") is invented. One caption constraint is load-bearing: the
check-in payoff's big number is an all-time total, not a streak and not
season-scoped — see [#780](https://github.com/Shir0o/bible-read/issues/780) and
the "Known conflict" note in `CONTEXT.md`.
