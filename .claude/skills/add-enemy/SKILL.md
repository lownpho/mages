---
name: add-enemy
description: Add a new enemy, monster, creature or boss to the game — composing its scene from the shared behaviour library, its bespoke cast spells and its CreatureResource. Covers the behaviour exports, the two dispatchers, pack aggro, telegraphs, roster placement and the Godot gotchas.
---

# Adding a new enemy

An enemy is a **composition**, not a script — the whole roster of 52 (three bosses included)
needs **zero per-enemy code**. You assemble nodes and set exports.

Source of truth is the code's own doc comments: `characters/creature/creature.gd`,
`characters/creature/behaviours/*.gd`, `characters/player/spells/spell_caster.gd`,
`items/bullets/base_bullet.gd`. `design/docs/enemies.md` is the browsable catalogue of what
already exists — its numbers are extracted from the `.tres` files themselves, so it is never
stale. This skill is the procedure on top of both.

## The model

1. **The body — `Creature` (`characters/creature/creature.gd`).** Faction-agnostic, shared by
   every enemy *and* every player summon; never subclassed. Faction is two exports:
   `target_groups` (default `["player", "summon"]`) and `bullet_collision_layer` (default
   `LAYER_ENEMY_BULLETS`). Services beats call: `get_target()`, `look_for_target(probe)`,
   `probe_sees(probe)`, `get_aim_direction()`, `make_timer(cb)`, `play(anim, speed_scale)`,
   `play_fitted(anim, duration)`, `face(dir_x)`, `telegraph(color)`, `telegraph_off()`,
   `apply_knockback(impulse)`, `start_dash(dir, speed, duration)`, `is_dashing()`.
   Scalar stats live in `data: CreatureResource`, not on the root. It already does off-screen
   sleep and forces `hit_from_inside` on every child RayCast2D (so probes don't go blind at
   melee range) — don't re-add either.

2. **The library — `characters/creature/behaviours/`.** `Behaviour extends State`; the base
   exposes the owning body as **`creature`** and wires `enter()` / `exit()` /
   `physics_update(delta)`.

3. **Glue = the scene.** One child `Node` under `$FSM` per beat, named for its **role**. That
   name is the state name used by `initial_state` and every `*_state` export.

### Library behaviours

| Behaviour | Shape | Key exports |
| --- | --- | --- |
| `hold.gd` (**Hold**) | Plant, pose, hand off once the clock lapses **and** the destination is willing. Idle, recovery-between-shots, rest, stagger — all one node. | `anim`, `min_time`/`max_time`, `next_state`, `probe_path`, `seen_state`, `lost_state`, `lost_margin`, `alert_on_hit`, `react_min`/`react_max` |
| `wander.gd` (**Wander**) | A Hold that drifts (overrides the `_tick` seam). | the above + `speed` |
| `approach.gd` (**Approach**) | Closing, in every shape: LOS-gated chase, weaving, or a boss's committed pursuit on a clock. | `speed`, `anim`, `chase_probe_path`, `lost_state`, `lost_grace`, `duration`, `done_state`, `attack_probe_path`, `attack_state`, `wait_state`, `weave_amplitude`, `weave_frequency` |
| `cast.gd` (**Cast**) | One beat = one `cast()`. Owns WHEN the burst starts, what the sprite does, and when to give up. | `caster_path`, `spell`, `done_state`, `attack_probe_path`, `out_of_range_state`, `exit_margin`, `windup_anim`, `attack_anim`, `windup_damage_scale`, `min_release_fraction`/`max_release_fraction`, `telegraph_color` |
| `charge.gd` (**Charge**) | A Cast whose spell drives the caster (ChargeDash). Locks heading once the dash is under way. | Cast's + `blocked_state` |
| `flee.gd` (**Flee**) | Bolts in a *random* direction re-rolled per entry. No clock = run till cornered (viper); `duration` set = the hit-and-run half of a loop (moth). | `chase_probe_path`, `retreat_probe_path`, `lost_state`, `cornered_state`, `speed`, `retreat_range`, `run_anim`, `duration`, `done_state` |
| `tether.gd` (**Tether**) | Orbit an anchor until a target shows. Used by the **player's summon minions** (halp, bzzz), not by any hostile enemy — but it is faction-agnostic like everything else. | `detect_probe_path`, `anchor_group`, `alert_state`, `follow_speed`, `orbit_radius`, `orbit_speed`, `queue_spacing`, `fly_anim` |
| `pattern_picker.gd` (**PatternPicker**) | Dispatcher — weighted roll. | `probe_path`, `lost_state` |
| `gate.gd` (**Gate**) | Dispatcher — ordered ladder. | `beats`, `probe_path`, `lost_state` |

**Approach's two gates are the thing people get wrong.** Arriving is a question about distance,
firing a question about the cooldown. `attack_probe_path` + `attack_state` is arrival;
`wait_state` is where arrival lands while the attack is still cooling. Leave `wait_state` empty
and a ranged creature walks a full cooldown's worth of pixels into the player's face.

### The base — `can_run()`

One eligibility predicate, asked by both dispatchers and by any `Hold` handing off. These dials
live on `Behaviour` and work under any shape:

| Export | Use |
| --- | --- |
| `pattern_weight` | Relative odds in a PatternPicker roll. **0 keeps it out of the pool** — that's why Idle/Chase are never rolled. |
| `health_min` / `health_max` | The beat's health window — how phases are authored. thornmess trades `Bloom` (`0.25..1`) for a `Spores` screen (`0..0.25`); gnarlking swaps `Call` for `CallBig` and `Winded` (5s) for `WindedShort` (3s). |
| `priority` | Positive priority jumps the queue instead of being rolled. |
| `once` | At most once per fight. Paired with `priority`, that's a desperation opener. |
| `clear_group` / `clear_radius_tiles` | Refuse to run while a pack member stands nearby. Counted **positionally** — streaming keeps other rooms' packs loaded. |
| `range_probe_path` | Eligible only while the target is inside this probe. Range answered *before* committing — unlike `Cast.attack_probe_path`, which bails once the beat is already running and reads as a boss rearing into a slam at nothing. |
| `damage_scale` | Armour for the beat's duration. <1 armours, 0 untouchable, >1 a punish window. Restored on exit. |
| `needs_cloud` / `refuses_cloud` | Gate the beat on standing in a spore cloud — the mycelium roster's "only while coated" rungs. |

## The two dispatchers

Both defer their hand-off one frame, so the FSM finishes entering before `transition_to` takes it
back out. Both answer `_ready_to_run()` with "do I have anything to dispatch", so a `Hold` pointed
at one waits the whole pool's cooldowns out instead of bouncing through every frame.

- **`PatternPicker`** falls back to the full pool when nothing is eligible, so it can't deadlock.
- **`Gate`** has no such fallback: **its last rung must be something always eligible** (a Hold).
  That floor is the only thing standing between an authored ladder and a stuck boss.

**Gates nest.** The gnarlking is three: `Summon` (`CallBig`, `Call`) → `Hunt` (`Charge`, `Slam`,
`Volley`, `Close`, `Brace`) → `Breathe` (`WindedShort`, `Winded`). A rung that is itself a Gate
gives a phase its own sub-rotation; a two-rung Gate whose rungs differ only by health window is
just a phase switch.

## Casting

**One `SpellCaster` node per enemy** (`characters/creature/creature_caster.tscn`, which is just
`spell_caster.gd` on a Node2D — the *same* engine the player casts through). Multiple attacks are
multiple **spell `.tres` files**, one per `Cast` beat, not multiple casters; per-spell cooldowns
are keyed by the resource. A couple of creatures (golem, longleg) carry two casters when two
beats must cool independently.

Each attack is a bespoke, unregistered `<id>_<beat>.tres` in the enemy's own folder, usually a
`BulletSpellResource` reusing `characters/player/spells/bullet_spell.tscn`. **Damage lives on the
spell, never on the bullet**: a `damage: ScalingProfile` sub-resource with `base_damage` set and
every `*_scaling` left at 0 (enemies have no stats to scale off). Burst length (`max_shots`),
cadence (`shot_interval`), aim drift (`rotation_per_shot`) and lane commitment (`aim_mode`:
Track / Lock / Independent) are that resource's data — a beat must never grow its own shot
counter.

Summons are the same mechanism: a `SummonResource` in the enemy's folder pointing at other
scenes (`gnarlking_brood.tres` → grimling scenes, with `count`, `minion_health`,
`minion_lifetime`, `minion_spell`).

## Kinds and weakness

`CreatureResource.kinds` says what the creature is *made of* (`GameConstants.KIND_INSECT`,
`KIND_FUNGAL`); `SpellResource.weakness` says what a cast is *made to kill*. One bitwise `and`
in `Creature._on_hurt` doubles the hit. Set `kinds` when the answer is obvious (a moth is
insect, a cap is fungal; the moss golem is both) and leave it 0 otherwise — a mismatch is never
punished, so the field only ever adds upside for a player who went and got the side tier.

## Pack aggro

`components/pack.gd` — a `Pack` node beside the FSM. The moment one member enters `alert_state`
from a calm state, every packmate within `radius_tiles` engages and relays from its own position,
so an alert walks a strung-out pack.

**The trap: the group name goes in two places** — the `group` export *and* the node's own Groups
list. One is who we shout to, the other is who hears us; setting only one half-wires it silently.

It pairs with a boss's `clear_group`: the gnarlking's charge stays shut behind `pack_grimling`, so
the player's clear speed decides when the fight swaps phase.

## Telegraph flashes

A `Cast`/`Charge` beat with a `cast_time` already holds a wind-up; `telegraph_color` is what makes
the player *see* it. Set it and the creature pulses **once** in that flat colour as it commits
(`Creature.telegraph(color)`, the palette-safe `gui/flatten.gdshader`), then goes back to normal.

- **Default is transparent — a beat is silent until you decide it's worth shouting about.**
- **Telegraph a beat whose `cast_time` is ≳0.45s, or one that's *disruptive* below that** — AoE
  under the player, a phase change, a death burst. Fast pokes and chip volleys stay silent. **A
  tell on every attack is no tell at all**; the roster telegraphs 56 of its 90 cast beats.
- **Colour is the creature's own accent, usually its eye colour**, from `Palette`
  (`globals/palette.gd`) — so the flash says both "incoming" and "from what".
- **A boss authors one hue per beat**: gnarlking green for brood, red for slam, orange for charge,
  yellow for volley; grimlord white for enrage and its death burst, silent on its ordinary bolt.
- **One pulse, never a loop.** `test_behaviours` bounds the flash against `Creature.TELEGRAPH_FLASH`,
  so a re-introduced strobe fails.

Two traps, both silent: `flatten.gdshader` **multiplies** texture alpha, so driving `flat_color.a`
to 0 blinks the creature out of existence (swap `sprite.material` instead); and a shader
parameter's sub-path doesn't resolve for `tween_property` — use `tween_callback`.

## Two idioms not visible in the exports

- **Hysteresis on every boundary.** `Hold.lost_margin` and `Cast.exit_margin` spawn a longer shadow
  probe so a target loitering on the edge can't strobe the creature; `Approach.lost_grace` buys
  seconds of unbroken no-LOS before a committed pursuit gives up.
- **`death_state`** on the scene root → a parting-shot beat (grimlord's `DeathBurst`). Separate
  from `CreatureResource.death_spawns`, which leaves *bodies* behind unconditionally (a bloatcap
  bursting into its brood) on the same path as the loot drops.

## Reference enemies (copy from these)

- **`sproutling/`** — the minimum, and the shape most enemies are: `Idle`(Hold) → `Attack`(Cast) →
  `Recover`(Hold with `min_time = max_time = 0`) → back. The zero-length Hold just re-asks
  `can_run()`, so the spell's own cooldown paces the loop and nothing counts shots.
- **`moth/`** — hit-and-run: weaving `Chase`(Approach) → `Poke`(Cast) → `Retreat`(Flee on a clock).
- **`grimlord/`** — PatternPicker, health-window phases, `Pack`, `death_state`.
- **`gnarlking/`** — nested Gates, `clear_group`, Charge with `blocked_state`, per-beat telegraph
  hues, summons. The worked example for a learnable rotation.
- **`bloatcap/`** — `death_spawns`, and the mycelium `needs_cloud` idiom.

## Naming conventions

- **Behaviour script: file name ⇄ class name, no suffix.** `approach.gd` → `class_name Approach`.
- **State node names are semantic roles, chosen per enemy — they may differ from the class.**
  thornmess's `Uproot` runs Approach, its `Pick` runs PatternPicker; gnarlking's `Hunt` runs Gate.
  This divergence is expected, not a smell.
- **Destination strings name node names, never class names.** A string matching no sibling fails at
  runtime with `State not found:`.
- **Probes are named role + type** (`DetectProbe`, `ChaseProbe`, `AttackProbe`, `SlamProbe`,
  `RetreatProbe`). Beats reach them by `NodePath`, so these only need to be clear.

## When to write a new behaviour

Almost never — the library covers the whole roster, and no shipped enemy has its own script. Check
first that the shape isn't already an unset dial away: a "guard" is a Hold with `damage_scale`, a
"sniper charge" is a Cast with a `windup_anim`, a "committed charge" is an Approach with no
`chase_probe_path`.

If you genuinely must, subclass the closest library behaviour and override its seam
(`Hold._tick`, `Cast._track_aim`, `Behaviour._ready_to_run`) — that's all `Wander` and `Charge`
are. One-off → the enemy's own folder; reusable → `behaviours/` with a `class_name`. Three rules:
call `super()` first in `_ready()`, take timers from `creature.make_timer(cb)` (never `add_child`
one), and tear down in `exit()` what `enter()` started. Use `creature.look_for_target(probe)`, not
`look_at` + `probe_sees` — a raycast read directly answers for last frame's aim.

## Procedure

1. **Sprite.** `<id>.png` in `characters/enemies/<id>/`, one row per animation. 47 of the 55
   shipped sheets are 8×8 frames; five are 16×16, the gnarlking 16×24. See the `creature-sprite`
   skill for the art itself.

2. **Texture import.** Each `.png` needs a `<id>.png.import`. Easiest: open the project in Godot
   once and let it generate the `.import` and uid.

3. **Cast spells.** One `<id>_<beat>.tres` per attack, copied from a reference enemy's. A
   `damage` `ScalingProfile` sub-resource with `base_damage` only, every scaling 0. Bullet stats
   (`range_tiles`, `speed_tiles`) in **tiles**, on an inline `BulletResource` that carries no
   damage. Pick an existing `FirePattern` (Single, Shotgun, Ring, Parallel, Flank). Anything
   beyond flying straight is a `BulletBehaviour` in the bullet's `behaviours` array (homing,
   chain, bounce, blast payload) — never a new field or a new bullet script.

4. **`<id>_data.tres`** (`CreatureResource`): `display_name`, `icon` (an AtlasTexture region off
   the sheet, the idle frame at native size), `rarity`, `max_health`, `kinds`, `drops` as
   `LootDrop` sub-resources (item + chance), optional `death_spawns`.

5. **Scene `<id>.tscn`.** Copy the closest reference and adapt:
   - Root `CharacterBody2D`: `creature.gd`, group `enemies`, `collision_layer = 32`,
     `collision_mask = 33`, `motion_mode = 1`, `data = <id>_data.tres`. Optional `death_state`.
     Leave `target_groups`/`bullet_collision_layer` at their hostile defaults.
   - `CollisionShape2D`, `AnimatedSprite2D` `SpriteFrames` (a sub-resource in the scene; define
     every animation a beat `play()`s), probe `RayCast2D`s (`collision_mask = 17` — terrain +
     player, so probes are LOS).
   - `Hurtbox` instance (`collision_mask = 256`) and one `SpellCaster`
     (`characters/creature/creature_caster.tscn`). Optional `Pack`.
   - `$FSM` (`components/fsm.tscn`): set `initial_state`; **leave `state_names` empty**. One child
     Node per beat with its behaviour script and exports wired — probe `NodePath`s
     (`NodePath("../../DetectProbe")`), `caster_path`/`spell`, destination strings, dials.
   - Per `Cast`/`Charge`: decide `telegraph_color` per *Telegraph flashes*.

6. **Place it.** Enemies are **streamed by the World generator**, not placed by hand —
   `world.tscn`'s `EncounterSpawner` adds them under `WorldRoot/Entities` as their chunks stream
   in. Put the enemy's `<id>_data.tres` on
   a **roster** with its Entry challenge: `roster` in a Biome's
   `game/generation/world/biomes/<b>/biome.tres` (shared by its Zones) or in one Zone's
   `zones/<zone>.tres`, and in `fillers` too if it should join every ordinary encounter once
   eligible. Each rostered enemy gets a Teaching room on every route that reaches its Entry
   challenge. A Rare, Miniboss or Boss instead leads a Fixed encounter (`rares`/`minibosses` on a
   Zone, `boss` on a Biome). How many come per encounter and how often it's drawn are `group_min`,
   `group_max` and `weight` on the `CreatureResource` itself. The `add-room` skill covers the
   content model, its authoring rules and the check command. An enemy may legitimately ship
   unrostered.

7. **Document it — mandatory.** Add the id to `design/data/enemies.yaml` (`id`, `description`,
   `art`, `casts`, optional `notes`, `fsm` transitions) and rebuild. **Never write a number
   there** — HP, damage, drops, speeds and ranges are extracted from the game by
   `design/tools/extract.py`. The build fails loudly if the yaml names an enemy the game doesn't
   have, or the game ships one the yaml doesn't list.

   ```bash
   design/tools/.venv/bin/python design/tools/build.py     # --check to verify without writing
   ```

   Use that venv python: the system `python3` has no PyYAML/Jinja2. The same script is the
   repo's `pre-commit` hook (`design/tools/pre-commit`, installed by hand with
   `ln -sf ../../design/tools/pre-commit .git/hooks/pre-commit`).

## Godot gotchas

- **uids.** Every `.gd`/`.tscn`/`.tres`/`.png` is referenced by `uid://…`. A copied file needs a
  **new, unique** uid (`.gd.uid` sidecar for scripts, header line for scenes/resources).
  References fall back to `path=`, so a mismatch self-heals on next import.
- **`$FSM` uses real child nodes — don't set `state_names`.** It auto-creates dumb `State` nodes
  that collide with your beats.
- **Never call `fsm.start()`** — the body does, deferred, so every beat's timer exists before the
  first `enter()`.
- **Animation names must match the strings beats `play()`.** A missing tag is silent.
- **The live editor re-saves scenes from memory and clobbers on-disk edits.** After editing a
  `.tscn`/`.tres` on disk while Godot is open: **Scene ▸ Reload Saved Scene** before anything that
  triggers a save. The editor owns `.import`/uid regeneration — let it.
- **Headless runs hang while the editor is open** (asset-import lock). Zero output + timeout =
  a **GDScript parse error** (unused params/iterators are errors), not slowness.
- After adding a `class_name`: `godot --headless --editor --quit --path game` once to rebuild the
  class cache.

## Validate

```bash
godot --headless --path game res://tests/test_enemy_scenes.tscn
```

Instantiates every enemy, checks it carries a `CreatureResource` with hp + icon, and that every
`*_state` export resolves to a real sibling — the typo in a rarely-rolled boss beat that would
otherwise stay invisible until mid-fight. Then `test_behaviours`, `test_creature_caster` and
`test_any_caster`, plus `tests/generation/test_content.tscn` and `test_encounters.tscn` if you
touched a roster.

Finally fight it in the real World: `godot --path game res://scenes/world.tscn` (append
`-- seed=<n>` for a fixed World). Entering the World writes the Run save, so this replaces a
saved Run. **Tab** pauses and opens the debug panel; on its **Combat** tab pick the enemy (new
enemies are discovered from disk) and left-click the World to place it, right-click removes one.
Or `spawn <id> [n]` in the console (`` ` ``).
