---
name: add-room
description: Add a new room type to the procedural world generator, or change how rooms are shaped/placed. Use when the user wants to create/add a room, room type, boss room, arena, shop, shrine, or "guaranteed" room in a biome; wants a room to always appear (once or N times); wants to control where on the difficulty ramp it lands; wants to pick/tune the generator that carves a room's interior (scatter, cave, arena) or make it an organic blob pocket; or wants to wire enemies/features into a room. Covers RoomTypeDef, the three generators, footprint_blob, quotas and the difficulty ramp, spawn tables, features, registration in gen_config, and the CONFIG_HASH/gen_version rule. NOT for adding whole biomes (that's a bigger job) or new enemy scenes (use add-enemy).
---

# Adding a room to the world generator

Rooms are **data**, not code. A room type is one `RoomTypeDef` `.tres` that is the **complete,
hand-authored room**: which biome owns it, where on the difficulty ramp it sits, how rare it is,
which generator carves its interior, its own enemy pool and budget, and any features standing in
it. Adding a room is almost always: make one `.tres`, register it in `gen_config.tres`. You only
write code for a genuinely new *generator algorithm*.

The architecture source of truth is the doc comments in `game/worldgen/core/room_type_def.gd`
and `game/worldgen/layers/room_graph.gd` — the latter documents the exact RNG order and the
placement passes. `design/docs/biomes.md` is the generated catalogue of what currently exists
(every room, its shape, its count and its rolled enemy groups), extracted from the `.tres` files
themselves, so it is never stale.

## The one rule you cannot skip

**Register it or it doesn't exist.** Everything is stitched together by
`game/world_content/gen_config.tres`. A room type that isn't in its `room_types` array is
invisible to the generator. (There is a second world: `world_content/mycelium_gen_config.tres`,
with per-floor configs under `world_content/mycelium_floors/` — a mycelium room registers there
instead.)

**There is no "remember to bump the version" rule for data.** `GenConfig.compute_hash()` folds
every world-affecting authored field — room types, their generators, their spawn tables, biomes,
adjacency — into `CONFIG_HASH`, which is mixed into every seed. So adding or editing a room type
*already* re-rolls saved worlds, loudly and by construction. `gen_version` is the manual dial for
what the hash **cannot** see: a change to generator or layout **code**. Bump it then, not for
`.tres` edits.

## Where things live

| What | Path |
|---|---|
| Master config | `game/world_content/gen_config.tres` (and `mycelium_gen_config.tres`) |
| Room types | `game/world_content/biomes/<biome>/rooms/<biome>_<name>.tres` |
| Feature data (door configs, etc.) | next to the biome that uses it, e.g. `biomes/glade/cave_door.tres` |
| Biome definitions | `game/world_content/biomes/<id>/<id>.tres` |
| Generator scripts (code) | `game/worldgen/generators/` |
| Enemy scenes (for spawn tables) | `game/characters/enemies/<id>/` |

Every room type belongs to **exactly one biome**, named by its own `biome` field. There is no
per-biome room table to add a row to — the room type declares its own membership, quota and
weight. (The one exception is a `WORLD`-unique type, which leaves `biome` empty.)

## RoomTypeDef fields

| Field | Meaning |
|---|---|
| `id` | Unique `&"name"`. Convention: `<biome>_<name>`. |
| `biome` | The one biome that hosts it. `&""` only for `WORLD`-unique types. |
| `generator` | A generator Resource, embedded as a sub-resource (see below). `null` = empty room, just floor. |
| `unique_scope` | `NONE` for everything except `WORLD` = **exactly one in the whole world**, pinned as a 1×1 leaf at world layout. |
| `unique_allowed_biomes` | `WORLD` only: which biomes may host it. Ignored for `NONE`. |
| `min_size_slots` / `max_size_slots` | Size window in slots, `Vector2i`. A room fits if `(w,h)` **or** `(h,w)` lies within it per axis, so orientation doesn't matter. Quota placements get a leaf of exactly `min_size_slots` carved for them by construction. |
| `difficulty` | 0–3. **This is placement, not tuning.** The biome's entrance-depth range splits into quarters; difficulty ≥ 2 lands as far from the entrance as the geometry allows, ≤ 1 as near. 0 = spawn-adjacent breather, 3 = the boss's quarter. |
| `footprint_blob` | Interior becomes an organic pocket carved from solid mass; corridors tunnel in. |
| `weight` | Relative odds in the weighted fill. **`0` = quota-only** — the room appears exactly as often as `min_per_biome` says and never rolls up as filler. |
| `min_per_biome` | Guaranteed placements, carved and assigned before any fill. `min == max` pins an exact count. |
| `max_per_biome` | Fill weight drops to 0 once this many are placed. |
| `enemies` | This room's own weighted `SpawnTableEntry` pool. `[]` = never spawns anything. |
| `enemy_groups_min` / `max` | Population budget. `0/0` = safe room. |
| `scale_groups_with_size` | Multiply the budget by the room's slot area. Turn **off** for exactly-one encounters (boss, rare, shrine) so a big leaf doesn't duplicate the set-piece. |
| `features` | `Array[RoomFeature]` — specific scenes (doors, altars, portals) placed on the finished room. Deliberately **not** hashed. |

## How a room type gets into the world

`RoomGraph.build()` carves the biome with a demand-carving guillotine BSP — correct by
construction, no retries — then assigns types in three passes:

1. **World-unique pins** (`unique_scope = WORLD`), stamped with no RNG.
2. **Quota minimums**, in descending difficulty (so the boss picks before lesser set-pieces).
   Each takes the free room whose depth **tier** is nearest its authored `difficulty`, among
   those fitting its size window.
3. **Weighted fill** over what's left, sampling among the types whose size window fits *and*
   whose difficulty matches the room's tier, falling through to lower tiers, and finally to the
   biome's `fallback_room_type` when nothing fits.

So one row's worth of policy is just three fields on the type itself:

- **Filler (maybe none):** `min_per_biome 0`, a `weight`, a sensible `max_per_biome`.
- **Exactly one (boss/gate/rare):** `min 1, max 1, weight 0`.
- **At least one, possibly more:** `min 1`, a `weight`, a higher `max`.

In the debug biome view, quota-guaranteed types outline cyan and world-uniques gold.

### Recipe: a room that always appears once in one biome (a glade boss)

Copy `world_content/biomes/glade_start/rooms/glade_start_boss.tres` — it is exactly this shape:

```
id = &"glade_start_boss"        biome = &"glade_start"
min_size_slots = Vector2i(2, 2) difficulty = 3
weight = 0  min_per_biome = 1   max_per_biome = 1
enemies = [ SpawnTableEntry with members = [PackMember{enemy_id = &"fae"}], pack_spread = 2.0 ]
enemy_groups_min = 1  enemy_groups_max = 1  scale_groups_with_size = false
```

Then add it to `gen_config.tres` → `room_types`. That's the whole job. `glade_start_gate_deepwood`
is the same with a `generator`, `footprint_blob = true` and a door `RoomFeature`.

## Generators

The generator carves the interior. Three exist — **reuse one with different numbers** (embed it
in the room-type `.tres` as a sub-resource); you rarely write a new one.

| Generator | Makes | Key `@export`s |
| --- | --- | --- |
| `RoomGenScatter` | Scattered blockers / clumps (rocks, trees) | `count_per_slot`, `min_spacing`, `clump_min`/`clump_max` |
| `RoomGenCave` | Organic cave (cellular automata) | `fill_prob`, `iterations`, `write_blockers` (emit BLOCKER/trees instead of WALL) |
| `RoomGenArena` | Blocker ring with gaps, open center — boss/arena | `inset`, `thickness`, `gap_count`, `gap_width` |

Note: a biome's *presentation* decides the art. Forest biomes (glade, deepwood) point both
`wall_tileset` and `object_tileset` at their tree tileset, so a cave or arena there reads as
trees, not rock.

Independent of the generator, `footprint_blob` reshapes the whole room into an organic pocket
(solid mass outside a noise-warped radius, corridors tunnelling in) — combine it with a generator
for the interior, or use it alone.

### Writing a new generator (only if the three can't make the shape)

1. Create `generators/generator_<name>.gd extends RoomGenBase`; copy `generator_scatter.gd`.
   Implement `run(grid, protected, w, h, rng, spec)` (write tiles) and `hash_fold(h)` (list every
   `@export`, starting with `h = super.hash_fold(h)` — the base folds the class name, so two
   generators with identical fields still hash apart).
2. **Rules `run()` must obey** (or you break connectivity / determinism):
   - Write only `RoomBuilder.FLOOR / WALL / BLOCKER / DECOR_FLOOR`. Index is `y * w + x`.
   - **Never touch a tile where `protected[idx] == 1`** — those are the corridors and openings
     that keep the room reachable.
   - **Only use the passed `rng`.** Never `randi()`/`randf()`. For probabilities use
     `WgHash.threshold(p)` compared against `rng.randi()` (see `generator_cave.gd`).
   - Every tunable is an `@export` and appears in `hash_fold`.
3. Set it as a room type's `generator`. **This is code, so bump `gen_version`.** Rebuild the
   class cache (see gotchas).

## Room size (there is no merge chance)

Room size comes from the BSP, not from a merge roll. `GenConfig.bsp_max_leaf_slots`
(default 3×3) caps a room; `bsp_stop_chance` is the per-rect probability that a rect already
within that cap stops splitting — raise it for bigger rooms, lower it for more, smaller ones.
`BiomeDef.bsp_stop_chance` overrides it per biome (`-1` = inherit). Quota rooms don't roll at
all: their leaf is carved to exactly `min_size_slots` before random subdivision starts.

## Enemies & features in the room

- **Random adds** are the room type's own `enemies` array — a weighted list of `SpawnTableEntry`
  (`enemy_id`, `weight`, `group_min`/`group_max`, `pack_spread`). An entry with a non-empty
  `members` array is a **mixed pack** instead: each `PackMember` brings its own
  `count_min`/`count_max` around a shared centre. `enemy_groups_min`/`max` controls *how much*,
  the pool controls *which*. Enemy ids are folder names under `game/characters/enemies/`.
- **A specific, guaranteed thing** (a boss door, an altar, a portal) is a `RoomFeature` in
  `features`: a `scene`, an optional `data` Resource applied through the instance's
  `setup(data)`, a `placement` (`CENTER` / `RANDOM_REACHABLE` / `NEAR_WALL`) and a count range.
  Use this for set-pieces rather than hoping the random table rolls one. Features are not hashed
  and draw from the `NS_FEATURES` stream, so swapping them never re-rolls a saved world and can
  never shift enemy identity.

## Procedure

1. Decide the policy: filler (`min 0` + weight), exactly one (`min 1, max 1, weight 0`), at least
   one (`min 1` + weight). Only a one-per-world room uses `unique_scope = WORLD` instead.
2. Copy the closest existing room from `world_content/biomes/<b>/rooms/` — `*_breather` (safe),
   `*_t1_scatter_var` (filler with a pool), `*_boss` (pinned set-piece), `*_gate_*` (blob + door
   feature), `*_rare_*` (single rare). Set `id`, `biome`, generator + numbers, the size window,
   `difficulty`, the quota triple, the enemy pool and budget, any features.
3. Give the `.tres` a **new uid** in its header.
4. Register it in `gen_config.tres` → `room_types` (or `mycelium_gen_config.tres`).
5. Only if you wrote new code: bump `gen_version` and rebuild the class cache.
6. Rebuild the design docs: `design/tools/.venv/bin/python design/tools/build.py`
   (the system `python3` has no PyYAML/Jinja2). `design/docs/biomes.md` will grow the new room's
   row automatically — never hand-edit inside the `GENERATED CATALOGUE` markers.

## Godot gotchas

- **uids.** Every `.tres`/`.gd` has a `uid://…`. When you copy a file, give it a **new** uid
  (header line for resources, `.gd.uid` sidecar for scripts). Opening the project in Godot
  regenerates missing ones; references fall back to `path=`, so a bad uid self-heals on import.
- **After adding a script with a `class_name`**, rebuild the class cache once or Godot reports
  "Could not find type": `godot --headless --editor --quit --path game`.
- **Close the Godot editor before any headless run** — an open editor holds the asset-import lock
  and headless hangs forever.
- **Zero-output headless timeout = a GDScript parse error**, not slowness (warnings are errors,
  incl. unused params/loop vars — underscore-prefix them).
- **The live editor re-saves from memory.** If a `.tres` is open in Godot while you edit it on
  disk, the next editor save clobbers your change — reload the resource first.

## Validate

See it live in the worldgen debug tool — the fastest loop by far:

```bash
godot --path game res://debug/worldgen/worldgen_debug.tscn
```

Four views over one world state, drilling down: **1** world (biome grid) → **2** biome (room
graph and type layout) → **3** room (the real `RoomOutput`: tiles, **P** protected, **M**
reachability, spawns) → **4** fly (free camera over the live streamed world with real enemies).
**Enter** drills in, **Esc** backs out, **T** teleports to the selection. **R** rerolls the seed,
`[` / `]` walk history, **B** bookmarks one. In fly view, **P** drops a real invulnerable player
in so you can walk and fight the actual room, and **O** shows room bounds and tags. It deep-links
from the CLI too:

```bash
godot --path game res://debug/worldgen/worldgen_debug.tscn -- seed=123 view=2
godot --path game res://debug/worldgen/worldgen_debug.tscn -- config=mycelium
```

Then the headless layer tests (editor closed), each printing `ALL PASS` / `FAILED: <n>`:

```bash
godot --headless --path game res://tests/worldgen/test_room_graph.tscn   # carving, quotas, tiers
godot --headless --path game res://tests/worldgen/test_config.tscn       # registration + hash diet
godot --headless --path game res://tests/worldgen/test_generators.tscn
godot --headless --path game res://tests/worldgen/test_population.tscn   # if you touched enemies
```

`test_config` is the one that catches a room type you forgot to register, or a hashed field that
shouldn't be. **Never boot `world.tscn` headless** — it persists and clobbers the player's save.
