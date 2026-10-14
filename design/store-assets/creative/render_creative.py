#!/usr/bin/env python3
"""Render the App Store creative assets (product page header, search result)
from the design-canvas artboards in canvas/ to full-resolution PNGs.

Apple's iOS 27 creative slots:

  Header          5244 x 2950 (16:9, also accepted for search results)
                  3840 x 1646 (wide)
  Search result   3840 x 2560 / 1920 x 1280 (3:2)

On iPhone the header is cropped hard: only about the centre 46% of the width
and the top 60% of the height show, and the back/share buttons sit on the top
~23%. Keep anything essential inside that window (the blue guide on the 16:9
artboards in canvas.json marks it).

Each artboard is flattened to a plain HTML page (template holes filled with the
"dawn" values, uploaded-image ids mapped back to captures/) and screenshotted
with headless Chrome at a whole-number-ish zoom, then cropped to the exact size.
Fonts load from Google Fonts, so this needs a network connection.

  python3 creative/render_creative.py      # writes creative/out/ and a zip
"""
import pathlib
import re
import subprocess
import tempfile
import zipfile

from PIL import Image

HERE = pathlib.Path(__file__).parent
CANVAS = HERE / "canvas"
CAPTURES = HERE.parent / "captures"
OUT = HERE / "out"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Ids of the captures as uploaded to the design canvas.
BLOBS = {
    "752c9b4628459a5f447f124e83ea2b8a": "10_checkin_dawn.png",
    "de9ab35036259508e53da509b6054eac": "11_checkin_night.png",
    "3dc5235f0c9851ac9d85bc9624399c46": "12_checkin_day.png",
    "9234dee6b82944e8486517fd133e730e": "13_checkin_dusk.png",
    "026618fd994285d0b62fd2b16b04bf3d": "20_home_behind.png",
    "b0a1d91a32c64557e6bc4c3589845009": "30_journey_streak.png",
    "06da83543a9fb7acac5a63871dab5a36": "40_community.png",
    "5e2d22f3640d29961101bcadaf68f8be": "50_plan_detail_light.png",
    "685dc52c3c4c039180d778a276d8e93b": "52_plan_detail_dark.png",
    "475bc5064ee3ca6292b15393fe7ee6c3": "60_reflect_sheet.png",
}

# artboard, (viewport w, h), zoom, outputs [(name, size)]. The first output is
# a crop of the zoomed render; any later one is a downscale of the first.
JOBS = [
    ("Main", (1311, 738), 4, [("header_5244x2950.png", (5244, 2950))]),
    ("HeaderWide", (1280, 549), 3, [("header_3840x1646.png", (3840, 1646))]),
    (
        "SearchResult",
        (1200, 800),
        3.2,
        [
            ("search-result_3840x2560.png", (3840, 2560)),
            ("search-result_1920x1280.png", (1920, 1280)),
        ],
    ),
    ("HeaderPath", (1311, 738), 4, [("variations/header_A_paper-path_5244x2950.png", (5244, 2950))]),
    ("HeaderNight", (1311, 738), 4, [("variations/header_B_night-sky_5244x2950.png", (5244, 2950))]),
    ("HeaderTogether", (1311, 738), 4, [("variations/header_C_together_5244x2950.png", (5244, 2950))]),
    ("HeaderHills", (1311, 738), 4, [("variations/header_D_dawn-path_5244x2950.png", (5244, 2950))]),
    ("HeaderWall", (1311, 738), 4, [("variations/header_E_reading-wall_5244x2950.png", (5244, 2950))]),
    ("HeaderScreens", (1311, 738), 4, [("variations/header_F_screen-wall_5244x2950.png", (5244, 2950))]),
]


def flatten(src):
    """A .dc.html artboard as a standalone page Chrome can screenshot."""
    t = src.read_text()
    body = t.split("<x-dc>")[1].split("</x-dc>")[0]
    helmet = re.search(r"<helmet>(.*?)</helmet>", body, re.S).group(1)
    body = re.sub(r"<helmet>.*?</helmet>", "", body, flags=re.S)
    # Artboards with a Sky tweak return `dusk ? {...} : {...}`; take dawn.
    dawn = t.split("} : {")[1].split("};")[0] if "} : {" in t else ""
    vals = dict(re.findall(r"(\w+): '([^']*)'", dawn))
    body = re.sub(r"\{\{(\w+)\}\}", lambda m: vals[m.group(1)], body)
    body = re.sub(r"/_blob/(\w+)", lambda m: (CAPTURES / BLOBS[m.group(1)]).as_uri(), body)
    assert "{{" not in body, f"unfilled hole in {src.name}"
    return (
        '<!doctype html><html><head><meta charset="utf-8">'
        f'{helmet.replace("&amp;", "&")}'
        "<style>html,body{overflow:hidden}</style></head>"
        f"<body>{body}</body></html>"
    )


def main():
    (OUT / "variations").mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for board, (vw, vh), zoom, outputs in JOBS:
            page = tmp / f"{board}.html"
            shot = tmp / f"{board}.png"
            page.write_text(flatten(CANVAS / f"{board}.dc.html"))
            subprocess.run(
                [
                    CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--allow-file-access-from-files", "--virtual-time-budget=8000",
                    f"--window-size={vw},{vh}", f"--force-device-scale-factor={zoom}",
                    f"--screenshot={shot}", page.as_uri(),
                ],
                check=True,
                capture_output=True,
            )
            im = Image.open(shot).convert("RGB")
            first, size = outputs[0]
            im = im.crop((0, 0, *size)) if im.width >= size[0] and im.height >= size[1] else im.resize(size, Image.LANCZOS)
            im.save(OUT / first, optimize=True)
            print(f"out/{first}  {size[0]}x{size[1]}")
            for name, size in outputs[1:]:
                im.resize(size, Image.LANCZOS).save(OUT / name, optimize=True)
                print(f"out/{name}  {size[0]}x{size[1]}")

    zip_path = OUT / "bible-read-app-store-creative.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(OUT.rglob("*.png")):
            z.write(f, f.relative_to(OUT))
    print(f"\n{zip_path.relative_to(HERE)}  {zip_path.stat().st_size / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
