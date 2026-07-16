# Spells

Everything the player or an enemy fires is a spell. A spell is the only thing you equip, and your stats come from what you have equipped.
Player and enemies draw from the same system. Player spells are the standardised, readable
versions; enemies get more variety and harsher tuning, and bosses compose bespoke multi-stage
spells that they drop.

## Loadout

You equip spells across two pages. Each page binds one spell to **LMB**, **RMB**, and
**Space**, six slots in total. **SHIFT** cycles the active page.

### Casting

Two independent things on a spell's card decide how casting it commits you: its **Cast time**
and its **Hold** type. You can only be committed to one spell at a time, and a committing spell
can only be started while you're free to act.

**Cast time** is an optional wind-up. A spell with one roots you in place for a short beat
before it takes effect. You press once and wait it out; you do **not** hold the button. It is
orthogonal to the Hold type: a fire-and-forget spell can have a wind-up (it roots you, fires,
then frees you), and an instant one simply has none. (For channeled and charged spells the Cast
time is instead the hold's time cap.)

**Hold** is how the spell is delivered, one of three:

- **Fire-and-forget** (`no`): the press launches the effect and frees you at once (after any
  wind-up), then the effect runs to completion on its own. A DPS burst (a few rings, a run of
  shotguns, a stream, then cooldown, exactly like an enemy attack), a nuke in flight, or a summon
  walking off all keep going while you move and cast other things. These stack: layer as many
  as you have off cooldown.
- **Channeled** (`channeled`): you hold the button and the spell holds you. You are rooted in
  place, its effect running until you release, it hits cooldown, or a channel-time cap cuts it
  off. It blocks every other cast while it's live.
- **Charged** (`charged`): a hold like a channel, but you keep moving while it builds. You hold
  to charge power, then release to unleash a single payload; letting go, running out, or the cap
  fires it. The mobility is the trade for committing the button.

So the layering that matters: fire-and-forget spells pile up freely, but the moment a channel
or a charge claims the button, nothing else casts until you let go.

## Types

Four types, read off the catalogue below. Each one covers a distinct job in a loadout, and
six slots are not enough to cover every job at once, so a loadout always gives something up.

## Building blocks

A spell is a **fire pattern** plus optional **bullet modifiers** plus a **delivery cadence**
(one shot, a timed burst, a channel). Player and enemies share this whole vocabulary; the
difference is only in the numbers and how many are stacked.

**Fire patterns**, how a single shot is arranged in space:

| Pattern  | Shape                    |
| -------- | ------------------------ |
| Single   | one bullet on the aim    |
| Shotgun  | a cone of pellets        |
| Ring     | a full 360° burst        |
| Parallel | side-by-side bullets     |
| Flank    | one bullet off each side |

**Bullet modifiers**, behaviours layered onto the bullets a pattern fires:

| Modifier            | Effect                                            |
| ------------------- | ------------------------------------------------- |
| Homing              | steers toward a target                            |
| Ricochet            | bounces off walls                                 |
| Pierce              | passes through enemies instead of stopping        |
| Explode             | spawns an AoE on expiry                           |
| Burst               | sprays sub-bullets on expiry                      |
| Chain               | leaps to the next enemy                           |
| Mine                | arms on the floor, detonates on proximity         |
| Ring-with-drift     | each pulse rotates the aim into a spiral          |
| Sinewave            | weaving bullet                                    |
| Stream              | a rapid narrow hose                               |
| Orbit-then-launch   | bullets circle the caster, then fire outward      |
| Moving ring         | a ring that travels                               |
| Delayed ring        | pauses mid-flight, then resumes                   |
| Center-mass spread  | heavy middle pellet, chip on the sides            |
| Heat-seeking cluster | several homers converging from different angles  |
| Homing mine         | stops near the target, then explodes              |
| Wall of projectiles | a sweeping line                                   |
| Trapdoor volley     | danger zones that rise from the floor             |

---

# Catalogue

Each spell below has its own table: **Scaling** (the stat or stats its power grows with),
**Grants** (the stat bonuses it hands you while equipped, deliberately two and often mixed so
no loadout is pure min-max), **Range**, **Cooldown**,
**Per tier** (what a higher tier improves). Range and cooldown use very low /
low / med / high / very high; a self-cast spell shows range as *self*. "Source" is the enemy
archetype that uses and drops the spell. As a rule of thumb, short-range spells grant some
**defence**: close quarters is dangerous, and flat reduction rewards the many-small-hits
playstyle they push you into.

<!-- BEGIN GENERATED CATALOGUE -->
<!-- Generated from design/data/spells.yaml by design/tools/build.py — do not edit by hand. -->

## DPS

The primary-damage core: hold-to-fire spells that loose a burst then cool down, the player's mirror of an enemy attack.

### Pew

One burst of single bullets at the cursor, then cooldown, rather than a sustained hose. The burst is short enough to read as a single commitment: you aim and fire, then move on. It is the reliable all-rounder, the spell every other weapon is measured against.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med) |
| Range | med |
| Cooldown | low |
| Cast time | instant |
| Hold | no |

### Snipe

A few homing bullets toward the first enemy in the cursor direction. They all launch on the same frame rather than staggering, so the volley lands as one clustered hit instead of a trickle: a target either eats the whole thing or none of it. Accurate, but low DPS for the cooldown. Use it to pick off a specific enemy, not to clear a room.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med) |
| Range | high |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

### Blam

Two shotgun blasts back-to-back at the cursor, then cooldown: a double barrel, capped at two rather than a sustained run. Both barrels are the whole spell, so a miss on either half is a real cost. It is a close-range shredder: at point blank the two cones overlap almost entirely and the whole pellet count lands on one body.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), defence (med) |
| Range | low |
| Cooldown | med |
| Cast time | instant |
| Hold | no |

### Ring

A few fast rings of bullets pulsed out of the caster. Every pulse spawns at the caster's exact centre and expands outward, and each one is rotated off the last, so the gaps between bullets in one ring are covered by the next. There is no aim: the spell is pure area denial around your own body. Walk into a crowd and let the pulses do the sorting.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), health (med) |
| Range | med |
| Cooldown | med |
| Cast time | instant |
| Hold | no |
| Per tier | damage, bullet count, pulses |

### Halo

Orbs orbit the caster for a duration, damaging anything they sweep. Proximity does the work; walk enemies into the orbits. High base damage.

| | |
|---|---|
| Scaling | defence |
| Grants | speed (low), defence (high) |
| Range | very low |
| Cooldown | med |
| Cast time | instant |
| Hold | no |

### Chomp

A short lunge-bite: the caster steps in and shreds at melee, then cools down. Where Blam plants you and fires two cones, Chomp closes the gap itself, a mobile brawler's opener that trades Blam's spread for a committed step into the target. The lunge is the aim, so a whiffed dash wastes the whole burst.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), defence (med) |
| Range | very low |
| Cooldown | low |
| Cast time | instant |
| Hold | no |

## Nukes

Long cooldown, big single payload.

### Fireball

The starting spell: the first thing a new player has in a slot, and the baseline every other nuke is read against. A homing orb toward the enemy nearest the cursor; it explodes on impact, wall, or max range. All damage is the explosion, so a shot that expires in open air still deals it. The homing and the guaranteed detonation make it hard to waste, which is what a first spell should be.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (high) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |
| Per tier | damage, explosion radius |

### Zaap

An instant chain-lightning bolt that leaps between packed enemies; one lone target gets a single zap.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med) |
| Range | med |
| Cooldown | low |
| Cast time | instant |
| Hold | no |

### Zoing

A fast piercing bullet that ricochets off walls; each bounce is a fresh leg of travel and adds damage.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (high), speed (low) |
| Range | high |
| Cooldown | med |
| Cast time | instant |
| Hold | no |

### Kaboom

A scattered meteor rain across the whole screen; ground marks telegraph, then each meteor explodes for its own AoE.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (very high) |
| Range | very high |
| Cooldown | very high |
| Cast time | high |
| Hold | no |

### Piercing Lights

Projectiles spawn in a wide ring around the caster and converge into the aim direction, each piercing every hurtbox it crosses. Because they start spread and close on a single line, the damage stacks up along that line: an enemy standing in the aim direction is crossed by most of the fan at once, while anything off-axis is only clipped by the outermost lights. It rewards lining a target up rather than raw volume.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

### Bwoom

Charges in front of the caster while held, growing per tick; on release it fires a piercing line whose damage scales with charge.

| | |
|---|---|
| Scaling | defence |
| Grants | skill (med), health (med) |
| Range | high |
| Cooldown | high |
| Cast time | high |
| Hold | charged |

### Krak

A line of spikes erupts from the floor toward the aim after a short telegraph (Trapdoor volley). A delayed ground nuke: it ignores intervening cover, striking wherever the line lands rather than travelling to it. The telegraph is the cost: the payload only pays off against an enemy that can't clear the marked ground in time.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (high), defence (low) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

### Splay

Projectiles spawn around the caster one at a time, each at a random position, then fly off in a random direction, a scatter that unfolds over a short window rather than landing all at once. It sits between Piercing Lights' aimed fan and Ring's tidy pulses: unaimed and shapeless, just a cloud of chaos you stand inside. It rewards being in the middle of a crowd over lining anything up.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med), health (med) |
| Range | med |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

## Summon

Minions you cast into the fight — they run their own AI and keep working while you move and cast other things.

### Halp

A small squad of ranged minions firing single bullets. A walking gunline.

| | |
|---|---|
| Scaling | health |
| Grants | health (high), skill (low) |
| Range | med |
| Cooldown | high |
| Cast time | low |
| Hold | no |

### Bzzz

A fragile swarm of fast, short-range minions; chaff that dumps damage then dies.

| | |
|---|---|
| Scaling | speed |
| Grants | health (med), speed (low) |
| Range | low |
| Cooldown | med |
| Cast time | low |
| Hold | no |

### Jimmy

One heavy minion firing a ring around itself; a walking turret that denies an area.

| | |
|---|---|
| Scaling | defence |
| Grants | health (very high), defence (low) |
| Range | med |
| Cooldown | very high |
| Cast time | med |
| Hold | no |

### Beep Boop

One steady single-shot minion, long-lived. The dependable second firing line.

| | |
|---|---|
| Scaling | skill |
| Grants | health (med), skill (med) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

## Utility

Everything that isn't raw damage or a summon: mobility, buffs, crowd control, denial, and mitigation. Some are instant and layer on top of your damage; others are channeled or charged holds that trade a slot of offence to shape or survive the fight.

### Blink

Instant teleport to the cursor, range-clamped. Pure mobility.

| | |
|---|---|
| Scaling | - |
| Grants | speed (high), skill (low) |
| Range | med |
| Cooldown | med |
| Cast time | instant |
| Hold | no |

### Nyoom

Converts skill into speed for a duration; casting another spell breaks it. For fast travel.

| | |
|---|---|
| Scaling | skill |
| Grants | speed (med), skill (med) |
| Range | self |
| Cooldown | high |
| Cast time | med |
| Hold | no |

### Shing

Your next spell casts twice.

| | |
|---|---|
| Scaling | - |
| Grants | health (med) |
| Range | self |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

### Clang

For a short window, all your bullets are piercing.

| | |
|---|---|
| Scaling | - |
| Grants | skill (med) |
| Range | self |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

### ChargeDash

Charges in a direction for a short duration at high speed. Sends bullets at 90 degrees.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), defence (med) |
| Range | med |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

### Vroop

Shoots a fireball-like bullet. When it hits an enemy, a wall, or the end of the range, creates a vortex that drags enemies to its center. Sets up an AoE follow-up on the whole clump.

| | |
|---|---|
| Scaling | - |
| Grants | defence (high), skill (low) |
| Range | med |
| Cooldown | high |
| Cast time | high |
| Hold | no |

### Thwomp

An instant radial knockback pulse; more damage the closer the enemy, chip at the edge. The "get off me" button.

| | |
|---|---|
| Scaling | defence |
| Grants | defence (high), health (med) |
| Range | low |
| Cooldown | med |
| Cast time | very low |
| Hold | no |

### Brrr

An ice patch that grows in a line towards the direction of the cursor; on release the whole area bursts and throws shards.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), health (med) |
| Range | high |
| Cooldown | med |
| Cast time | instant |
| Hold | charged |

### Fwoosh

A short-lived wall of fire along a line toward the cursor. Enemies pay HP to cross it, and it blocks their bullets (not yours).

| | |
|---|---|
| Scaling | skill |
| Grants | skill (low), health (med) |
| Range | med |
| Cooldown | med |
| Cast time | low |
| Hold | no |

### Ploop

Drops a floating mine that arms after a delay, then erupts into piercing darts on proximity. Several can be out at once. Prep a room or cover a retreat.

| | |
|---|---|
| Scaling | speed |
| Grants | defence (med), speed (med) |
| Range | low |
| Cooldown | low |
| Cast time | instant |
| Hold | no |

### Oop

Drops a floating mine that arms after a delay, then erupts into a fireball-like explosion on proximity.

| | |
|---|---|
| Scaling | speed |
| Grants | skill (med), speed (med) |
| Range | low |
| Cooldown | low |
| Cast time | very low |
| Hold | no |

### Nope

On a long cooldown, raises a bubble that absorbs incoming damage; a white ring flashes on each absorbed hit.

| | |
|---|---|
| Scaling | defence |
| Grants | defence (high), health (med) |
| Range | self |
| Cooldown | low |
| Cast time | instant |
| Hold | channeled |

### Slurp

An aura that drains every enemy in range each tick and heals the caster for a fraction. Steady damage and self-healing on one button.

| | |
|---|---|
| Scaling | health |
| Grants | health (med), defence (med) |
| Range | low |
| Cooldown | med |
| Cast time | instant |
| Hold | channeled |

### Heal

Instantly restores health. The safety net every survivability loadout considers.

| | |
|---|---|
| Scaling | defence |
| Grants | health (high), defence (low) |
| Range | self |
| Cooldown | high |
| Cast time | med |
| Hold | no |

<!-- END GENERATED CATALOGUE -->
