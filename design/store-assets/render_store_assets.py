#!/usr/bin/env python3
"""Render the finished store assets as PNGs at full store resolution.

Captions and image assignments come from build_artboards.py, so the canvas and
these PNGs never drift apart. Type is drawn with the app's own bundled fonts
(assets/fonts), not a web fallback.

Outputs, per Apple's and Google's specs:

  out/appstore/*.png   1290 x 2796   App Store 6.9" (confirmed accepted by ASC)
  out/play/*.png       1080 x 2160   Play phone (Play rejects taller than 2:1)
  out/play/feature_graphic.png
                       1024 x 500    Play feature graphic

  python3 render_store_assets.py
"""
import pathlib
import shutil
import zipfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from build_artboards import (
    ARTBOARDS,
    BEZEL,
    DIM,
    FEATURE_H,
    FEATURE_W,
    FRAME_H,
    FRAME_W,
    GOLD,
    INK,
    PAPER,
    PLAY_H,
    PLAY_W,
)

HERE = pathlib.Path(__file__).parent
FONTS = HERE.parent.parent / "assets" / "fonts"
OUT = HERE / "out"

# The canvas embeds downscaled JPEGs to keep the published page small; these
# renders use the untouched full-resolution captures instead.
FULL_RES = {
    "checkin_split.jpg": "_checkin_split.png",
    "home.jpg": "20_home_behind.png",
    "journey.jpg": "30_journey_streak.png",
    "community.jpg": "40_community.png",
    "plan_detail_split.jpg": "_plan_detail_split.png",
    "reflection.jpg": "60_reflect_sheet.png",
    "payoff.jpg": "70_checkin_payoff_dusk.png",
}

SERIF = FONTS / "Spectral-Medium.ttf"
SERIF_REG = FONTS / "Spectral-Regular.ttf"
SERIF_ITALIC = FONTS / "Spectral-Italic.ttf"
SANS = FONTS / "HankenGrotesk-VariableFont_wght.ttf"


def font(path, size, weight=None):
    f = ImageFont.truetype(str(path), size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass  # static face, or FreeType without variable-font support
    return f


def text_width(draw, s, f, tracking=0):
    w = draw.textlength(s, font=f)
    return w + tracking * max(len(s) - 1, 0)


def draw_tracked(draw, xy, s, f, fill, tracking):
    """PIL has no letter-spacing; the eyebrow needs it, so step per glyph."""
    x, y = xy
    for ch in s:
        draw.text((x, y), ch, font=f, fill=fill)
        x += draw.textlength(ch, font=f) + tracking


def wrap(draw, s, f, max_w):
    words, lines, cur = s.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if draw.textlength(trial, font=f) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255
    )
    return mask


def device(capture_path, width, bezel_pad, outer_radius):
    """A bezelled phone at `width`, transparent outside its rounded corners."""
    shot = Image.open(capture_path).convert("RGB")
    inner_w = width - 2 * bezel_pad
    inner_h = round(shot.size[1] * inner_w / shot.size[0])
    shot = shot.resize((inner_w, inner_h), Image.LANCZOS)

    outer = Image.new("RGBA", (width, inner_h + 2 * bezel_pad), (0, 0, 0, 0))
    body = Image.new("RGBA", outer.size, BEZEL)
    outer.paste(body, (0, 0), rounded_mask(outer.size, outer_radius))

    inner_radius = max(outer_radius - bezel_pad, 4)
    outer.paste(shot, (bezel_pad, bezel_pad), rounded_mask(shot.size, inner_radius))
    return outer


def drop_shadow(canvas, layer, xy, blur, offset_y, opacity):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    solid = Image.new("RGBA", layer.size, (35, 30, 44, opacity))
    shadow.paste(solid, (xy[0], xy[1] + offset_y), layer)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))


def render_frame(out_path, target_w, target_h, art_w, art_h, pad_top, image, headline, sub):
    """Scale the artboard geometry up to the real store pixel size."""
    k = target_w / art_w
    canvas = Image.new("RGBA", (target_w, target_h), PAPER)
    draw = ImageDraw.Draw(canvas)

    eyebrow_f = font(SANS, round(11 * k), weight=700)
    head_f = font(SERIF, round(44 * k))
    sub_f = font(SANS, round(15.5 * k), weight=400)

    y = round(pad_top * k)

    tracking = 1.7 * k
    label = "BIBLE READ"
    draw_tracked(
        draw,
        ((target_w - text_width(draw, label, eyebrow_f, tracking)) / 2, y),
        label,
        eyebrow_f,
        GOLD,
        tracking,
    )
    y += round(11 * k * 1.4) + round(14 * k)

    line_h = round(44 * k * 1.06)
    for line in headline.split("<br>"):
        draw.text(
            ((target_w - draw.textlength(line, font=head_f)) / 2, y),
            line,
            font=head_f,
            fill=INK,
        )
        y += line_h
    y += round(20 * k)  # PIL draws from the ascender, so the CSS gap needs padding

    sub_line_h = round(15.5 * k * 1.45)
    for line in wrap(draw, sub, sub_f, 348 * k):
        draw.text(
            ((target_w - draw.textlength(line, font=sub_f)) / 2, y),
            line,
            font=sub_f,
            fill=DIM,
        )
        y += sub_line_h

    y += round(36 * k)
    phone = device(
        HERE / "captures" / FULL_RES[image],
        round(380 * k),
        round(9 * k),
        round(48 * k),
    )
    x = (target_w - phone.size[0]) // 2
    drop_shadow(canvas, phone, (x, y), blur=round(22 * k), offset_y=round(24 * k), opacity=70)
    canvas.alpha_composite(phone, (x, y))

    canvas.convert("RGB").save(out_path, optimize=True)
    print(f"{out_path.relative_to(HERE)}  {target_w}x{target_h}")


def render_feature_graphic(out_path):
    canvas = Image.new("RGBA", (FEATURE_W, FEATURE_H), PAPER)
    draw = ImageDraw.Draw(canvas)

    eyebrow_f = font(SANS, 12, weight=700)
    head_f = font(SERIF_REG, 54)
    head_italic_f = font(SERIF_ITALIC, 54)
    sub_f = font(SANS, 17, weight=400)

    # Phones first: the text block sits clear of them, and Play may crop the
    # outer edges, so the phones are what can lose a sliver.
    for capture, right, top, angle, opacity in (
        ("_checkin_split.png", 196, 74, -5, 66),
        ("20_home_behind.png", 28, 128, 4, 76),
    ):
        phone = device(HERE / "captures" / capture, 208, 6, 30)
        phone = phone.rotate(angle, expand=True, resample=Image.BICUBIC)
        x = FEATURE_W - right - phone.size[0]
        drop_shadow(canvas, phone, (x, top), blur=18, offset_y=18, opacity=opacity)
        canvas.alpha_composite(phone, (x, top))

    left = 72
    block_h = 12 + 14 + 2 * 56 + 18 + 2 + 18 + 2 * 26
    y = (FEATURE_H - block_h) // 2

    draw_tracked(draw, (left, y), "BIBLE READ", eyebrow_f, GOLD, 2)
    y += 12 + 18

    draw.text((left, y), "Reading counts as", font=head_f, fill=INK)
    y += 56
    draw.text((left, y), "showing up.", font=head_italic_f, fill="#6A53AD")
    y += 56 + 30  # clear the descender before the rule

    draw.rectangle([(left, y), (left + 56, y + 2)], fill=GOLD)
    y += 2 + 18

    sub = "A daily plan, a streak that tells the truth, and a group reading beside you."
    for line in wrap(draw, sub, sub_f, 430):
        draw.text((left, y), line, font=sub_f, fill=DIM)
        y += 26

    canvas.convert("RGB").save(out_path, optimize=True)
    print(f"{out_path.relative_to(HERE)}  {FEATURE_W}x{FEATURE_H}")


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "appstore").mkdir(parents=True)
    (OUT / "play").mkdir(parents=True)

    for i, (name, _title, image, headline, sub) in enumerate(ARTBOARDS, start=1):
        stem = f"{i:02d}_{name.lower()}.png"
        render_frame(
            OUT / "appstore" / stem, 1290, 2796, FRAME_W, FRAME_H, 62, image, headline, sub
        )
        render_frame(
            OUT / "play" / stem, 1080, 2160, PLAY_W, PLAY_H, 48, image, headline, sub
        )

    render_feature_graphic(OUT / "play" / "feature_graphic.png")

    zip_path = HERE / "bible-read-store-assets.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(OUT.rglob("*.png")):
            z.write(f, f.relative_to(OUT))
    size_mb = zip_path.stat().st_size / 1_000_000
    print(f"\n{zip_path.name}  {size_mb:.1f} MB")


if __name__ == "__main__":
    main()
