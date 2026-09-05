#!/usr/bin/env python3
"""Composite two device captures into one split frame, and shrink captures for
the design canvas.

  composite.py diagonal dawn.png night.png out.png    # top-left / bottom-right
  composite.py vertical light.png dark.png out.png    # left / right
  composite.py shrink in.png out.png --width 760      # canvas-sized copy

The diagonal split says "this screen changes through the day"; the vertical
split says "there are two themes". Different cut, different claim — see
design/store-assets/README.md.
"""
import argparse
import sys

from PIL import Image, ImageDraw

# Hairline drawn along the seam so the two captures read as one deliberate
# image rather than a mis-registered paste. Warm paper white at low alpha.
SEAM_RGBA = (255, 253, 250, 210)
SEAM_WIDTH = 3


def _load_pair(a_path, b_path):
    a = Image.open(a_path).convert("RGBA")
    b = Image.open(b_path).convert("RGBA")
    if a.size != b.size:
        sys.exit(f"size mismatch: {a.size} vs {b.size} — captures must match")
    return a, b


def diagonal(a_path, b_path, out_path):
    """`a` fills the top-left, `b` the bottom-right, cut corner to corner."""
    a, b = _load_pair(a_path, b_path)
    w, h = a.size

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon([(w, 0), (w, h), (0, h)], fill=255)

    out = Image.composite(b, a, mask)
    draw = ImageDraw.Draw(out)
    draw.line([(w, 0), (0, h)], fill=SEAM_RGBA, width=SEAM_WIDTH)
    out.convert("RGB").save(out_path)
    print(f"{out_path}: diagonal {a_path} / {b_path} at {w}x{h}")


def vertical(a_path, b_path, out_path):
    """`a` fills the left half, `b` the right half."""
    a, b = _load_pair(a_path, b_path)
    w, h = a.size
    mid = w // 2

    out = a.copy()
    out.paste(b.crop((mid, 0, w, h)), (mid, 0))
    draw = ImageDraw.Draw(out)
    draw.line([(mid, 0), (mid, h)], fill=SEAM_RGBA, width=SEAM_WIDTH)
    out.convert("RGB").save(out_path)
    print(f"{out_path}: vertical {a_path} / {b_path} at {w}x{h}")


def shrink(in_path, out_path, width):
    """Downscale for embedding in the canvas, where every byte republishes."""
    img = Image.open(in_path).convert("RGB")
    w, h = img.size
    height = round(h * width / w)
    img.resize((width, height), Image.LANCZOS).save(
        out_path, optimize=True, quality=82
    )
    print(f"{out_path}: {w}x{h} -> {width}x{height}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    for name in ("diagonal", "vertical"):
        s = sub.add_parser(name)
        s.add_argument("a")
        s.add_argument("b")
        s.add_argument("out")

    s = sub.add_parser("shrink")
    s.add_argument("input")
    s.add_argument("out")
    s.add_argument("--width", type=int, default=760)

    args = p.parse_args()
    if args.cmd == "diagonal":
        diagonal(args.a, args.b, args.out)
    elif args.cmd == "vertical":
        vertical(args.a, args.b, args.out)
    else:
        shrink(args.input, args.out, args.width)


if __name__ == "__main__":
    main()
