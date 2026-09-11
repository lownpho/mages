---
name: game-ui
description: Build or restyle a HUD panel, overlay, page, table, tooltip or any other Control UI in the game's 320x180 pixel style. Use when the user wants a new panel/screen/menu/overlay/recap page, a strip button, a paged book, a column layout, or wants an existing one to match the rest of the HUD. Covers the shared panel skeleton, the theme and palette rules, the ui.png chrome atlas and the keys.png input prompts, columns and paging, keyboard/pad focus, and the "data lives in the scene, not the script" rule with its headless test.
---

# Building UI in this game's style

The HUD is **scenes, not code**. Every shipped panel is a `.tscn` that an editor can lay out;
the script beside it is small and does one thing (bind data, turn pages, toggle visibility).
When you are asked for a new panel, the deliverable is a scene tree — reach for a script only
for behaviour that has no scene expression.

Read `gui/ui.gd`, `gui/theme.tres` and `gui/controls/controls.tscn` before starting. They are
the architecture source of truth; the rest of this file is what they have in common.

## The canvas

320x180, integer-scaled (`project.godot [display]`). Consequences that bite:

- **Every size is a whole pixel.** No fractional offsets, no `scale`, no anchoring that lands
  a Control on a half pixel. Art is authored 1:1 and must never be stretched — size the
  Control to the art, not the art to the Control.
- **8px is the grid unit.** Icons, slots and prompts are 8x8 (some prompts 16 or 24 wide).
  Margins are 3, gaps are 1-4, a generous gap is 12.
- **A panel has ~250x140 of usable room.** A long English sentence at font size 8 is about
  80px. Budget accordingly, and let the headless test catch what doesn't fit.

## The theme gives you the look — don't restate it

`gui/theme.tres` is the project-wide theme (`project.godot: gui/theme/custom`). It already
sets the font (`m3x6.ttf` at size 8), the white label colour, the 9-sliced `PanelContainer`
background, and flat borderless `Button`s. **A new scene overrides nothing by default.** If a
node in your scene carries `theme_override_colors/font_color` or a `font_size`, you are
deviating on purpose and should be able to say why.

Type variations that already exist — set `theme_type_variation` rather than restyling:

| variation | base | what it is |
|---|---|---|
| `IconButton` | Button | strip button; adds the 1px focus ring |
| `BarPanel` | PanelContainer | panel with 2px right padding, for a bar + value |
| `HealthBar` | ProgressBar | red fill |
| `StatValue` | Label | 1px right padding for a right-aligned number |
| `TooltipPanel` | PanelContainer | the hand-built tooltip's frame |

## Colour: the palette, always

Every colour in the game is a Zughy 32 entry in `globals/palette.gd` (`Palette.WHITE`,
`Palette.GREY_LIGHT`, …). Scripts reference the constant. A `.tscn` has to write a literal
`Color(...)`, so **write the palette entry's value and nothing else** — pick the constant
first, then convert. Derived shades are `.darkened()` / `.lightened()` steps of a constant,
never a new hue.

Values you will reach for in scenes:

```
Palette.WHITE       Color(0.8745098, 0.9647059, 0.9607843, 1)   default label
Palette.GREY_LIGHT  Color(0.627451, 0.576471, 0.556863, 1)      dim heading / kicker
Palette.GREY        Color(0.490196, 0.439216, 0.443137, 1)      rules, off dots
Palette.BLACK       Color(0.188235, 0.172549, 0.180392, 1)      curtains
```

## The two atlases

**`gui/ui.png` (64x32) — chrome.** Cut with an `AtlasTexture` sub-resource per region:

| region | what |
|---|---|
| `Rect2(0, 0, 8, 8)` | panel frame (9-slice, 1px margins) — the theme's, you rarely re-cut it |
| `Rect2(8, 0, 8, 8)` | slot frame |
| `Rect2(x, 8, 8, 8)` | stat glyphs: damage 0, cooldown 8, cast 16, health 24, defence 40, skill 48, speed 56 |
| `Rect2(0, 16, 8, 8)` | skull (bestiary) |
| `Rect2(8, 16, 8, 8)` | quit |
| `Rect2(16, 16, 8, 8)` | map |
| `Rect2(24, 16, 8, 8)` | close X |
| `Rect2(40, 16, 8, 8)` | tome (grimoire) |
| `Rect2(0, 24, 8, 8)` / `Rect2(8, 24, 8, 8)` | page arrows, left / right |

**`gui/keys.png` — input prompts.** Never cut this one by hand. `gui/key_icons.gd` is a
generated name → region table (`tools/gen_key_icons.py` owns it; edit the script's tables and
re-run, never the .gd), and `gui/controls/key_prompt.gd` is the node you place:

```
[node name="key_w" type="TextureRect" parent="..."]
script = ExtResource("4_prompt")
icon = &"key_w"
```

`KeyPrompt` is `@tool`, so a page of prompts renders in the editor, and its `icon` export is a
dropdown of every atlas name. Ask for a prompt by name from a script with
`KeyIcons.texture(&"hud_controls")`.

## The overlay panel skeleton

`bestiary.tscn`, `grimoire.tscn`, `map_panel.tscn` and `controls.tscn` are the same shape. Copy it:

```
Panel (PanelContainer)                    ← theme paints the frame; no style overrides
└ Margin (MarginContainer, margins 3)
  └ Content (Control)                     ← the anchor frame everything else hangs off
    ├ Title (Label, %Title, anchors_preset 10, offset_top 1, horizontal_alignment 1)
    │                                     ← the window's name in capitals: "BESTIARY", "MAP"
    ├ Header (HBox, offset_top 1, sep 4)  ← the page heading on the left: "play", "The Glade 3/9"
    ├ CloseButton (TextureButton)         ← anchors_preset 1, offset_left -8, offset_bottom 8,
    │                                       grow_horizontal 0, focus_mode 0, close X region
    ├ Body (…, anchors_preset 15, offset_top 9-10, offset_bottom -9/-10, grow 2/2)
    └ Nav (HBox, anchors_preset 7, offset_top -9, offset_bottom -1, alignment 1, sep 4)
      └ PrevPage · PageDots · NextPage
```

`Body` is a `CenterContainer` when the content is a block that should sit in the middle
(bestiary grid), or a `VBoxContainer` with `alignment = 1` when the content must span the full
width but still centre vertically (controls tables). Everything the script touches gets
`unique_name_in_owner` and is addressed as `%Name`.

Mount it in `gui/ui.tscn` as an instance under `UI`, `visible = false`, `anchors_preset 15`,
`offset_left 52` (clear of the strip), `offset_top/bottom 5`, `offset_right -10`.

## Wiring an overlay into the HUD

Two edits in `gui/ui.gd`, both one line:

1. A strip button in `ui.tscn` under `Strip/VBox/BestiaryChip/Buttons`, `theme_type_variation
   = &"IconButton"`, with its 8x8 icon. `Buttons` is a 4-column grid — the strip is exactly four
   buttons wide — so a fifth wraps onto the next row, which is also the next rung of the focus
   ladder (see below: add it to `nav` and to `tests/test_ui_focus.gd`).
2. A `%Panel: %Button` entry in `_panel_buttons`.

That dictionary is the answer to every "which panels are there" question — opening one closes
the others, Esc / pad B / an outside click closes whichever is open, focus is released while a
panel is up and returned to the opening button on close, and that button wears a painted-on
focus ring while the panel is open. You get all of it for free; do not re-implement any of it
in the panel.

## Paging

`gui/bestiary/page_dots.gd` (`PageDots`) draws the "page 2 of 4" dots — set `.pages` and
`.current`. The pattern, from `controls.gd`:

- one node per page under the body container, `_set_page` shows exactly one;
- `_page = clampi(page, 0, count - 1)` — paging **clamps, never wraps**;
- arrows **dim** at the ends (`disabled = true`, `self_modulate.a = 0.4`) rather than hiding,
  so the nav row never shifts;
- pad paging reads `ui_left` / `ui_right` in `_unhandled_input`, gated on
  `visible and GlobalInput.ui_captured` so a keyboard's arrow keys stay with whatever else
  has them, then `get_viewport().set_input_as_handled()`.

## Tables and columns

Columns are a `GridContainer`, not per-row `HBox`es. `controls.tscn` is the reference:

- `columns = 3`, `h_separation = 0`, `v_separation` for the line spacing (7 reads well);
- every cell gets `size_flags_horizontal = 3` (EXPAND_FILL) at the default ratio, so the
  columns are equal fractions of whatever width the table is given;
- a cell that holds icons is an `HBoxContainer` with `alignment = 1` and `separation = 1`; a
  cell that holds text is a `Label` with `horizontal_alignment = 1` and
  `size_flags_vertical = 4`;
- column titles are their own grid with the same `columns`, so they sit over the same
  fractions — pad the short row with an empty `Control` rather than leaving cells off;
- a `GridContainer` cannot span a heading across its columns. If a table needs sections, give
  each section **its own page** rather than interleaving heading rows.

Name cells after their row (`MoveKeys`, `MovePad`, `MoveText`) — the grid flattens the rows
away, and the names are what puts them back for whoever opens the scene.

## Data lives in the scene, not the script

The rule this codebase converged on: **if a designer would want to change it, it is a node or
an exported property, not a table in GDScript.** Applied:

- a page's *title* is its node name (`%PageTitle.text = String(_pages[_page].name)`);
- a binding's *prompt* is a `KeyPrompt.icon`, not a string in an array;
- a column's *width rule* is a size flag, not a constant.

When a leaf needs to be editable by name, write a tiny `@tool` node like `KeyPrompt`:

```gdscript
@export var icon: StringName = &"":
    set(value):
        icon = value
        texture = KeyIcons.texture(icon) if icon != &"" else null

func _validate_property(property: Dictionary) -> void:
    if property.name == "icon":
        property.hint = PROPERTY_HINT_ENUM          # a dropdown, not a memory test
        property.hint_string = ",".join(names)
    elif property.name == "texture":
        property.usage &= ~PROPERTY_USAGE_STORAGE   # derived: keep it out of the .tscn
```

Stripping `PROPERTY_USAGE_STORAGE` from the derived property is what keeps the scene storing
the *name* only — otherwise every node bakes an `AtlasTexture` sub-resource into the file.

## Focus and the pad

- Pad focus down the strip is ONE explicit 4-wide ladder wired in `ui.gd::_wire_focus_ladder`
  (spell slots, bag slots, buttons). If you add a focusable strip control, add it to `nav`
  there and to `tests/test_ui_focus.gd`.
- Chrome that is clicked but never navigated to — close buttons, page arrows — takes
  `focus_mode = 0`, or it becomes a stop on the ladder.
- `GlobalInput.ui_captured` means "the HUD owns input"; `GlobalInput.using_gamepad` means
  "the last input was a pad". Gate pad-only handling on the first, cosmetics on the second.
- Movement is never gated: the mage keeps walking while a panel is up. Don't pause.

## The headless test

Every panel gets one, in `tests/`, run as
`godot --headless --path game res://tests/test_<thing>.tscn`, printing `ALL PASS` or
`FAILED: n` and `get_tree().quit(0 or 1)`. Copy `tests/test_controls_page.gd`. It exists to
catch the failures that are **silent** at 320x180:

```gdscript
get_window().size = Vector2i(320, 180)   # headless picks its own size otherwise
var ui := UI_SCENE.instantiate()
add_child(ui)
panel.visible = true
await get_tree().process_frame            # twice: layout settles a frame late
await get_tree().process_frame
```

Then assert what a person would only notice by squinting: every icon resolved (a bad name
leaves a *hole*, not an error), every row fits `area.size.x`, the stacked rows fit
`area.size.y`, the columns are equal within the odd rounding pixel, paging clamps and the
arrows agree, and opening the panel closes the other overlays. **Verify each assertion fires**
by breaking the scene once and watching it fail — a check that walks zero nodes passes
vacuously.

## Godot gotchas

- A new `.gd` needs its `.uid`; run `godot --headless --path game --import` once, then paste
  the uid into any `[ext_resource]` that points at it.
- `class_name` types are only findable by `find_children("*", "Type", …)` after that import.
- Node names are load-bearing here (titles, cell identity). They must stay unique among
  siblings; lowercase is fine.
- A `.tscn` edited on disk while the Godot editor has it open will be clobbered by the
  editor's in-memory copy — tell the user to reload the scene.
- Don't hand-write `unique_id=` on nodes; Godot assigns them on save.
- Rendering a screenshot to check the work needs a display: a throwaway scene that does
  `await RenderingServer.frame_post_draw` a few times then
  `get_viewport().get_texture().get_image().save_png("user://x.png")`, run **without**
  `--headless`. Delete the scene afterwards.

## Checklist

- [ ] Scene tree, not a builder function; script only for behaviour.
- [ ] No theme overrides you can't justify; `theme_type_variation` where one fits.
- [ ] Colours are palette values.
- [ ] Whole-pixel sizes; art at 1:1.
- [ ] `unique_name_in_owner` on everything the script touches.
- [ ] Overlay: registered in `_panel_buttons`, mounted at the shared offsets.
- [ ] `focus_mode = 0` on click-only chrome; ladder updated if it is navigable.
- [ ] Headless test written, each assertion seen to fail once, `ALL PASS` green.
