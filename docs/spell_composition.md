# Spell Composition

Spells are data plus one scene. A spell is a `SpellResource` `.tres` describing what it costs
and how it casts, and an **effect scene** that does everything the spell actually does. Most
new spells are one scene and one resource; the casting machinery never changes.

## The pieces

A spell is three things:

- **The resource** (`spell_resource.gd`) — an equippable item like hats and weapons, so it
  rides the same pickup → bag → slot pipeline. It holds what every spell shares: the effect
  scene, mana cost, cooldown, cast time, base damage, and skill scaling. A spell with stats of
  its own gets a small subclass (`FireballResource` adds projectile speed, range, AoE size,
  and the explosion animation).
- **The caster** (`spell_caster.gd`, a node on the player) — the generic flow, and only that:
  reads `spell1`–`spell4` input, checks cooldown and mana, roots the player for the cast time
  if there is one (the FSM `Cast` state), then instantiates the effect scene and hands it
  `setup(spell, caster)`. That call is the entire contract between the two.
- **The effect scene** — all behaviour. It positions itself from the caster, flies, explodes,
  heals, places an idol — whatever the spell means. The caster neither knows nor cares.

Tiers are just separate `.tres` files sharing one effect scene: Fireball I–III are three
resources with bigger numbers pointing at the same `fireball.tscn`.

## How damage lands

Effects deal damage the same way bullets do — through the target's `Hurtbox`. A `DamageZone`
(`components/damage_zone.gd`) is the area counterpart of a bullet body: an `Area2D` on the
player-bullets layer carrying `get_damage()`. Hurtboxes treat overlapping damage areas exactly
like entering bullet bodies, so AoE bursts, beams, and zones all reuse the existing contract
and friendly-fire layers.

## Cooldowns

Cooldowns belong to the **spell resource**, not the slot it was cast from — moving a spell to
another slot mid-cooldown can't dodge it. Different tiers are different spells with independent
cooldowns. The caster emits `GlobalEvent.spell_cooldown_started(spell, duration)` once per
cast; the UI slots share a spell → cooldown table and each draws the dark curtain over
whatever spell it currently holds, so the indicator follows the spell around the inventory.

## Anatomy of the fireball

Cast: 0.5s rooted wind-up, then a projectile flies toward the cursor. It explodes on the first
thing it hits — or at max range — and all damage comes from the explosion, so a direct hit and
a splash hit are worth the same. The explosion sprites are drawn at exactly the AoE size in
tiles, so the visual is the hitbox. Its tree:

```
Fireball                 (CharacterBody2D — fireball.gd, collides with terrain + enemies)
├─ Sprite2D              (projectile — the spell's icon)
├─ CollisionShape2D
└─ Explosion             (DamageZone on the player-bullets layer, off until impact)
   ├─ CollisionShape2D   (circle sized to the AoE at runtime)
   └─ AnimatedSprite2D   (explosion frames from the tier's resource)
```

## Adding a new spell

1. If the spell has stats the base resource lacks, subclass `SpellResource` next to its
   effect scene (one folder per spell under `characters/player/spells/`).
2. Build the effect scene: root script implements `setup(spell, caster)` and positions
   itself. Damage goes through a `DamageZone` (or a body with `get_damage()`).
3. One `.tres` per tier: icon from `spells.png`, stats from `docs/spells.md`, the shared
   effect scene. The item registry picks them up automatically.
4. Drop pickups in the world to make it obtainable.

The caster, inventory, UI, and cooldown indicator need no changes.
