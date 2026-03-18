# MVP Plan

A minimum viable product that proves the core loop: fight, Focus, gear up, clear a dungeon.
Scoped to be playable from start to finish — a player should be able to pick a build, clear
a dungeon, and beat a boss.

---

## What exists today

| System | Status | Details |
|--------|--------|---------|
| Player (Idle/Move/Focus) | Done | FSM works, Focus recovers mana, stats compute from gear |
| Inventory + drag/drop UI | Done | Weapon, hat, robe, 6 bag, 4 spell slots. Robe equip not wired. |
| Weapons (base system) | Done | OneBulletWeapon, RingBulletWeapon, BaseBullet. 2 test weapons. |
| Hats | Done | 3 test hats (Skill +50, Speed +50, Wisdom +100 mana). Placeholder values. |
| Robes | Partial | Slot exists, ItemType.ROBE defined. No items, no equip handling in player. |
| Spells | Partial | 4 UI slots exist. No spell system, no items, no activation. |
| Enemies | Partial | SmallDemon only (100 HP, 16 speed — wrong stats). Idle/Chase/Attack FSM. |
| Event bus | Done | GlobalEvent with 11 signals. All cross-system communication works. |
| World | Placeholder | Single open tilemap room with scattered test pickups and 1 enemy. |
| Loot drops | None | Enemies die and vanish. No drops. |
| Dungeons | None | No room transitions, no generation, no doors. |
| Death | None | Player health goes to 0, nothing happens. |
| Menus | None | No start screen, no pause, no game over. |

---

## MVP scope

One dungeon with 3 rooms and a boss. Three weapon families at tier 1. All four enemy types.
Two spells (one instant, one channeled) to prove both damage paths. Item drops from enemies.
Death sends you back to the overworld. Beat the boss, get a badge, see a win screen.

**Not in MVP:** Multiple dungeons, all 16 spell families, tiered items (tier 2-5), overworld
generation, save/load, audio, particle effects, animations beyond what exists.

---

## Phases

### Phase 0 — Fix foundations

Update the prototype to match the design before building new systems. Small changes that
unblock everything else.

**0.1 — Update player base stats**
- `base_skill`: 25 → 10
- `base_max_mana`: 50 → 30 (scene override, currently 50)
- These are the balanced values from the design docs.

**0.2 — Wire robe equip in player**
- `player._on_equipment_changed()` currently handles weapon and hat. Add the robe case:
  instantiate robe scene, apply stat modifiers via `_recompute_stats()`.
- Follows the exact same pattern as hat equip.

**0.3 — Add death handling**
- When `health <= 0` in `player._on_hurt()`: emit a `player_died` signal on GlobalEvent.
- For MVP: reload the current scene (restart). Later this becomes "return to overworld."

**0.4 — Remove test items from world.tscn**
- Delete the 16 scattered pickup instances and the 1 SmallDemon.
- The world scene becomes an empty room — content comes from generation later.

---

### Phase 1 — Real items (tier 1 only)

Replace test items with tier 1 versions of each family. One item per family, matching the
design doc numbers.

**1.1 — Weapons**

Extend existing weapon classes to create the three families. The OneBulletWeapon class already
handles Wand (single homing projectile). RingBulletWeapon can be adapted or a new class
created for Rune (shotgun pattern). Staff is a OneBulletWeapon with different stats.

| Item | Class | Base dmg | Scaling | Fire rate | Cost | +Stat |
|------|-------|----------|---------|-----------|------|-------|
| Wand | OneBulletWeapon | 10 | 1.0 | 1.0 | 1 | — |
| Staff | OneBulletWeapon | 15 | 0.5 | 0.5 | 2 | — |
| Rune | RingBulletWeapon | 6 | 1.0 | 2.0 | 2 | +5 HP |

Tasks:
- Create `wand.tscn` (OneBulletWeapon, homing bullet, stats from table).
- Create `staff.tscn` (OneBulletWeapon, straight bullet, stats from table).
- Create `rune.tscn` (RingBulletWeapon or new ShotgunWeapon, short range, stats from table).
- Create corresponding bullet scenes for each.
- Create pickup scenes for each.
- Wand bullet needs homing behavior toward nearest enemy to cursor — new bullet script or
  BaseBullet extension with `_physics_process` steering.

**1.2 — Hats**

Replace test hats with tier 1 designs. These are just BaseItem with different exported stat
values — no new scripts needed.

| Item | +Skill | +Speed | +HP | +Mana |
|------|--------|--------|-----|-------|
| Hat | 10 | 0 | 0 | 0 |
| Headband | 7 | 5 | 0 | 0 |
| Hood | 7 | 0 | 3 | 3 |

Tasks:
- Create `hat.tscn`, `headband.tscn`, `hood.tscn` as BaseItem scenes with exported values.
- Create pickup scenes for each.

**1.3 — Robes**

First robes in the game. Same as hats — BaseItem with stat values.

| Item | +HP | +Mana | +Skill | +Speed |
|------|-----|-------|--------|--------|
| Mantle | 10 | 0 | 0 | 0 |
| Robe | 0 | 10 | 0 | 0 |
| Vesture | 5 | 5 | 0 | 0 |

Tasks:
- Create `mantle.tscn`, `robe.tscn`, `vesture.tscn` as BaseItem scenes.
- Create pickup scenes for each.

---

### Phase 2 — Enemies

Implement the four enemy types from the design. SmallDemon's FSM (Idle/Chase/Attack) is the
template — all four enemies use the same state machine with different stats and behaviors.

**2.1 — Fix SmallDemon stats**
- HP: 100 → 20
- Speed: 16 → 60
- Update detection/chase/attack probe ranges.

**2.2 — Skitter**

The most important new enemy. Same FSM structure but with rush-in/rush-out behavior.

- HP: 15, Speed: 80, Damage: 8, Attack speed: 0.3s
- Behavior change: needs a retreat state. After attacking for a few seconds, transitions to a
  Retreat state (moves away from player), then back to Idle. New FSM states: Idle → Rush →
  Attack → Retreat → Idle.
- Likely needs its own script extending a base enemy class, or a modified FSM with 4 states.

**2.3 — Husk**

Tanky enemy with dual attack.

- HP: 50, Speed: 40, Damage: 15 (AoE) / 10 (single)
- Two weapons: a close-range AoE (ring bullet or area damage) and a long-range single shot.
  Switches based on distance to player. The Attack state checks distance and picks weapon.
- New scripts: HuskEnemy or modify SmallDemon to accept two weapons.

**2.4 — Ranger**

Ranged enemy. Same FSM as SmallDemon but slower, longer range.

- HP: 30, Speed: 20, Damage: 10, Attack range: 128
- Uses existing OneBulletWeapon with enemy bullet. Detection range 128.
- Mostly a stat variant of SmallDemon — may not need a new script.

**2.5 — Extract base enemy class**

Before or during enemy implementation, extract shared logic from SmallDemon into a `base_enemy.gd`:
- Exported stats: max_health, speed, skill
- Shared: health tracking, `_on_hurt()`, `die()`, player_position tracking via GlobalEvent
- Each enemy type extends this with its own FSM behavior.

---

### Phase 3 — Spells

Build the spell system and implement 2 spells to prove both damage paths.

**3.1 — Spell base class**

Create `base_spell.gd` extending BaseItem (so it has stat modifiers and fits the inventory).

```
Properties:
  @export var mana_cost: int        # flat cost (instant) or per-second (channeled)
  @export var cooldown: float       # seconds between casts
  @export var is_channeled: bool    # if true, drains mana_cost per second while active
  @export var cast_time: float      # seconds of root before effect (0 = instant)

Signals:
  spell_started
  spell_ended

Methods:
  cast(player_position, mouse_position, skill) -> void  # abstract
  can_cast(current_mana) -> bool
  start_channel() -> void
  stop_channel() -> void
```

**3.2 — Spell activation in player**

- Add input bindings for 4 spell slots (e.g., 1/2/3/4 keys).
- On key press: check equipped spell in that slot, check cooldown and mana, call `cast()`.
- For channeled spells: hold key to channel, release to stop. Drain mana per second while
  channeling. Cannot move or fire weapon while channeling (same as Focus).
- Connect spells to `GlobalEvent.equipment_changed` like weapons/hats.

**3.3 — Fireball (instant, skill-scaling)**

Proves the glass cannon damage path.

- Cost: 10, Cooldown: 8s, Damage: 15, Scaling: 2, AoE radius: 4
- Implementation: spawn a projectile (like BaseBullet but with AoE on impact). On reaching
  hurtbox or max range, create an Area2D explosion that damages all enemies in radius.
- New script: `fireball_projectile.gd` extending BaseBullet with `_on_lifetime_timeout()` or
  `reached_hurtbox()` triggering an explosion scene.

**3.4 — Laser (channeled, mana-scaling)**

Proves the mana build damage path.

- Cost: 5/sec, Cooldown: 6s, Damage/tick: 15, Scaling: 0.2
- Implementation: while channeled, a RayCast2D from the player toward the cursor. Every tick
  (e.g., 0.2s), check what the ray hits. If enemy, deal damage. Visual: a Line2D or similar
  from player to raycast end point.
- New script: `laser_spell.gd` extending BaseSpell. Uses a timer for damage ticks and a
  raycast for targeting.

---

### Phase 4 — Loot drops

Enemies drop items on death.

**4.1 — Drop table system**

Create a `loot_table.gd` autoload or utility class:
- Input: enemy power level (1-5, matching item tiers for MVP just 1).
- Output: an ItemData to spawn as a pickup, or null (no drop).
- Drop chance: based on enemy toughness. Skitter ~10%, SmallDemon ~15%, Ranger ~20%,
  Husk ~25%. Boss: 100%.
- Item selection: random type (weapon/hat/robe/spell), random family within type.
- For MVP all drops are tier 1 since only tier 1 items exist.

**4.2 — Spawn pickup on death**

Modify `base_enemy.die()`:
- Query loot table for a drop.
- If drop: instantiate a PickupItem at the enemy's death position with the rolled ItemData.
- The pickup system already handles the rest (player walks over it → goes to bag).

---

### Phase 5 — Dungeon

Build one dungeon to prove the room-based gameplay loop.

**5.1 — Room scene template**

Create a `base_room.tscn` — a self-contained tilemap scene with:
- Walls around the perimeter (collision).
- Door markers (Position2D nodes) on each edge: north, south, east, west.
- Enemy spawn points (Marker2D nodes) where enemies are pre-placed.
- A room script that:
  - Spawns pre-configured enemies at spawn points on `_ready()`.
  - Tracks when all enemies are dead → emits `room_cleared` signal.
  - Opens doors when cleared.

**5.2 — Room transitions**

When the player walks through a door:
- Disable current room (or queue_free).
- Load/instantiate the next room.
- Place the player at the corresponding entry door.
- This can use a simple scene-swap approach for MVP — no need for seamless transitions.

A `dungeon_manager.gd` script (or autoload) tracks:
- The sequence of rooms (for MVP: 3 pre-defined rooms + 1 boss room).
- Which room the player is in.
- Whether the dungeon is complete.

**5.3 — Room generation (basic)**

For MVP, "procedural generation" can be minimal:
- 3-5 hand-designed room layouts (tilemap templates with different geometry).
- Dungeon manager picks a sequence of rooms and assigns enemy compositions.
- Enemy composition per room: random selection from the 4 types, count scales with room number.

Full procedural tilemap generation is NOT in MVP scope. Hand-designed room templates with
randomized enemy placement is sufficient.

**5.4 — Boss room**

The final room of the dungeon contains a boss. For MVP, the boss can be a stat-scaled Husk
(higher HP, higher damage, maybe faster) rather than a unique enemy with new mechanics. The
boss just needs to feel like a harder fight.

- Boss drops a guaranteed item + awards a badge.
- On boss death: show a "Dungeon Complete" message, return player to overworld.

**5.5 — Overworld (minimal)**

For MVP the overworld is a single room (the existing world.tscn) with:
- A dungeon entrance (Area2D or interactable object) that loads the dungeon.
- A few roaming enemies (SmallDemons) for early gear.
- A spawn point where the player appears after dying or completing a dungeon.

Full overworld generation is NOT in MVP scope.

---

### Phase 6 — Game loop

Wire everything together into a playable session.

**6.1 — Death penalty**

On player death:
- If in dungeon: return to overworld, keep inventory. Dungeon resets (enemies respawn, new
  composition). You keep your gear but lose dungeon progress.
- If in overworld: respawn at overworld spawn point. No item loss.
- This is forgiving enough to not frustrate during testing, punishing enough that death in a
  dungeon costs time.

**6.2 — Badge tracking**

- Add a `badges: int` variable to a game state autoload (or GlobalInventory).
- Dungeon boss death increments badges.
- For MVP: 1 dungeon = 1 badge = game complete.

**6.3 — Win screen**

- When badge count reaches target (1 for MVP): show a simple "You Win" screen.
- Can be a CanvasLayer with a Label and a restart button.

**6.4 — Start screen**

- Minimal: a scene with the game title and a "Start" button that loads the overworld.
- Not essential for MVP but takes 10 minutes and makes it feel like a game.

---

## Phase summary

| Phase | What it delivers | Depends on |
|-------|-----------------|------------|
| 0 — Fix foundations | Correct stats, robe equip, death, clean world | Nothing |
| 1 — Real items | 3 weapons, 3 hats, 3 robes (tier 1) | Phase 0 |
| 2 — Enemies | 4 enemy types with correct stats/behavior | Phase 0 |
| 3 — Spells | Spell system + Fireball + Laser | Phase 0, Phase 1 (for equip) |
| 4 — Loot drops | Enemies drop items on death | Phase 1, Phase 2 |
| 5 — Dungeon | Room transitions, 1 dungeon, boss | Phase 2, Phase 4 |
| 6 — Game loop | Death, badges, win/start screen | Phase 5 |

Phases 1, 2, and 3 can be worked in parallel after Phase 0. Phase 4 needs items and enemies.
Phase 5 needs loot drops and enemies. Phase 6 wires it all together.

---

## What this proves

After MVP, a player can:
1. Start the game in the overworld.
2. Fight a few overworld enemies, get some tier 1 drops.
3. Equip a weapon (Wand, Staff, or Rune), choosing a build direction.
4. Equip a hat and robe, reinforcing the build.
5. Equip Fireball or Laser, choosing burst vs. sustained damage.
6. Enter the dungeon.
7. Fight through 3 rooms of pre-placed enemies, using Focus to recover mana between fights.
8. Face the boss, beat it, earn a badge.
9. See the win screen.

This proves: Focus tension, build identity (glass cannon vs. channeler vs. tank), the two
damage paths (instant vs. channeled spells), loot-driven progression, and dungeon structure.
Everything after MVP is more content: more tiers, more spells, more dungeons, more enemies.
