"""Deterministic grid -> PNG renderer. No interpolation, no AA, no decisions."""
from PIL import Image


def _hex_to_rgba(hex_color):
    h = hex_color.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def grid_to_image(grid, palette, bg_color=None):
    """Render a character grid to a 1x PIL Image (RGBA).

    grid: list[str], all rows same length
    palette: dict char -> '#RRGGBB' or None (transparent)
    bg_color: '#RRGGBB' or None for transparent background
    """
    h, w = len(grid), len(grid[0])
    for i, row in enumerate(grid):
        if len(row) != w:
            raise ValueError(f"Row {i} has length {len(row)}, expected {w}")
    bg = _hex_to_rgba(bg_color) if bg_color else (0, 0, 0, 0)
    img = Image.new('RGBA', (w, h), bg)
    px = img.load()
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch not in palette:
                raise KeyError(f"Char '{ch}' at ({y},{x}) not in palette")
            color = palette[ch]
            if color is not None:
                px[x, y] = _hex_to_rgba(color)
    return img


def render_grid(grid, palette, output_path, pixel_size=16, bg_color=None):
    """Render grid to PNG scaled by pixel_size (nearest neighbor). Returns path."""
    img = grid_to_image(grid, palette, bg_color)
    img = img.resize((img.width * pixel_size, img.height * pixel_size), Image.NEAREST)
    img.save(output_path)
    return output_path


def render_strip(grids, palette, output_path, pixel_size=16, gap=2, bg_color='#333333'):
    """Render multiple grids side by side (for frame comparison). Returns path."""
    imgs = [grid_to_image(g, palette) for g in grids]
    w, h = imgs[0].width, imgs[0].height
    strip = Image.new('RGBA', ((w + gap) * len(imgs) - gap, h), _hex_to_rgba(bg_color))
    for i, im in enumerate(imgs):
        strip.alpha_composite(im, (i * (w + gap), 0))
    strip = strip.resize((strip.width * pixel_size, strip.height * pixel_size), Image.NEAREST)
    strip.save(output_path)
    return output_path
