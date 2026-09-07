#!/usr/bin/env python3
"""inspect_sheet.py — dump a PNG (or a region of one) as a copy-pasteable
character grid, for studying an existing sprite before drawing a sibling.

Replaces the one-off "crop a frame, loop pixels, print hex" snippet that
otherwise gets rewritten by hand every time a new sprite needs to match an
existing project's conventions (proportions, face template, leg/eye
placement, ...).

Usage:
  python inspect_sheet.py sheet.png                      # whole image, hex grid
  python inspect_sheet.py sheet.png --region 0,0,8,8      # one frame, hex grid
  python inspect_sheet.py sheet.png --region 0,16,8,8 --keys
      # assigns a short letter per unique color and prints a ready-to-paste
      # `palette = {...}` dict plus a `grid = [...]` literal
"""
import argparse

from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("--region", help="x,y,w,h — defaults to the whole image")
    ap.add_argument(
        "--keys",
        action="store_true",
        help="assign a letter per unique color and print a palette dict + grid literal, instead of raw hex",
    )
    args = ap.parse_args()

    im = Image.open(args.png).convert("RGBA")
    if args.region:
        x, y, w, h = (int(v) for v in args.region.split(","))
        im = im.crop((x, y, x + w, y + h))
    px = im.load()
    w, h = im.size

    if not args.keys:
        for y in range(h):
            row = []
            for x in range(w):
                r, g, b, a = px[x, y]
                row.append("." if a == 0 else "#%02x%02x%02x" % (r, g, b))
            print(" ".join(f"{c:>9}" for c in row))
        return

    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    color_to_key: dict[str, str] = {}
    grid_rows = []
    for y in range(h):
        row_chars = []
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                row_chars.append("_")
                continue
            hexc = "#%02x%02x%02x" % (r, g, b)
            if hexc not in color_to_key:
                if len(color_to_key) >= len(letters):
                    raise SystemExit("more than 52 unique colors in region — too busy to key")
                color_to_key[hexc] = letters[len(color_to_key)]
            row_chars.append(color_to_key[hexc])
        grid_rows.append("".join(row_chars))

    print("palette = {")
    print("    '_': None,")
    for hexc, key in color_to_key.items():
        print(f"    '{key}': '{hexc}',")
    print("}")
    print()
    print("grid = [")
    for row in grid_rows:
        print(f" '{row}',")
    print("]")


if __name__ == "__main__":
    main()
