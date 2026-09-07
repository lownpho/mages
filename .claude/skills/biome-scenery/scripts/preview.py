#!/usr/bin/env python3
"""Biome-scenery verification helpers (rule 9).

Two jobs the generic pixel-art renderer doesn't cover:
  --colors SHEET                list the opaque colors in a sheet (sample the biome)
  --sheet SHEET --fw W --fh H --floor RRGGBB --out PREFIX
                                composite the frames on the floor tone and tile a bunch

Examples:
  python3 preview.py --colors /tmp/floor.png
  python3 preview.py --sheet /tmp/sheet.png --fw 8 --fh 16 --floor 3c5956 --out /tmp/prev
"""
import argparse, collections, random
from PIL import Image


def hex_to_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def list_colors(path):
    im = Image.open(path).convert('RGBA')
    counts = collections.Counter(im.getdata())
    print(f"{path}  {im.size}")
    for c, n in counts.most_common():
        if c[3] == 0:
            continue
        print(f"  #{c[0]:02x}{c[1]:02x}{c[2]:02x}  {n}")


def previews(sheet_path, fw, fh, floor_hex, out_prefix, cols=8, rows=3, seed=3, scale=12):
    sheet = Image.open(sheet_path).convert('RGBA')
    n = sheet.width // fw
    frames = [sheet.crop((i * fw, 0, i * fw + fw, fh)) for i in range(n)]
    floor = hex_to_rgba(floor_hex)

    onfloor = Image.new('RGBA', (sheet.width, fh), floor)
    onfloor.alpha_composite(sheet)
    onfloor.resize((onfloor.width * scale, onfloor.height * scale), Image.NEAREST) \
        .save(f"{out_prefix}_onfloor.png")

    random.seed(seed)
    bunch = Image.new('RGBA', (fw * cols, fh * rows), floor)
    for ry in range(rows):
        for cx in range(cols):
            bunch.alpha_composite(random.choice(frames), (cx * fw, ry * fh))
    bunch.resize((bunch.width * (scale // 2 or 1), bunch.height * (scale // 2 or 1)),
                 Image.NEAREST).save(f"{out_prefix}_bunch.png")
    print(f"wrote {out_prefix}_onfloor.png and {out_prefix}_bunch.png ({n} variants)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--colors', metavar='SHEET')
    ap.add_argument('--sheet')
    ap.add_argument('--fw', type=int, default=8)
    ap.add_argument('--fh', type=int, default=16)
    ap.add_argument('--floor', default='3c5956')
    ap.add_argument('--out', default='/tmp/biome_prev')
    ap.add_argument('--cols', type=int, default=8)
    ap.add_argument('--rows', type=int, default=3)
    a = ap.parse_args()
    if a.colors:
        list_colors(a.colors)
    elif a.sheet:
        previews(a.sheet, a.fw, a.fh, a.floor, a.out, a.cols, a.rows)
    else:
        ap.error("pass --colors SHEET or --sheet SHEET")


if __name__ == '__main__':
    main()
