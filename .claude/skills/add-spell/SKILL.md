---
name: add-spell
description: Add a new player spell to the game. Use when the user wants to create/implement a spell from design/docs/spells.md (or a new one) — composing it from a SpellResource (data), an effect scene (behaviour), and tier .tres files. Covers the effect-scene contract, CastContext, the damage-delivery patterns (bullet spell, composable bullet behaviours, AoE, channel, summon, self), file layout, and the Godot-specific gotchas (uids, deferred spawning, headless tests).
---

# Adding a new spell

Spells are **data plus, sometimes, one effect scene**. Most shipped spells have **no script at
all**: they are a `BulletSpellResource` `.tres` pointing at the shared `bullet_spell.tscn`.

The casting machinery never changes. `SpellCaster` (`characters/player/spells/spell_caster.gd`)
handles per-spell cooldowns, the `cast_time` wind-up, channels, and over-time effects; it
instantiates the spell's effect scene, calls `setup(spell, host)`, and adds it to the tree root.
That call is the entire contract. Everything the spell *does* lives in the effect scene.

**The caster is not the player's.** `SpellCaster` is mounted on *any* caster — the player,
every enemy, every summoned minion — and `characters/creature/creature_caster.tscn` is just that
same script on a Node2D. `PlayerCastInput` is the only player-specific piece: it maps
`cast1..cast4` (LMB/MMB/RMB/Space, L1/L2/R1/R2 on pad) onto the spell row of `GlobalInventory`
and calls `cast()`. Creature behaviours call the same `cast()` on their own timing. Keep it that
way (see *Faction-agnostic effects*).

Read the doc comments in `spell_caster.gd`, `cast_context.gd`, `spell_resource.gd`,
`bullet_spell_resource.gd`, `items/bullets/base_bullet.gd` and
`items/bullets/behaviours/bullet_behaviour.gd` — they are the architecture source of truth.
`design/docs/spells.md` is the design catalogue: the prose is hand-written in
`design/data/spells.yaml`, every number in it is extracted from the `.tres` files, so its stats
are never stale.

## The model

A spell is two or three things:

1. **The resource** — a `.tres` per tier. `SpellResource` extends `ItemResource` (so spells ride
   the pickup → bag → spell-row pipeline untouched, and can carry `skill_modifier` /
   `speed_modifier` / `max_health_modifier` / `defence_modifier` as passive grants). It holds
   what every spell shares: `effect_scene`, `cooldown`, `cast_time` (0 = instant; > 0 roots the
   player in the FSM `Cast` state), `channeled`, `weakness`, `blurb`. **There is no mana** —
   cooldowns and commitment are the whole cost model.

   Subclass it **only** when the spell has stats of its own. Shipped subclasses:
   `BulletSpellResource`, `HealResource`, `NopeResource`, `BwoomResource`, `BlinkResource`,
   `ChargeDashResource`, `SummonResource`, `ThwompResource`, `WhumfResource`, `MineResource`.

2. **The effect scene** — root script implements `setup(spell: SpellResource, caster: Node2D)`,
   builds a `CastContext` from the caster, and positions itself. Three optional extras the
   caster looks for:
   - a **`finished` signal** → the effect is *over-time*: the cooldown starts when it ends, the
     spell can't recast while it's live, and a newer exclusive cast `interrupt()`s it.
   - **`interrupt()`** → cut it short; it goes on cooldown exactly as if it had run out.
   - **`channel_released()`** → required on any `channeled` spell; fired on button release, on
     the `cast_time` cap (0 = uncapped), or when a behaviour ends the channel.

3. **The caster** — already exists. The common case touches it not at all.

### Tiers and side tiers

Tiers are separate `.tres` files with bigger numbers sharing one effect scene:
`pew1.tres`, `pew2.tres`, `pew3.tres`. Cooldowns are keyed by the *resource*, so re-slotting
can't dodge them and tiers are genuinely distinct spells. A **side tier** is a third-tier
variant carrying a `weakness` (`pew3_insect.tres`, `blam3_insect.tres`): it hits creatures whose
`CreatureResource.kinds` overlap for double. Side tiers are the reward for going and getting
them — never put a `weakness` on a base tier.

## Modularity — extend the machinery, never special-case a spell

This is the load-bearing principle, and it overrides "don't touch the machinery" whenever they
conflict. A new spell sometimes needs a capability the shared code doesn't have yet. When that
happens, add the capability as a **generic, reusable mechanism** the machinery interprets — a
flag on `SpellResource`, a hook on the caster, a new `BulletBehaviour`, a uniform rule in
`SpellCaster` — **never** an `if spell == bwoom` branch. The test: another spell, including an
enemy-cast one, must be able to reuse it by setting data, with zero new code. If your change
names a specific spell, you did it wrong.

Worked examples, all still in the code:

- **"Redirect damage to something other than health" (Nope)** → a `damage_absorber` hook on the
  caster: the hurt path filters incoming damage through `absorber.absorb(damage) -> remainder`
  before touching health. Nope's effect registers itself for the channel's duration. Any future
  damage-interceptor reuses the same hook — the hurt path never learns a spell name.
- **"Hold as long as you like"** → `cast_time == 0` on a `channeled` spell reinterpreted as
  *uncapped* in the caster: a general meaning of an existing field, not a new flag.
- **"Cooldown starts when the cast ends"** → one uniform rule (`_resolve_cooldown`) covering all
  three cast shapes — instant, wind-up, channel — plus any effect that exposes `finished`.
- **"One burst at a time"** → `_cancel_bursts()` interrupts any live over-time effect when a new
  one starts, for every spell at once. Instants deliberately stack on top of a firing burst.

Three reuse rules baked into the system, all worth preserving:

- **Don't reinvent `BaseBullet` — and don't add fields to `BulletResource`.** A projectile spell
  is a `BulletSpellResource`: a `FirePattern` + an inline `BulletResource` + a `damage`
  `ScalingProfile`, pointing at the shared `bullet_spell.tscn`. **No per-spell script.** Anything
  beyond flying straight is a **composable `BulletBehaviour`** in the bullet's `behaviours`
  array — the shipped set is `homing_behaviour`, `chain_behaviour`, `bounce_behaviour`,
  `blast_payload` (the on-expire AoE that makes a fireball a fireball), `spore_payload`,
  `spore_detonator`. A genuinely new trait is a **new `BulletBehaviour` resource**, never a new
  field on `BulletResource` and never a one-off effect script. Behaviours are shared across
  bullets, so they hold config only — per-bullet counters go in `BaseBullet.runtime`, keyed by
  the behaviour. Then weapons, spells *and* enemies get the trait for free.
- **Faction-agnostic effects.** Keep effect scenes free of "the caster is the player". That is
  what `CastContext` is for: it samples origin, aim **direction** (never a cursor — a stick must
  drive it), `skill`/`speed`/`defence`, `bullet_layer`, `target_groups`, `pierce`, `damage` and
  `weakness` from the caster *once*, in the one place that reads them. `ctx.spawn_bullet(...)`
  stamps all of it. `tests/test_any_caster.tscn` exists to prove a sproutling can cast the
  player's heal and fireball; don't break it. (Player-only utility like Blink is a deliberate
  exception.)
- **Reuse the damage and feedback channels.** Damage always lands through `Hurtbox` +
  `get_damage()` — never a new damage path. Hit/flash feedback goes through
  `gui/flatten.gdshader`, never a sprite scale or a colour tween (off-grid / off-palette).

When you extend the machinery, update its doc comment in the same change, so the next spell
author sees the new knob.

## Damage delivery — pick the right pattern

All damage lands through the target's `Hurtbox` (an `Area2D` that accepts bodies *and* areas
carrying `get_damage()`). Layer + mask + `bullets`-group membership select the behaviour.
Layers are named in `GameConstants`: `LAYER_PLAYER_BULLETS` 256, `LAYER_ENEMY_BULLETS` 512,
`LAYER_SPELL_BARRIER` 1024.

| Pattern | How | Example |
| --- | --- | --- |
| Bullet burst (the default) | `BulletSpellResource` + `bullet_spell.tscn`. `max_shots` 1 = a single projectile. | `pew`, `blam`, `snipe`, `ring`, `zaap` |
| Piercing | `pierce` on the `BulletResource` (or the caster's buff) — leaves the `bullets` group, so the hurtbox damages but can't despawn it | `zoing` |
| Chaining / ricochet / homing | a `BulletBehaviour` in `behaviours` | `chain_behaviour`, `bounce_behaviour`, `homing_behaviour` |
| AoE on impact | `blast_payload` behaviour — spawns a one-shot `DamageZone` of `radius_tiles` at expiry, with optional `frames`. `blast_only` suppresses contact damage so a direct and a splash hit match | `fireball` (pure data — no script) |
| Standalone AoE zone | `components/damage_zone.gd` — an area whose `get_damage()` hits a Hurtbox once on entry | explosions, spore clouds |
| Channel / interceptor | `channeled = true`, effect implements `channel_released()`; register on a caster hook | `nope`, `bwoom` |
| Summon | `SummonResource` (`minion_scenes`, `count`, `spawn_pattern`, `minion_health`, `minion_lifetime`, `minion_spell`, `minion_sheet`) + `summon_spawner.tscn` | `halp`, `bzzz`, `jimmy`, `poot`, `blops` |
| Self / utility | no collision at all; act on the caster and emit the matching `GlobalEvent` signal | `heal`, `blink` |

Damage is always `ScalingProfile.compute(skill, speed, defence)` —
`base_damage + skill*skill_scaling + speed*speed_scaling + defence*defence_scaling`, rounded.
Speed scaling reads **bonus** speed only (above `base_speed`), so an unequipped caster
contributes 0. Stats are authored in **tiles**; convert with `GameConstants.PX_PER_TILE`, never
hardcode 8.

## Reference spells (copy from these)

- **`pew/`, `blam/`, `ring/`, `snipe/`, `zaap/`, `zoing/`** — pure data. Four `.tres` and nothing
  else. **Reach for this first** for any projectile spell.
- **`fireball/`** — also pure data: a bullet whose `behaviours` carry a `blast_payload` with
  per-tier explosion `SpriteFrames`. Proof that "cast time + projectile + AoE" needs no script.
- **`heal/`** — the minimal *scripted* spell: a ~20-line effect that computes a `ScalingProfile`
  off `CastContext`, modifies the caster, emits the event, frees itself. Start here for
  self/utility.
- **`nope/`** — the channel template: registers itself as `caster.damage_absorber`,
  implements `channel_released()`, breaks early when its pool runs dry.
- **`halp/`, `jimmy/`** — summons: no effect script, a `SummonResource` and a minion scene whose
  FSM is built from the same creature behaviour library the enemies use (see `add-enemy`).
- **`oop/`, `ploop/`** — mines: a bullet with no speed goes off where it was spawned.

## Procedure

1. **Design.** Take the intent from `design/docs/spells.md`. Numbers the design doesn't specify
   (projectile speed, timing juice) become `@export`s with sensible defaults.

2. **Folder.** Everything in `game/characters/player/spells/<spell>/`: optional
   `<spell>_resource.gd` + effect scene `.gd`/`.tscn`, and the tier files `<spell>1.tres`,
   `<spell>2.tres`, `<spell>3.tres` (a spell may ship only the tiers it has).

3. **Icons & sprites.** Spell icons live in `characters/player/spells/spells.png`, an **8×8-cell
   grid**; projectile sprites usually come from `items/bullets/bullets.png` (also 8×8 cells).
   Inspect the sheet before guessing regions (the `pixel-art` skill's `inspect_sheet.py` dumps
   it) — rows are themed triplets, one cell per tier. If icons come later, leave `icon` unset
   (slot and ground pickup render empty — say so) and use a placeholder bullet cell.

4. **Resources.** Copy a reference tier `.tres` and adapt. Icon `AtlasTexture` region is
   `Rect2(col*8, row*8, 8, 8)`. Keep one effect scene shared by all tiers.

5. **Visual feedback rules.** The game is palette-locked (Zughy 32, `globals/palette.gd`). Never
   alpha-blend, never `modulate` with a non-white colour, never tween colours — tween coverage or
   position instead. Flat-colour flashes go through `gui/flatten.gdshader`.

6. **Put it in the world.** There is **no item registry** — every item in the game is a spell, and
   spells reach the player two ways: a `LootDrop` entry on some enemy's `CreatureResource`
   (see the `rebalance-enemies` skill for which enemy should carry what), or the starter hand in
   `game/scenes/world.gd` (`roll_starter_hand`). Don't add pickups to `world.tscn` by hand.

7. **Document it — mandatory.** Add the spell to `design/data/spells.yaml` (`id` = the folder
   name, `name`, `category`, `description`, optional `per_tier`) and rebuild. **Never write a
   number there** — cooldown, cast time, damage, tiers and projectile stats are all extracted
   from the `.tres`. The build fails if the yaml names a spell that doesn't ship, or a shipped
   spell is missing from the yaml.

8. **Name the tier files right — the grimoire reads them.** Every `<spell>.tres`,
   `<spell><n>.tres` and `<spell><n>_<kind>.tres` in the folder is a grimoire entry of its own (a
   silhouette until it is picked up), with nothing to register. Keep any other file in the folder
   off that naming (`poot_shot.tres`, not `poot4.tres`), or the book shows it as a spell.
   `tests/test_grimoire.tscn` checks every entry loads as a spell with an icon and an effect scene.

   ```bash
   design/tools/.venv/bin/python design/tools/build.py     # --check to verify without writing
   ```

   Use that venv python: the system `python3` has no PyYAML/Jinja2.

## Godot gotchas (each of these has bitten before)

- **Generate uids with Godot, not by hand.** Hand-rolled uid strings get silently reassigned by
  the editor later, churning every reference. Generate real ones up front:
  `godot --headless -s <script>` where the script prints
  `ResourceUID.id_to_text(ResourceUID.create_id())`, and put them in the `.tscn`/`.tres` headers
  and cross-references.
- **Scripts get their uid from the importer.** After writing `.gd` files, run
  `godot --headless --import` **from `game/`** (it fails with "no main scene" from the repo
  root). Then read the generated `.gd.uid` sidecars and patch the
  `[ext_resource type="Script" …]` lines to include them.
- **Never spawn siblings during `_ready` with a direct `add_child`.** An effect that spawns
  projectiles in `_ready` runs while the tree is still adding the effect itself — direct
  `get_tree().root.add_child(p)` fails with "parent busy setting up children" and the spell
  silently does nothing. That is exactly what `CastContext.spawn_bullet(..., deferred: true)`
  is for; a burst tick in `_physics_process` can add synchronously.
- **Deferred adds rename nodes.** Deferred-added duplicates become `@CharacterBody2D@N` — find
  spawned nodes by `get_script()`, never by name.
- **The live editor re-saves scenes/resources from memory** and can clobber on-disk edits. After
  editing on disk, reload in the editor before saving anything.
- **Timers, not delta counters**, for lifetimes/staggers/legs — one-shot child `Timer`s die with
  the node. A projectile that can outlive its purpose needs a fallback lifetime.
- **A bullet with `speed_tiles = 0` or `range_tiles = 0` never flies**: it hides and expires
  where it spawned. That's a feature (mines), and a trap if unintended.
- **Zero-output headless timeout = a GDScript parse error**, not slowness — warnings are errors,
  including unused params and loop vars.

## Validate

There **is** a test suite; add to it rather than writing throwaways. Each prints
`ALL PASS` / `FAILED: <n>`:

```bash
godot --headless --path game res://tests/test_spell_damage.tscn   # damage reaches the bullets
godot --headless --path game res://tests/test_bullet_spell.tscn   # burst cadence, aim modes
godot --headless --path game res://tests/test_any_caster.tscn     # an enemy can cast it
godot --headless --path game res://tests/test_loadout.tscn        # slotting/cooldown plumbing
```

`test_spell_damage` uses distinct non-zero `skill`/`speed`/`defence` so a dropped scaling term
shows up, and `tests/support/stub_caster.gd` is there for driving an effect without a real
player. Pick tiers and stats so expected damage is exact and assert numbers, not "took some
damage". **Pace by wall-clock, not frames** — headless runs uncapped FPS, so `frames == 60` is
not one second; use `Time.get_ticks_msec()`. Assert cleanup too: after lifetimes elapse, zero
effect/projectile nodes remain.

A generic machinery extension (a `SpellCaster` or caster hook) must be tested through a **real
caster scene**, run as a *scene* (`godot --headless --path game res://tests/x.tscn`), not
`godot -s` — `-s` loads before the autoloads (`GlobalInventory`, `GlobalEvent`) register.

Then feel it: the combat lab (`godot --path game res://debug/combat_lab/combat_lab.tscn`) —
**Tab** for the panel, LMB on an item icon equips it, **F3** shows dealt/taken tallies, and
"Reload .tres" re-reads every slotted item from disk so you can tune numbers in a text editor
without restarting. Sprites, timing juice and palette can only be judged there.
