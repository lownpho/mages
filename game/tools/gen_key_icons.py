#!/usr/bin/env python3
"""Generate gui/keys.png — the input-prompt atlas — and gui/key_icons.gd, its region map.

Every key, mouse button and pad button the game can ask for, drawn 1:1 on the UI's 8px
grid so a prompt drops into a label row without scaling. The atlas is *generated* rather
than hand-drawn in Aseprite (the rest of the art pipeline): a keycap is a frame plus a
letter, and 60-odd of them by hand would be 60 chances to get the frame wrong. Edit the
tables here, re-run, commit the PNG.

    python3 tools/gen_key_icons.py            # writes gui/keys.png + gui/key_icons.gd
    python3 tools/gen_key_icons.py --preview /tmp/keys_8x.png   # 8x contact sheet

Run from the `game/` directory. Needs Pillow.

Layout: cells are 8px tall and 8, 16 or 24 wide, packed left to right into a 128px sheet;
each group starts on a fresh row so the sheet stays readable. Names and rects are written
out to key_icons.gd, which is what game code uses — nothing should hard-code a rect.

Style: Zughy 32 only. Keycaps are a light face with a dark glyph knocked out and a one
pixel bottom lip, which is the UI's "outlined = interface" dialect. Pad face buttons keep
their console colours (A green, B red, X blue, Y yellow) since that colour *is* the name
on a real pad. Nothing here is anti-aliased or scaled.
"""
import argparse
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, ".."))

SHEET_W = 128
CELL_H = 8

# ---- Zughy 32 subset -------------------------------------------------------------
# Names are Palette's (globals/palette.gd), so an icon's colour and the code that tints
# anything beside it can name the same entry.
DARK = (0x30, 0x2C, 0x2E, 255)  # BLACK — glyph knockout, and the panel behind these icons
LIP = (0x7D, 0x70, 0x71, 255)  # GREY — keycap lip, unlit dpad arms
FACE = (0xCF, 0xC6, 0xB8, 255)  # SILVER — keycap face
BRIGHT = (0xDF, 0xF6, 0xF5, 255)  # WHITE — the lit part, and the HUD glyphs
GREY = (0xA0, 0x93, 0x8E, 255)  # GREY_LIGHT — mouse body, stick base
GREEN = (0x71, 0xAA, 0x34, 255)  # GREEN — pad A
RED = (0xA9, 0x3B, 0x3B, 255)  # RED_DARK — pad B
BLUE = (0x39, 0x78, 0xA8, 255)  # BLUE — pad X
YELLOW = (0xF4, 0xB4, 0x1B, 255)  # YELLOW — pad Y

# ---- 3x5 glyphs, in m3x6's spirit (M/N/W are wider, as they are in the font) ------
GLYPHS = {
    "A": [".##", "#.#", "###", "#.#", "#.#"],
    "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"],
    "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"],
    "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    "J": ["..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": [".#.", "#.#", "#.#", "#.#", ".#."],
    "P": ["##.", "#.#", "##.", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "##.", ".##"],
    "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"],
    "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
    "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "Z": ["###", "..#", ".#.", "#..", "###"],
    "0": [".##", "#.#", "#.#", "#.#", "##."],
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"],
    "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"],
    "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"],
    "9": ["###", "#.#", "###", "..#", "##."],
    "+": ["...", ".#.", "###", ".#.", "..."],
    "-": ["...", "...", "###", "...", "..."],
    "=": ["...", "###", "...", "###", "..."],
    "[": ["##", "#.", "#.", "#.", "##"],
    "]": ["##", ".#", ".#", ".#", "##"],
    "`": ["#.", ".#", "..", "..", ".."],
    # Solid triangles read as arrows far better than a stem-and-head at this size.
    "\x18": [".....", "..#..", ".###.", "#####", "....."],  # up
    "\x19": [".....", "#####", ".###.", "..#..", "....."],  # down
    "\x1b": ["..#", ".##", "###", ".##", "..#"],  # left
    "\x1a": ["#..", "##.", "###", "##.", "#.."],  # right
}
ARROW_UP, ARROW_DOWN, ARROW_LEFT, ARROW_RIGHT = "\x18", "\x19", "\x1b", "\x1a"


def glyph_w(text):
    """Width of `text` set with 1px letter spacing."""
    if not text:
        return 0
    return sum(len(GLYPHS[c][0]) for c in text) + (len(text) - 1)


class Canvas:
    """A tiny mutable RGBA grid; every drawing helper writes through put()."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def put(self, x, y, color):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def rect(self, x, y, w, h, color):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.put(i, j, color)

    def blit_glyph(self, text, x, y, color):
        for c in text:
            rows = GLYPHS[c]
            for j, row in enumerate(rows):
                for i, ch in enumerate(row):
                    if ch == "#":
                        self.put(x + i, y + j, color)
            x += len(rows[0]) + 1

    def to_image(self):
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None:
                    im.putpixel((x, y), self.px[y][x])
        return im


# ---- Icon painters ---------------------------------------------------------------
# Each returns a Canvas of the cell's size. Cells are CELL_H tall; the art inside
# leaves the last column clear so two prompts placed side by side don't touch.


def keycap(label, width):
    """A key: light face, cut corners, dark glyph, one pixel lip along the bottom."""
    c = Canvas(width, CELL_H)
    w = width - 1  # keep a spacer column on the right
    c.rect(0, 0, w, 7, FACE)
    c.rect(1, 7, w - 2, 1, LIP)  # lip, inset so the cap reads rounded
    for x, y in ((0, 0), (w - 1, 0), (0, 6), (w - 1, 6)):
        c.put(x, y, None)
    c.put(0, 6, LIP)
    c.put(w - 1, 6, LIP)
    gw = glyph_w(label)
    c.blit_glyph(label, (w - gw + 1) // 2, 1, DARK)
    return c


DISC8 = [
    "..####..",
    ".######.",
    "########",
    "########",
    "########",
    "########",
    ".######.",
    "..####..",
]


def pad_face(letter, color):
    """A round pad button: solid disc filling the cell, letter knocked out. The disc uses
    all 8px — a 7px one leaves the letter only a pixel of colour around it and turns into a
    smudge at 1:1."""
    c = Canvas(8, CELL_H)
    for y, row in enumerate(DISC8):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x, y, color)
    c.blit_glyph(letter, 3, 2, DARK)
    return c


def pad_pill(label, width):
    """A shoulder / start button: a rounded slab, dark label, no lip."""
    c = Canvas(width, CELL_H)
    w = width - 1
    c.rect(0, 1, w, 6, FACE)
    c.rect(1, 0, w - 2, 1, FACE)
    for x, y in ((0, 1), (w - 1, 1), (0, 6), (w - 1, 6)):
        c.put(x, y, None)
    c.rect(1, 7, w - 2, 1, LIP)
    gw = glyph_w(label)
    c.blit_glyph(label, (w - gw + 1) // 2, 1, DARK)
    return c


DPAD = [
    "..###..",
    "..###..",
    "#######",
    "#######",
    "#######",
    "..###..",
    "..###..",
]
DPAD_ARMS = {
    "up": [(2, 0), (3, 0), (4, 0), (2, 1), (3, 1), (4, 1)],
    "down": [(2, 5), (3, 5), (4, 5), (2, 6), (3, 6), (4, 6)],
    "left": [(0, 2), (1, 2), (0, 3), (1, 3), (0, 4), (1, 4)],
    "right": [(5, 2), (6, 2), (5, 3), (6, 3), (5, 4), (6, 4)],
}


def dpad(active=()):
    """The cross. Arms named in `active` light up; the rest sit back in LIP."""
    c = Canvas(8, CELL_H)
    base = LIP if active else GREY
    for y, row in enumerate(DPAD):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x, y, base)
    for arm in active:
        for x, y in DPAD_ARMS[arm]:
            c.put(x, y, BRIGHT)
    return c


# A mouse reads at this size as a narrow rounded body with a dark channel splitting its two
# buttons — the channel is the whole silhouette's information, and it doubles as the wheel.
# A wider, squarer body turns into a face with two eyes.
MOUSE = [
    "..###..",
    ".##.##.",
    ".##.##.",
    ".#####.",
    ".#####.",
    ".#####.",
    ".#####.",
    "..###..",
]
MOUSE_PARTS = {
    "left": [(1, 1), (2, 1), (1, 2), (2, 2)],
    "right": [(4, 1), (5, 1), (4, 2), (5, 2)],
    "wheel": [(3, 0), (3, 1), (3, 2)],
}


def mouse(part=None):
    """The mouse body in grey, with one button (or the wheel) lit."""
    c = Canvas(8, CELL_H)
    for y, row in enumerate(MOUSE):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x, y, GREY)
    for x, y in MOUSE_PARTS.get(part, ()):
        c.put(x, y, BRIGHT)
    return c


def mouse_wide(part, symbol):
    """Mouse plus a symbol alongside — scroll direction, or the drag arrows. The symbol
    can't ride inside an 8px body, so these prompts are two cells wide."""
    c = Canvas(16, CELL_H)
    body = mouse(part)
    for y in range(CELL_H):
        for x in range(8):
            if body.px[y][x] is not None:
                c.put(x, y, body.px[y][x])
    for y, row in enumerate(symbol):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(9 + x, y + (CELL_H - len(symbol)) // 2, BRIGHT)
    return c


WHEEL_UP = ["..#..", ".###.", "#####"]
WHEEL_DOWN = ["#####", ".###.", "..#.."]
WHEEL_BOTH = ["..#..", ".###.", ".....", ".###.", "..#.."]
DRAG_LR = [".#.#.", "#####", ".#.#."]


def stick(letter, clicked=False):
    """A stick seen from above: dished top with a bright rim, its side lettered."""
    c = Canvas(12, CELL_H)
    disc = [
        "..###..",
        ".#####.",
        "#######",
        "#######",
        "#######",
        ".#####.",
        "..###..",
    ]
    for y, row in enumerate(disc):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x, y, GREY)
    c.rect(2, 2, 3, 3, BRIGHT if clicked else LIP)
    if clicked:
        c.put(3, 3, DARK)
    c.blit_glyph(letter, 8, 1, FACE)
    return c


# The HUD strip's own button, in ui.png's dialect: a flat white glyph, no keycap frame.
KEYBOARD = [
    "#######",
    "#.#.#.#",
    "#######",
    "#.###.#",
    "#######",
]


def hud_keyboard():
    """The strip button that opens this page: a keyboard, seen head on."""
    c = Canvas(8, CELL_H)
    for y, row in enumerate(KEYBOARD):
        for x, ch in enumerate(row):
            if ch == "#":
                c.put(x, y + 2, BRIGHT)
    return c


def chord_plus():
    """The '+' that joins two prompts into a chord ('Y + dpad')."""
    c = Canvas(8, CELL_H)
    c.blit_glyph("+", 1, 1, FACE)
    return c


def slash():
    """The '/' that offers an alternative ('= / +')."""
    c = Canvas(8, CELL_H)
    for i in range(5):
        c.put(1 + (4 - i) // 2, 1 + i, FACE)
    return c


# ---- The atlas -------------------------------------------------------------------
# (name, canvas) in sheet order. A `None` entry breaks to the next row, which is what
# keeps the sheet legible when someone opens it in an image editor.
def build_icons():
    icons = []

    def add(name, canvas):
        icons.append((name, canvas))

    def row_break():
        icons.append((None, None))

    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        add("key_" + ch.lower(), keycap(ch, 8))
    row_break()
    for ch in "0123456789":
        add("key_" + ch, keycap(ch, 8))
    for name, ch in (("plus", "+"), ("minus", "-"), ("equals", "="),
                     ("lbracket", "["), ("rbracket", "]"), ("backquote", "`")):
        add("key_" + name, keycap(ch, 8))
    row_break()
    add("key_up", keycap(ARROW_UP, 8))
    add("key_down", keycap(ARROW_DOWN, 8))
    add("key_left", keycap(ARROW_LEFT, 8))
    add("key_right", keycap(ARROW_RIGHT, 8))
    add("key_esc", keycap("ESC", 16))
    add("key_tab", keycap("TAB", 16))
    add("key_alt", keycap("ALT", 16))
    add("key_del", keycap("DEL", 16))
    row_break()
    add("key_space", keycap("SPACE", 24))
    add("key_enter", keycap("ENTER", 24))
    add("key_shift", keycap("SHIFT", 24))
    add("key_ctrl", keycap("CTRL", 24))
    add("key_bksp", keycap("BKSP", 24))
    row_break()
    for n in range(1, 13):
        add("key_f%d" % n, keycap("F%d" % n, 16))
    row_break()
    add("mouse", mouse())
    add("mouse_left", mouse("left"))
    add("mouse_middle", mouse("wheel"))
    add("mouse_right", mouse("right"))
    add("mouse_wheel", mouse_wide("wheel", WHEEL_BOTH))
    add("mouse_wheel_up", mouse_wide("wheel", WHEEL_UP))
    add("mouse_wheel_down", mouse_wide("wheel", WHEEL_DOWN))
    add("mouse_drag", mouse_wide("left", DRAG_LR))
    row_break()
    add("pad_a", pad_face("A", GREEN))
    add("pad_b", pad_face("B", RED))
    add("pad_x", pad_face("X", BLUE))
    add("pad_y", pad_face("Y", YELLOW))
    add("pad_l1", pad_pill("L1", 16))
    add("pad_r1", pad_pill("R1", 16))
    add("pad_l2", pad_pill("L2", 16))
    add("pad_r2", pad_pill("R2", 16))
    add("pad_start", pad_pill("START", 24))
    add("pad_back", pad_pill("BACK", 24))
    row_break()
    add("pad_dpad", dpad())
    add("pad_dpad_up", dpad(("up",)))
    add("pad_dpad_down", dpad(("down",)))
    add("pad_dpad_left", dpad(("left",)))
    add("pad_dpad_right", dpad(("right",)))
    add("pad_dpad_lr", dpad(("left", "right")))
    add("pad_dpad_ud", dpad(("up", "down")))
    row_break()
    add("pad_stick_l", stick("L"))
    add("pad_stick_r", stick("R"))
    add("pad_stick_l3", stick("L", clicked=True))
    add("pad_stick_r3", stick("R", clicked=True))
    row_break()
    add("chord", chord_plus())
    add("alt_slash", slash())
    add("hud_controls", hud_keyboard())
    return icons


def pack(icons):
    """Place icons left to right, wrapping at SHEET_W; `None` forces a new row."""
    placed = []
    x = y = 0
    for name, canvas in icons:
        if name is None:
            if x:
                x, y = 0, y + CELL_H
            continue
        if x + canvas.w > SHEET_W:
            x, y = 0, y + CELL_H
        placed.append((name, canvas, x, y))
        x += canvas.w
    height = y + CELL_H if x else y
    return placed, height


GD_HEADER = '''## Regions of gui/keys.png, one per input prompt — GENERATED by tools/gen_key_icons.py.
## Do not hand-edit: change the tables in that script and re-run it.
##
## Names read as <device>_<key>: `key_*` for the keyboard, `mouse_*`, `pad_*` for a
## controller. Ask for one with texture(), which caches the AtlasTexture, and let the
## Control size itself to the region — these are 1:1 art and must never be scaled.
class_name KeyIcons

const SHEET := preload("res://gui/keys.png")

const REGIONS := {
'''

GD_FOOTER = '''}

static var _cache: Dictionary = {}

## The AtlasTexture for `name`, or null if nothing is named that (a typo'd prompt should
## leave a hole, not crash the HUD).
static func texture(name: StringName) -> AtlasTexture:
	if _cache.has(name):
		return _cache[name]
	if not REGIONS.has(name):
		push_warning("KeyIcons: no icon named '%s'" % name)
		return null
	var tex := AtlasTexture.new()
	tex.atlas = SHEET
	tex.region = REGIONS[name]
	_cache[name] = tex
	return tex
'''


def write_gd(placed, path):
    lines = [GD_HEADER]
    for name, canvas, x, y in placed:
        lines.append('\t&"%s": Rect2(%d, %d, %d, %d),\n' % (name, x, y, canvas.w, CELL_H))
    lines.append(GD_FOOTER)
    with open(path, "w") as f:
        f.write("".join(lines))


IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path="res://.godot/imported/keys.png-{hash}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://gui/keys.png"
dest_files=["res://.godot/imported/keys.png-{hash}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def write_import(png_path):
    """Seed the .import so a fresh clone resolves res://gui/keys.png before anyone opens
    the editor. Godot rewrites the cache path itself on first import and keeps the uid, so
    this only ever runs once — an existing file is left alone."""
    import hashlib

    imp = png_path + ".import"
    if os.path.exists(imp):
        return  # never clobber the editor's own uid
    digest = hashlib.md5(b"res://gui/keys.png").hexdigest()
    # Godot's uid alphabet; any stable string works as long as it is unique in the project.
    uid = "b" + hashlib.md5(b"gui/keys.png/uid").hexdigest()[:12]
    with open(imp, "w") as f:
        f.write(IMPORT_TEMPLATE.format(uid=uid, hash=digest))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", metavar="PNG",
                    help="also write an 8x nearest-neighbour contact sheet here")
    ap.add_argument("--out-dir", default=os.path.join(GAME, "gui"))
    args = ap.parse_args()

    icons = build_icons()
    placed, height = pack(icons)
    sheet = Image.new("RGBA", (SHEET_W, height), (0, 0, 0, 0))
    for _name, canvas, x, y in placed:
        sheet.paste(canvas.to_image(), (x, y))

    png = os.path.join(args.out_dir, "keys.png")
    sheet.save(png)
    write_import(png)
    write_gd(placed, os.path.join(args.out_dir, "key_icons.gd"))
    print("%s  (%dx%d, %d icons)" % (png, SHEET_W, height, len(placed)))

    if args.preview:
        scale = 8
        bg = Image.new("RGBA", (SHEET_W * scale, height * scale), DARK)
        bg.alpha_composite(sheet.resize((SHEET_W * scale, height * scale), Image.NEAREST))
        bg.save(args.preview)
        print("preview -> %s" % args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
