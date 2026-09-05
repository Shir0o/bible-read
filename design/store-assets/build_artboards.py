#!/usr/bin/env python3
"""Generate the store-screenshot artboards and canvas.json for the design canvas.

Every artboard is direction A: warm paper, caption above, real device capture
cropped at the bottom edge. Only the caption and the image change, so they live
in ARTBOARDS below and this script writes the rest.

  python3 build_artboards.py
"""
import json
import pathlib

HERE = pathlib.Path(__file__).parent

# Two deliverable aspects, because the stores disagree:
#
#   App Store 6.9"  1290 x 2796  (0.461)  — confirmed accepted by App Store
#                                           Connect on upload; Apple's docs list
#                                           conflicting numbers, so trust this.
#   Play phone      1080 x 2160  (0.500)  — Play caps the long edge at twice
#                                           the short edge, so a raw 20:9 phone
#                                           capture (Pixel 10 Pro is 1080x2410,
#                                           2.23:1) is REJECTED. 1080x2160 is
#                                           the tallest legal Play frame and the
#                                           closest one to the App Store aspect.
#
# Artboards are drawn at ~37% of the App Store frame; the Play variant matches
# its own aspect at the same width so the two can be compared side by side.
FRAME_W, FRAME_H = 480, 1040          # App Store 6.9"
PLAY_W, PLAY_H = 480, 960             # Play phone
DEVICE_W = 380  # outer bezel width; the capture is cropped by the frame edge

PAPER = "#F4F0E8"
INK = "#231E2C"
DIM = "#6C6577"
GOLD = "#A0702F"
BEZEL = "#231E2C"

FONTS = (
    "https://fonts.googleapis.com/css2?"
    "family=Spectral:wght@300;400;500;600&"
    "family=Hanken+Grotesk:wght@400;500;600;700&display=swap"
)

# name, slot title, image file, headline (<br> allowed), sub-line
ARTBOARDS = [
    (
        "Main",
        "1 · Check-in",
        "checkin_split.jpg",
        "Did you<br>read today?",
        "The first thing the app asks. The sky behind it moves with the hour.",
    ),
    (
        "Home",
        "2 · Home",
        "home.jpg",
        "Two readings<br>behind. No alarm.",
        "Catch up in any order, whenever. Your group keeps reading beside you.",
    ),
    (
        "Streak",
        "3 · Journey",
        "journey.jpg",
        "A streak that<br>tells the truth.",
        "Days shown up, your current streak, and the whole month at a glance.",
    ),
    (
        "Community",
        "4 · Community",
        "community.jpg",
        "Read alongside<br>your group.",
        "See who has read today and what the group is on, without chasing anyone.",
    ),
    (
        "PlanDetail",
        "5 · Plan detail",
        "plan_detail_split.jpg",
        "The whole plan,<br>day by day.",
        "Every reading, what is done and what is waiting — in light or dark.",
    ),
    (
        "Reflection",
        "6 · Reflection",
        "reflection.jpg",
        "A sentence<br>is plenty.",
        "Note what stayed with you. The prompt changes from day to day.",
    ),
    (
        "Payoff",
        "7 · Check-in payoff",
        "payoff.jpg",
        "Thank you<br>for being here.",
        "Marked, and the day is done. The number is every day you have shown up.",
    ),
]

TEMPLATE = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="{fonts}">
  <style>
    body {{ margin: 0; font-family: 'Hanken Grotesk', system-ui, -apple-system, sans-serif; }}
    a {{ color: #6A53AD; }} a:hover {{ color: #5B449E; }}
  </style>
</helmet>
<div style="width: {fw}px; height: {fh}px; overflow: hidden; background: {paper}; display: flex; flex-direction: column; align-items: center; box-sizing: border-box;">

  <div style="display: flex; flex-direction: column; align-items: center; gap: 14px; padding: {pt}px 44px 0; text-align: center;">
    <div style="font-size: 11px; font-weight: 700; letter-spacing: 1.7px; color: {gold};">BIBLE READ</div>
    <div style="font-family: Spectral, Georgia, serif; font-size: 44px; font-weight: 500; line-height: 1.06; letter-spacing: -1.1px; color: {ink}; text-wrap: balance;">{headline}</div>
    <div style="font-size: 15.5px; line-height: 1.45; color: {dim}; max-width: 348px; text-wrap: pretty;">{sub}</div>
  </div>

  <div style="margin-top: 36px; width: {dw}px; flex: none; background: {bezel}; padding: 9px; border-radius: 48px; box-sizing: border-box; box-shadow: 0 30px 64px rgba(35, 30, 44, 0.24);">
    <div style="border-radius: 40px; overflow: hidden; line-height: 0;">
      <img src="{image}" alt="" style="display: block; width: 100%;">
    </div>
  </div>

</div>
</x-dc>
</body>
</html>
"""


# Play feature graphic: exactly 1024x500, PNG or JPEG, max 15 MB. Authored at
# 1:1 so the artboard IS the deliverable size. Play crops this for some
# surfaces, so nothing that matters sits in the outer ~8%.
FEATURE_W, FEATURE_H = 1024, 500

FEATURE_TEMPLATE = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="{fonts}">
  <style>
    body {{ margin: 0; font-family: 'Hanken Grotesk', system-ui, -apple-system, sans-serif; }}
    a {{ color: #6A53AD; }} a:hover {{ color: #5B449E; }}
  </style>
</helmet>
<div style="width: {fw}px; height: {fh}px; overflow: hidden; background: {paper}; position: relative; box-sizing: border-box;">

  <div style="position: absolute; left: 72px; top: 0; height: {fh}px; width: 560px; display: flex; flex-direction: column; justify-content: center; gap: 18px;">
    <div style="font-size: 12px; font-weight: 700; letter-spacing: 2px; color: {gold};">BIBLE READ</div>
    <div style="font-family: Spectral, Georgia, serif; font-size: 54px; font-weight: 400; line-height: 1.04; letter-spacing: -1.6px; color: {ink};">Reading counts as<br><span style="font-style: italic; color: #6A53AD;">showing up.</span></div>
    <div style="width: 56px; height: 2px; background: {gold};"></div>
    <div style="font-size: 17px; line-height: 1.5; color: {dim}; max-width: 430px; text-wrap: pretty;">A daily plan, a streak that tells the truth, and a group reading beside you.</div>
  </div>

  <div style="position: absolute; right: 196px; top: 74px; width: 208px; transform: rotate(-5deg); background: {bezel}; padding: 6px; border-radius: 30px; box-sizing: border-box; box-shadow: 0 26px 54px rgba(35, 30, 44, 0.26);">
    <div style="border-radius: 25px; overflow: hidden; line-height: 0;">
      <img src="{image_a}" alt="" style="display: block; width: 100%;">
    </div>
  </div>

  <div style="position: absolute; right: 28px; top: 128px; width: 208px; transform: rotate(4deg); background: {bezel}; padding: 6px; border-radius: 30px; box-sizing: border-box; box-shadow: 0 26px 54px rgba(35, 30, 44, 0.30);">
    <div style="border-radius: 25px; overflow: hidden; line-height: 0;">
      <img src="{image_b}" alt="" style="display: block; width: 100%;">
    </div>
  </div>

</div>
</x-dc>
</body>
</html>
"""


def write_feature_graphic():
    path = HERE / "FeatureGraphic.dc.html"
    path.write_text(
        FEATURE_TEMPLATE.format(
            fonts=FONTS,
            fw=FEATURE_W,
            fh=FEATURE_H,
            paper=PAPER,
            ink=INK,
            dim=DIM,
            gold=GOLD,
            bezel=BEZEL,
            image_a="checkin_split.jpg",
            image_b="home.jpg",
        )
    )
    print(f"wrote {path.name}")


def write_artboard(name, image, headline, sub, fw, fh, pad_top, device_w):
    path = HERE / f"{name}.dc.html"
    path.write_text(
        TEMPLATE.format(
            fonts=FONTS,
            fw=fw,
            fh=fh,
            pt=pad_top,
            dw=device_w,
            paper=PAPER,
            ink=INK,
            dim=DIM,
            gold=GOLD,
            bezel=BEZEL,
            headline=headline,
            sub=sub,
            image=image,
        )
    )
    print(f"wrote {path.name}")


def main():
    for name, _title, image, headline, sub in ARTBOARDS:
        write_artboard(name, image, headline, sub, FRAME_W, FRAME_H, 62, DEVICE_W)

    # The same slot at the Play aspect: a shorter frame, so the caption block
    # tightens and the device shows less before the crop.
    play = ARTBOARDS[0]
    write_artboard(
        "PlayPhone", play[2], play[3], play[4], PLAY_W, PLAY_H, 48, DEVICE_W
    )

    write_feature_graphic()

    # Row of seven on page 1; the surviving direction sketch on page 2.
    step = FRAME_W + 80
    canvas = {
        "artboards": [
            {
                "file": f"{name}.dc.html",
                "title": title,
                "x": i * step,
                "y": 0,
                "w": FRAME_W,
                "h": FRAME_H,
                "page": "page-1",
            }
            for i, (name, title, _img, _h, _s) in enumerate(ARTBOARDS)
        ]
        + [
            {
                "file": "PlayPhone.dc.html",
                "title": "1 · Check-in (Play ratio)",
                "x": len(ARTBOARDS) * step,
                "y": 0,
                "w": PLAY_W,
                "h": PLAY_H,
                "page": "page-1",
            },
            {
                "file": "FeatureGraphic.dc.html",
                "title": "Play feature graphic · 1024×500",
                "x": 0,
                "y": 0,
                "w": FEATURE_W,
                "h": FEATURE_H,
                "page": "page-2",
            },
            {
                "file": "DirectionC.dc.html",
                "title": "Portrait sketch (superseded)",
                "x": 0,
                "y": 660,
                "w": FRAME_W,
                "h": FRAME_H,
                "page": "page-2",
            },
        ],
        "annotations": [
            {
                "id": "brief",
                "x": 0,
                "y": -250,
                "w": 720,
                "page": "page-1",
                "text": (
                    "Bible Read — store screenshots\n\n"
                    "Seven frames in the order they run in the listing. Every phone image is a real "
                    "capture of the app, driven by integration_test/store_capture_test.dart with "
                    "seeded data — no redrawn UI.\n\n"
                    "Slot 1 is two captures of the same screen, dawn and night, cut on the diagonal. "
                    "Slot 5 is light and dark, cut on the vertical. Different cut, different claim.\n\n"
                    "SIZES. The first seven are the App Store 6.9\" aspect (1290×2796) at ~37%. "
                    "The eighth is the same slot at the Play phone aspect (1080×2160): Play refuses "
                    "anything taller than 2:1, so a raw 20:9 phone capture cannot be uploaded there "
                    "as-is. Both get composited at full resolution once the design is settled; the "
                    "Play feature graphic (1024×500) is on page 2."
                ),
            },
            {
                "id": "note-c",
                "x": 0,
                "y": -170,
                "w": 460,
                "page": "page-2",
                "text": (
                    "Play feature graphic — 1024×500, PNG or JPEG, under 15 MB.\n\n"
                    "Drawn at 1:1, so this artboard is the deliverable size: export the PNG and "
                    "upload it. Play crops this image on some surfaces, so the headline and rule "
                    "stay clear of the outer edges and the phones are the part that can lose a "
                    "sliver.\n\n"
                    "The portrait sketch below is what this grew out of; it is kept only for "
                    "reference and is not an upload."
                ),
            },
        ],
        "pages": [
            {"id": "page-1", "name": "Screenshots"},
            {"id": "page-2", "name": "Feature graphic"},
        ],
        "launch": {"view": "canvas", "page": "page-1"},
    }
    (HERE / "canvas.json").write_text(json.dumps(canvas, indent=2) + "\n")
    print("wrote canvas.json")


if __name__ == "__main__":
    main()
