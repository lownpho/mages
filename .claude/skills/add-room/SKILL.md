---
name: add-room
description: Author the World's Rooms through its content model — Zone Room quotas, set pieces (Boss, Miniboss and Rare rooms), the eight Room-shaping knobs, Breather Objects and Signs. Use when the user wants to add a boss/miniboss/rare room, add or resize a Zone, change how many Rooms a Biome has, make Rooms bigger/rockier/loopier/more connected, make the walls (tree lines) between Rooms thicker or more varied, put fountains or other Objects in Breathers, or add a Sign. NOT for new enemy scenes (add-enemy) or retuning enemy numbers and rosters (rebalance-enemies).
---

# Authoring Rooms

Rooms are **generated**, never authored one by one. You edit the World's content model — flat
`.tres` under `game/generation/world/` — and the generator plans every Room from it at Run start.
Every request lands as one of the recipes below, followed by the content check.

Before writing any content `.tres`, read `docs/agents/content-authoring.md`: the saver's order,
the typed-collection script lines and the sub-resource ids every file needs. `docs/` is gitignored,
so in a worktree read it from the main checkout. The domain words (Zone, Set-piece room, Breather,
Teaching room, Fixed encounter, …) are defined in `CONTEXT.md`.

## The content model

Folder and file names are the ids; nothing registers content by hand, so a new Zone file is picked
up as soon as it exists.

| File | Owns |
| --- | --- |
| `world.tres` (`WorldResource`) | topology: the `ideal_path` order and each Side biome with its parent |
| `challenge_curve.tres` | global encounter density and types per Challenge step, `teach_dip`, `respawn_delay`, `breather_chance` |
| `biomes/<biome>/biome.tres` (`BiomeResource`) | exit Challenge, shared roster, the one `boss`, the eight shape knobs, `presentation`, decoration density, Professor count, Signs, Breather Objects |
| `biomes/<biome>/zones/<zone>.tres` (`ZoneResource`) | `route_rooms` and `room_count`, additive roster, `minibosses`, `rares`, decoration override, Signs, Breather Objects |
| `biomes/<biome>/art/` | the Biome's presentation and tilesets (see `biome-scenery`) |

The resource classes and their doc comments are in `game/generation/content/`. A new Biome also
needs a `world.tres` entry, a Boss and art — a bigger job than a Room.

## How Rooms come out of it

- A Biome's Zone order is seeded; the single Spawn zone (`spawn = true`, in the first Ideal-path
  Biome) always comes first. Each Zone keeps its quotas wherever it lands.
- `route_rooms` Rooms lie on the Ideal path (or the Side route). `room_count` is every Room the
  Zone owns, route Rooms included.
- Roles fill the quota: a Teaching room for each enemy at its first eligible route position, the
  set pieces (the Biome's Boss in its last Zone, the Zone's Minibosses and Rares), then Testing
  rooms. A non-Teaching ordinary Room becomes a Breather with the curve's `breather_chance`, which
  only means it draws a Breather Object — it still fights. Signs and Professors stand in ordinary
  Rooms of any role and leave their encounters alone.
- Set-piece rooms are spacious, off-route, have exactly one Passage and never hold Objects. The
  Boss sits near the end of its Ideal path or Side route, Minibosses late in their Zone, and Rares
  move with the seed.

## Recipes

### A Boss, Miniboss or Rare room

Add a Fixed encounter sub-resource — `boss` on the Biome (exactly one, required), or an entry in a
Zone's `minibosses` or `rares`:

```
[sub_resource type="Resource" id="miniboss_thornmess"]
script = ExtResource("fixed_encounter")
leader = ExtResource("thornmess")
centred = true
```

`leader` is an enemy's `<id>_data.tres`; `escorts` maps more data sheets to counts. The Zone's
`room_count` must still fit the new set piece.

### More or fewer Rooms

Set `route_rooms` and `room_count` on the Zone. `room_count` has to hold the route Rooms plus the
reserved roles (a Teaching room per newly eligible enemy, the set pieces); the check reports a Zone
quota it can't fit.

### Room shape

The Biome's eight knobs (Zones inherit them). Ranges are the debug sliders':

| Knob | Range | Effect |
| --- | --- | --- |
| `room_size` | 16–64 | typical Room diameter in tiles |
| `border_warp` | 0–12 | how far Room borders wander |
| `loops` | 0–1 | chance of a loop Passage between neighbouring ordinary Rooms |
| `shortcuts` | 0–0.8 | chance of a shortcut where route stretches fold alongside one another |
| `passage_width` | 2–12 | Passage width in tiles |
| `rockiness` | 0–0.6 | share of the open floor that turns to rock (0.1 is light, 0.3 dense) |
| `wall_depth` | 1–6 | depth of the wall on each side of a Room border, in tiles |
| `wall_variation` | 0–4 | how far `wall_depth` wanders along a border, in tiles either way |

Tune them live (below) and let **Save** write them back, rather than guessing numbers in text.

### Objects, Signs, Professors

- `breather_objects`: scene → weight, added across the Biome and its Zone; a Breather draws one or
  stays empty. Fountains are `game/objects/fountain/*_fountain.tscn`. An Object scene takes its
  generated data through `setup(data: Dictionary)`.
- `signs`: `text`, plus `reveals` (an enemy data sheet) when reading it should reveal the nearest
  Boss or Miniboss that enemy leads. Each Sign stands exactly once.
- `professors` count on the Biome. A Professor (`game/objects/professor/`) reads
  the Bestiary page of its own Biome and pays out once a Run when that page is complete. Its kind is
  seeded per site, not authored: half open a portal into the **Biome onward** (the next on the Ideal
  path, or the one after a Side biome's parent), half give up one of the items that drop there. A
  sealed Biome onward, or the end of the Ideal path, leaves the Professor with nothing to give — it
  still stands and says so. What it says lives on `professor.tscn` as `{biome}`/`{next}`/`{seen}`/
  `{total}` templates, not in the script.

### Which enemies a Room fights

Not authored per Room: rosters, Entry challenges, Hazards and the curve decide it — see `add-enemy`
and `rebalance-enemies`.

### The interior algorithm

Every Biome shares one interior algorithm (`game/generation/interiors/`); there are no per-Room
generators. Changing it is code: every Passage and Object spot must stay reachable, which
`test_world_tiles` checks at each knob extreme.

## Check every edit

```sh
godot --headless --path game res://generation/content/check_content.tscn
```

It exits 0 when the World loads clean; otherwise it prints one `path:line: problem` per problem.

## See it live

```sh
godot --path game res://scenes/world.tscn -- seed=123
```

Entering the World writes the Run save, so this replaces a saved Run. **Tab** pauses and opens the
debug panel; clicking the World to its right teleports there.

- **World:** seed and Reroll, the Biome picker, its eight knobs and the four set-piece radii (↶
  reverts to the authored value), derived Room totals, **Rebuild** (applies pending edits: changed
  Biomes' Rooms only, radius edits replan the World), **Save** (writes changed knobs into
  `biome.tres`) and Fly.
- **Overlays:** Ideal path, roles, Passages, Zones, Challenge, macro grid, discovery, outlines.
- **Map:** the whole World's graph — wheel zoom, middle/right drag pan, click to teleport.

After editing `.tres` by hand, the console's (`` ` ``) `reload` rereads the content and rebuilds at
the same seed; with unsaved knob edits it warns first and discards them on a second `reload`.

## Tests

Each prints `ALL PASS` or `FAILED: <n>`. A GDScript parse error hangs headless Godot, so wrap each
run in `timeout -s KILL 300`:

```sh
godot --headless --path game res://tests/generation/test_content.tscn       # load pass, saver order
godot --headless --path game res://tests/generation/test_world_plan.tscn    # Zone order, quotas, set pieces, Challenge
godot --headless --path game res://tests/generation/test_room_graph.tscn    # reachability, roles, isolation, knob sweep
godot --headless --path game res://tests/generation/test_world_tiles.tscn   # interiors and tiles at knob extremes
godot --headless --path game res://tests/generation/test_encounters.tscn    # rosters, Teaching rooms, Fixed encounters
godot --headless --path game res://tests/generation/test_world_objects.tscn # Object sites, Signs, Portals
```

`test_content` also saves the shipped World in place and fails on any file a save would rewrite,
then restores the text.
