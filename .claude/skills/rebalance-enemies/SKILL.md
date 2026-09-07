---
name: rebalance-enemies
description: Retune existing enemy numbers — HP, cast damage, movement speed, drop chances/items, or spawn frequency — without rebuilding anything. Use when the user asks to buff/nerf an enemy or a biome's roster, adjust drop rates or drop-table contents, make enemies "more/less trivial," or fix loot that's "too scarce"/"never drops." Not for adding a new enemy (see add-enemy) or new room/spawn types (see add-room).
---

# Rebalancing enemies

Pure numeric edits to existing `.tres`/`.tscn` resources. No new scenes, no scripts, no new
nodes. The whole job is: find the right field in the right file, change the number, rebuild the
docs. Do it with minimal reads — these files are small and the fields are self-describing.

## Where each number lives

For enemy `<id>` under `game/characters/enemies/<id>/`:

| What | File | Field |
|---|---|---|
| HP | `<id>_data.tres` (`CreatureResource`) | `max_health` |
| Cast damage | `<id>_<beat>.tres` (`BulletSpellResource`, **one per attack beat**) | `base_damage` on the embedded `ScalingProfile` sub-resource (`damage = SubResource(...)`) |
| Cast cadence / burst | the same `<id>_<beat>.tres` | `cooldown`, `cast_time`, `max_shots`, `shot_interval`, `rotation_per_shot` |
| Projectile reach & pace | the same file's inline `BulletResource` | `range_tiles`, `speed_tiles` (**tiles**, not px) |
| Movement speed | `<id>.tscn` — on the behaviour node, not the resource | `speed` on the Approach/Wander/Flee beat (a creature can move at different speeds per state, which is why it isn't on `CreatureResource`) |
| Drop table | `<id>_data.tres` | `drops = Array[...]([...])` — `LootDrop` sub-resources, each `{item: ExtResource, chance: float}` |
| Spawn frequency | the **room type's** `.tres` (`game/world_content/biomes/<biome>/rooms/<room>.tres`, `RoomTypeDef`), in its `enemies` array: a `SpawnTableEntry`'s `weight` (relative pick odds in that room's pool) and `group_min`/`group_max` | not on the enemy itself |
| How often that *room* appears | the same `RoomTypeDef` | `weight`, `min_per_biome`, `max_per_biome`, `difficulty` |

**Damage is on the cast, never on the bullet.** `BulletResource` deliberately carries no damage
so the same projectile shape hits for one number in the player's hands and another in an
enemy's. Enemy casts author `base_damage` and leave every `*_scaling` at 0.

**Multi-attack enemies** (golem, gnarlking, thornmess) have several `<id>_<beat>.tres` — grep
the enemy's folder for `base_damage` to catch all of them; don't assume one cast per enemy.

**Loot rolls are independent, not weighted.** `LootDrop.roll()` is `randf() < chance` per entry
(`game/items/loot_drop.gd`) — an enemy with 5 drops at 0.1 each yields ~40% "got something," not
one item picked from five. (`LootTable.pick()` exists and *is* a weighted pick-exactly-one, but
enemy `drops` don't use it.) When an enemy "never drops anything," the fix is either raising its
per-item chances or noting it's rarely killed, not switching to a weighted pick.

**Frequency confounds drop rate.** An enemy's *felt* drop rate is `chance × how often you kill
it`, and kill rate is set by two things that both live outside the enemy: which rooms list it in
their `enemies` pool (and at what `weight`/`group_max`), and how often those rooms are placed
(the `RoomTypeDef`'s own `weight`/`min_per_biome`/`difficulty`). Before concluding an item is
"too rare," check whether the enemy carrying it is just rarely spawned. A report of "X never
drops" is a spawn-frequency question as often as a chance question. Don't change spawn weights
unless the user asks specifically — a rate complaint is usually about `chance`.

## Token-cheap procedure

1. **One grep across the whole enemy** (not per-file `cat`+`Read`) to see every current number
   at once:
   ```
   grep -rn "max_health\|base_damage\|chance = \|^speed = " game/characters/enemies/<id>/
   ```
   This is enough context to know exactly what `old_string` to pass to `Edit` — you don't need
   to open every file in full.
2. **Read each file you're about to `Edit`** — the tool requires it, but a full `Read` is
   overkill for a resource that's mostly boilerplate `ext_resource` headers. A plain `Read`
   with no `offset`/`limit` on these files is fine; don't `cat` the same file first and then
   `Read` it too — that's a wasted duplicate pass. Read once, then `Edit`.
3. **Edit with `replace_all: true`** when a file has several identical `chance = 0.05` lines you
   want moved to the same new value together — one call beats N single-occurrence calls. Fall
   back to unique `old_string` snippets (include the neighbouring `item = ExtResource(...)` line)
   when different sub-resources in the same file need different new values.
4. **Compute rounded values up front**, don't iterate: for "increase HP by at least X%," use
   `ceil(old * (1 + X/100))` so every enemy clears the floor in one pass instead of
   under/over-shooting and re-editing.
5. **Rebuild the design docs.** They are generated, not hand-edited — every number in
   `design/docs/enemies.md` is read straight out of the `.tres` you just changed by
   `design/tools/extract.py`, so there is no prose table to sync by hand. Just run:
   ```
   design/tools/.venv/bin/python design/tools/build.py
   ```
   (Use that venv python — the system `python3` has no PyYAML/Jinja2.) Only touch
   `design/data/enemies.yaml` if the *words* changed — a rebalance big enough that the enemy's
   description now lies. The yaml holds no numbers by design.
6. **No `gen_version` bump.** That dial (`world_content/gen_config.tres`) means "the generator
   *algorithm* changed" — bump it only for code the hash can't see. Every piece of authored
   world data, spawn tables included, is already folded into `CONFIG_HASH` by
   `GenConfig.compute_hash()`, so a data edit re-rolls saved seeds on its own. HP, cast damage
   and loot chances aren't hashed at all and don't touch a saved seed's geography; editing a
   `SpawnTableEntry` or a `RoomTypeDef` quota does change the world, automatically, with no bump
   needed.

## Drop assignment (when redistributing a roster's loot)

**Every item in the game is a spell** — there are no hats, robes or weapons; `ItemType` is
`BAG`/`SPELL`/`OTHER` and all enemy drops are spell tier `.tres` under
`characters/player/spells/<id>/`. So a drop table is a statement about which *playstyle* an
enemy hands you.

Pick by playstyle so gear reads as belonging to the enemy:

- **Sustain/mitigation** (heal, nope) → tanky or stationary enemies: what you needed to survive
  the thing that just killed you.
- **Cheap, spammable** (zaap, pew) → fast/erratic/small enemies.
- **Expensive burst** (fireball, thwomp) → aggressive chargers and screamers.
- **Summons** (halp, bzzz, jimmy) → enemies that themselves arrive in numbers.
- **Mobility** (blink, charge_dash) → the enemies that outmanoeuvre you.

Tiers are the other axis: a tier-1 file (`pew1.tres`) belongs on a common, tier-2 on a rare or a
tougher biome's commons, tier-3 on a boss. The `*3_insect.tres` / `*3_fungal.tres` **side tiers**
carry a `weakness` and should drop from the biome whose roster they counter, not scattered.

When redistributing a whole biome's pool, list every candidate tier once and check it against
your assignment before writing files — it's easy to double up one spell and starve another.
Concentrating one spell on one enemy at a higher chance reads better, and audits more easily for
full coverage, than spreading three copies thin at low chance.

## Don't

- Don't touch spawn `weight`/`group_min`/`group_max`, or a `RoomTypeDef`'s placement quota,
  unless asked — that's a population-density decision, separate from loot balance, and it
  re-rolls every saved world through `CONFIG_HASH`.
- Don't rewrite a `_data.tres` or a cast `.tres` from scratch with `Write` when an `Edit` on the
  one changed line will do — these files carry `uid`s and `ExtResource` ids that are easy to
  typo when retyped wholesale.
- Don't re-derive the item pool from scratch each time you're asked to tweak one chance — grep
  the enemy's drops once, edit the specific number, done.
- Don't hand-edit `design/docs/enemies.md`. The region between the `GENERATED CATALOGUE` markers
  is machine-owned and will be overwritten on the next build.

## Validate

`design/tools/.venv/bin/python design/tools/build.py --check` proves the docs and the game still
agree. For anything you want to *feel*, the combat lab
(`godot --path game res://debug/combat_lab/combat_lab.tscn`) has a "Reload .tres" button that
re-reads every slotted item from disk — tune numbers in the editor and click it, no restart.
