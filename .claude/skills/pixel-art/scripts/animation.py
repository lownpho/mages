"""Animations: stacks of grids + part masks, previews, and raw-PNG export.

Animation file layout under project_dir/animations/<sprite>_<anim>.json:
{
  "sprite": "dog", "anim": "walk", "fps": 6,
  "palette": {...},
  "parts": {"head": [[0,3],...], "legs": [[6,2],...]},
  "static_parts": ["head"],
  "frames": [ [<grid rows>], [<grid rows>], ... ]
}
"""
import json
import os

from PIL import Image
from render import grid_to_image, render_strip
from validate import validate_animation


def save_animation(sprite, anim, frames, palette, project_dir,
                   parts=None, static_parts=None, fps=6):
    adir = os.path.join(project_dir, 'animations')
    os.makedirs(adir, exist_ok=True)
    data = {'sprite': sprite, 'anim': anim, 'fps': fps, 'palette': palette,
            'parts': parts or {}, 'static_parts': static_parts or [],
            'frames': frames}
    path = os.path.join(adir, f'{sprite}_{anim}.json')
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
    return path


def load_animation(sprite, anim, project_dir):
    with open(os.path.join(project_dir, 'animations', f'{sprite}_{anim}.json')) as f:
        d = json.load(f)
    d['parts'] = {k: [tuple(c) for c in v] for k, v in d.get('parts', {}).items()}
    return d


def animation_gif(frames, palette, output_path, pixel_size=16, fps=6,
                  bg_color='#333333'):
    """Looping GIF preview (bg needed: GIF has no real alpha)."""
    from render import _hex_to_rgba
    imgs = []
    for g in frames:
        im = Image.new('RGBA', (len(g[0]), len(g)), _hex_to_rgba(bg_color))
        im.alpha_composite(grid_to_image(g, palette))
        im = im.resize((im.width * pixel_size, im.height * pixel_size), Image.NEAREST)
        imgs.append(im.convert('P', palette=Image.ADAPTIVE))
    imgs[0].save(output_path, save_all=True, append_images=imgs[1:],
                 duration=int(1000 / fps), loop=0, disposal=2)
    return output_path


def onion_skin(frame_a, frame_b, palette, output_path, pixel_size=16):
    """Overlay two frames: A ghosted at 35% alpha under B. Shows exactly what moved."""
    a = grid_to_image(frame_a, palette)
    b = grid_to_image(frame_b, palette)
    ghost = a.copy()
    alpha = ghost.getchannel('A').point(lambda v: int(v * 0.35))
    ghost.putalpha(alpha)
    out = Image.new('RGBA', a.size, (51, 51, 51, 255))
    out.alpha_composite(ghost)
    out.alpha_composite(b)
    out = out.resize((out.width * pixel_size, out.height * pixel_size), Image.NEAREST)
    out.save(output_path)
    return output_path


def preview_animation(frames, palette, out_dir, name, pixel_size=16, fps=6):
    """Generate everything the vision loop needs: strip, GIF, onion skins."""
    os.makedirs(out_dir, exist_ok=True)
    paths = {
        'strip': render_strip(frames, palette,
                              os.path.join(out_dir, f'{name}_strip.png'),
                              pixel_size=pixel_size),
        'gif': animation_gif(frames, palette,
                             os.path.join(out_dir, f'{name}.gif'),
                             pixel_size=pixel_size, fps=fps),
        'onion': [],
    }
    for i in range(1, len(frames)):
        paths['onion'].append(onion_skin(
            frames[i - 1], frames[i], palette,
            os.path.join(out_dir, f'{name}_onion_{i-1}_{i}.png'),
            pixel_size=pixel_size))
    return paths


def export_raw(sprite, anim_data, out_dir, scale=1):
    """Export raw PNGs for a custom engine:
    - one PNG per frame: <sprite>_<anim>_<i>.png (native size x scale, transparent)
    - one horizontal spritesheet: <sprite>_<anim>_sheet.png (no gaps)
    - metadata JSON: frame size, count, fps, frame order
    Returns dict of paths.
    """
    os.makedirs(out_dir, exist_ok=True)
    frames, palette = anim_data['frames'], anim_data['palette']
    name = f"{anim_data['sprite']}_{anim_data['anim']}"
    w, h = len(frames[0][0]), len(frames[0])
    frame_paths = []
    sheet = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, g in enumerate(frames):
        im = grid_to_image(g, palette)
        sheet.alpha_composite(im, (i * w, 0))
        if scale != 1:
            im = im.resize((w * scale, h * scale), Image.NEAREST)
        p = os.path.join(out_dir, f'{name}_{i}.png')
        im.save(p)
        frame_paths.append(p)
    if scale != 1:
        sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    sheet_path = os.path.join(out_dir, f'{name}_sheet.png')
    sheet.save(sheet_path)
    meta = {'frame_width': w * scale, 'frame_height': h * scale,
            'frame_count': len(frames), 'fps': anim_data.get('fps', 6),
            'sheet': os.path.basename(sheet_path),
            'frames': [os.path.basename(p) for p in frame_paths]}
    meta_path = os.path.join(out_dir, f'{name}.json')
    with open(meta_path, 'w') as f:
        json.dump(meta, f, indent=2)
    return {'frames': frame_paths, 'sheet': sheet_path, 'meta': meta_path}


def check_animation(anim_data):
    """Run cross-frame mechanical validation on a saved/loaded animation dict."""
    return validate_animation(anim_data['frames'],
                              parts=anim_data.get('parts'),
                              static_parts=anim_data.get('static_parts'))
