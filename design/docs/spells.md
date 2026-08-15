# Spells

Everything the player or an enemy fires is a spell. A spell is the only thing you equip, and your stats come from what you have equipped.
Player and enemies draw from the same system. Player spells are the standardised, readable
versions; enemies get more variety and harsher tuning, and bosses compose bespoke multi-stage
spells that they drop.

## Loadout

You equip spells across two pages. Each page binds one spell to **LMB**, **RMB** and **MMB** —
or, on a controller, to **L1**, **L2** and **R1**, left to right — six slots in total. **Space**,
the mouse wheel or the pad's **R2** cycles the active page.

The game plays fully on either device and swaps between them the moment you touch one. On a
controller the left stick moves, the right stick aims (it holds your last direction when you let
go, and follows your run if you never touch it), and **Start** opens slot navigation: the dpad
moves a highlight across your spells, bag and the strip buttons, **A** picks an item up and
places it, **B** puts it back or backs out, **X** drops it on the floor.

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

Every spell here is **shipped**: it has tier `.tres` files in the game, and the numbers in
its table are read straight out of them, never retyped. Each tier row shows what that tier
actually costs and delivers — cooldown, cast time, the burst it fires, its damage formula, the
stats it grants while equipped. Unbuilt proposals live in [ideas](#ideas) at the bottom, where
they keep the old fuzzy scales (very low / low / med / high / very high) because there is no
resource to read a number off yet.

As a rule of thumb, short-range spells grant some **defence**: close quarters is dangerous, and
flat reduction rewards the many-small-hits playstyle they push you into.

For the interactive views: [spells.html](spells.html) filters the catalogue,
[spells_balance.html](spells_balance.html) is the numbers sheet with live DPS.

<!-- BEGIN GENERATED CATALOGUE -->
<!-- Generated by design/tools/build.py from design/data/ + the game's .tres — do not edit by hand. -->

## DPS

The primary-damage core: hold-to-fire spells that loose a burst then cool down, the player's mirror of an enemy attack.

### Pew

One burst of single bullets at the cursor, then cooldown, rather than a sustained hose. The burst is short enough to read as a single commitment: you aim and fire, then move on. It is the reliable all-rounder, the spell every other weapon is measured against.

**Scaling:** speed

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 1s | instant | Single, 6 @ 0.25s | 3 + 0.5×speed = **43** | 8 | speed +4 |
| T2 | 1s | instant | Single, 8 @ 0.2s | 5 + 0.6×speed = **53** | 8 | speed +6 |
| T3 | 1s | instant | Single, 10 @ 0.18s | 7 + 0.75×speed = **67** | 9 | speed +8 |

### Snipe

A few homing bullets toward the first enemy in the cursor direction. They all launch on the same frame rather than staggering, so the volley lands as one clustered hit instead of a trickle: a target either eats the whole thing or none of it. Accurate, but low DPS for the cooldown. Use it to pick off a specific enemy, not to clear a room.

**Scaling:** skill

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 4s | instant | Single, 3 @ 0.1s | 4 + 0.2×skill = **9** | 18 | skill +4 |
| T2 | 4s | instant | Single, 5 @ 0.1s | 5 + 0.25×skill = **11** | 18 | skill +6 |

**Also:** homing 90° cone.

### Blam

Two shotgun blasts back-to-back at the cursor, then cooldown: a double barrel, capped at two rather than a sustained run. Both barrels are the whole spell, so a miss on either half is a real cost. It is a close-range shredder: at point blank the two cones overlap almost entirely and the whole pellet count lands on one body.

**Scaling:** skill

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 1.5s | instant | Shotgun x3, 2 @ 0.4s | 4 + 0.2×skill = **9** | 4 | skill +4, defence +3 |
| T2 | 1.5s | instant | Shotgun x3, 2 @ 0.4s | 6 + 0.25×skill = **12** | 4 | skill +7, defence +5 |
| T3 | 1.5s | instant | Shotgun x5, 3 @ 0.3s | 8 + 0.3×skill = **16** | 4 | skill +10, defence +7 |

### Ring

A few fast rings of bullets pulsed out of the caster. Every pulse spawns at the caster's exact centre and expands outward, and each one is rotated off the last, so the gaps between bullets in one ring are covered by the next. There is no aim: the spell is pure area denial around your own body. Walk into a crowd and let the pulses do the sorting.

**Scaling:** skill · **Per tier:** damage, bullet count, pulses

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 2.5s | instant | Ring x8, 3 @ 0.6s | 5 + 0.2×skill = **10** | 5 | skill +3, max_health +15 |
| T2 | 2.5s | instant | Ring x10, 4 @ 0.6s | 5 + 0.25×skill = **11** | 5 | skill +5, max_health +25 |
| T3 | 2.5s | instant | Ring x12, 5 @ 0.6s | 8 + 0.3×skill = **16** | 6 | skill +8, max_health +30 |

## Nukes

Long cooldown, big single payload.

### Fireball

The starting spell: the first thing a new player has in a slot, and the baseline every other nuke is read against. A homing orb toward the enemy nearest the cursor; it explodes on impact, wall, or max range. All damage is the explosion, so a shot that expires in open air still deals it. The homing and the guaranteed detonation make it hard to waste, which is what a first spell should be.

**Scaling:** skill · **Hold:** charged · **Per tier:** damage, explosion radius

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 4s | 0.5s | Single | 10 + 1.25×skill = **41** | 12 | skill +6 |
| T2 | 4s | 0.5s | Single | 15 + 2×skill = **65** | 12 | skill +10 |

**Also:** blast 5 tiles (splash only).

### Zaap

An instant chain-lightning bolt that leaps between packed enemies; one lone target gets a single zap.

**Scaling:** speed

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 2s | instant | Single | 5 + 0.8×speed = **69** | 12 | speed +6 |
| T2 | 2s | instant | Single | 8 + 1.1×speed = **96** | 12 | speed +9 |

**Also:** chains 16x, chains 8x.

### Zoing

A fast piercing bullet that ricochets off walls; each bounce is a fresh leg of travel and adds damage.

**Scaling:** skill

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 3.5s | instant | Single, 5 @ 0.2s | 5 + 0.25×skill = **11** | 30 | skill +6, speed +2 |

**Also:** BounceBehaviour, pierces.

### Bwoom

Charges in front of the caster while held, growing per tick; on release it fires a piercing line whose damage scales with charge.

**Scaling:** defence · **Hold:** channeled

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 4s | 2s | — | 6 + 0.5×defence = **6** | — | defence +6 |

## Summon

Minions you cast into the fight — they run their own AI and keep working while you move and cast other things.

### Halp

A small squad of ranged minions firing single bullets. A walking gunline.

**Scaling:** defence · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 10s | 0.5s | — | — | — | skill +2, max_health +35 |
| T3 | 9s | 0.5s | — | — | — | skill +4, max_health +50 |

**Also:** 4 minions, 34 hp, 8s, 6 minions, 55 hp, 10s.

### Bzzz

A fragile swarm of fast, short-range minions; chaff that dumps damage then dies.

**Scaling:** flat · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 8s | 0.3s | — | — | — | speed +3, max_health +15 |

**Also:** 4 minions, 15 hp, 6s.

### Jimmy

One heavy minion firing a ring around itself; a walking turret that denies an area.

**Scaling:** defence · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 14s | 1s | — | — | — | max_health +30, defence +1 |

**Also:** 1 minions, 200 hp, 15s.

## Utility

Everything that isn't raw damage or a summon: mobility, buffs, crowd control, denial, and mitigation. Some are instant and layer on top of your damage; others are channeled or charged holds that trade a slot of offence to shape or survive the fight.

### ChargeDash

Charges in a direction for a short duration at high speed. Sends bullets at 90 degrees.

**Scaling:** skill, speed · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 6s | 0.3s | Flank x2, 9 @ 0.1s | 10 + 0.6×skill + 1.2×speed = **121** | 8 | skill +6, speed +2 |

**Also:** dash 80 px/s for 1s.

### Thwomp

An instant radial knockback pulse; more damage the closer the enemy, chip at the edge. The "get off me" button.

**Scaling:** defence · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T3 | 4s | 0.2s | — | 15 + 1.5×defence = **15** | — | max_health +25, defence +7 |

### Blink

An instant hop along your aim: you vanish and reappear a fixed distance away, leaving a ghost behind. Aim is a direction rather than a click, so the hop is a length you learn instead of a spot you pick, and it refuses a landing with a wall in the way rather than posting you through one. Pure mobility — no damage, no wind-up, just the gap between where a boss's charge is going and where you are.

**Scaling:** flat · **Per tier:** a longer hop on a shorter cooldown.

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 2s | instant | — | — | — | skill +2, speed +8 |

### Oop

Drops a mine a tile ahead of your aim — in the doorway, not under your feet. It arms on a short delay and then goes up in a fireball-sized blast the moment an enemy touches it. The mine is a dumb object — it has no health, nothing can shoot it, and it never moves or chases; it is a hazard the room has to walk around. Several can be out at once, so it plays as prep: seed the doorway you are about to retreat through, or the lane the pack has to cross. The cinderstone is the same detonation pointed the other way.

**Scaling:** skill · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 2s | 0.2s | Single | 12 + 1×skill = **37** | 0 | skill +5 |

**Also:** blast 4 tiles (splash only).

### Ploop

The mine that answers a crowd instead of a target: same drop, same arming, but on contact it erupts into a full ring of piercing darts that run through everything in line. Lower per-hit than Oop's blast, far better across a corridor or into a pack, and the darts keep going after the first body.

**Scaling:** speed · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T2 | 2s | 0.2s | Ring x8, 3 @ 0.15s | 7 + 0.75×speed = **67** | 6 | speed +6 |

**Also:** pierces.

### Nope

On a long cooldown, raises a bubble that absorbs incoming damage and pays a slice of it back as health; a white ring flashes on each absorbed hit.

**Scaling:** flat · **Hold:** channeled

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 2s | 1.5s | — | — | — | max_health +20, defence +5 |

### Heal

Instantly restores health. The safety net every survivability loadout considers.

**Scaling:** skill, defence · **Hold:** charged

| Tier | Cooldown | Cast | Burst | Amount | Range | Grants |
|---|---|---|---|---|---|---|
| T1 | 20s | 0.8s | — | 50 + 0.5×skill + 2×defence = **62** | — | max_health +20 |
| T2 | 17s | 0.8s | — | 88 + 0.5×skill + 3×defence = **100** | — | max_health +35, defence +2 |

<!-- END GENERATED CATALOGUE -->

---

# ideas

Spells the design wants but the game has not built. They carry the fuzzy scales rather than
numbers — nothing ships them, so there is nothing to measure. Move one into `spells.yaml` in
the same change that builds it.

### DPS

#### Halo

Orbs orbit the caster for a duration, damaging anything they sweep. Proximity does the work; walk enemies into the orbits. High base damage.

| | |
|---|---|
| Scaling | defence |
| Grants | speed (low), defence (high) |
| Range | very low |
| Cooldown | med |
| Cast time | instant |
| Hold | no |

#### Chomp

A short lunge-bite: the caster steps in and shreds at melee, then cools down. Where Blam plants you and fires two cones, Chomp closes the gap itself, a mobile brawler's opener that trades Blam's spread for a committed step into the target. The lunge is the aim, so a whiffed dash wastes the whole burst.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), defence (med) |
| Range | very low |
| Cooldown | low |
| Cast time | instant |
| Hold | no |

### Nukes

#### Kaboom

A scattered meteor rain across the whole screen; ground marks telegraph, then each meteor explodes for its own AoE.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (very high) |
| Range | very high |
| Cooldown | very high |
| Cast time | high |
| Hold | no |

#### Piercing Lights

Projectiles spawn in a wide ring around the caster and converge into the aim direction, each piercing every hurtbox it crosses. Because they start spread and close on a single line, the damage stacks up along that line: an enemy standing in the aim direction is crossed by most of the fan at once, while anything off-axis is only clipped by the outermost lights. It rewards lining a target up rather than raw volume.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

#### Krak

A line of spikes erupts from the floor toward the aim after a short telegraph (Trapdoor volley). A delayed ground nuke: it ignores intervening cover, striking wherever the line lands rather than travelling to it. The telegraph is the cost: the payload only pays off against an enemy that can't clear the marked ground in time.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (high), defence (low) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

#### Splay

Projectiles spawn around the caster one at a time, each at a random position, then fly off in a random direction, a scatter that unfolds over a short window rather than landing all at once. It sits between Piercing Lights' aimed fan and Ring's tidy pulses: unaimed and shapeless, just a cloud of chaos you stand inside. It rewards being in the middle of a crowd over lining anything up.

| | |
|---|---|
| Scaling | speed |
| Grants | speed (med), health (med) |
| Range | med |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

### Summon

#### Beep Boop

One steady single-shot minion, long-lived. The dependable second firing line.

| | |
|---|---|
| Scaling | skill |
| Grants | health (med), skill (med) |
| Range | high |
| Cooldown | med |
| Cast time | low |
| Hold | no |

### Utility

#### Nyoom

Converts skill into speed for a duration; casting another spell breaks it. For fast travel.

| | |
|---|---|
| Scaling | skill |
| Grants | speed (med), skill (med) |
| Range | self |
| Cooldown | high |
| Cast time | med |
| Hold | no |

#### Shing

Your next spell casts twice.

| | |
|---|---|
| Scaling | - |
| Grants | health (med) |
| Range | self |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

#### Clang

For a short window, all your bullets are piercing.

| | |
|---|---|
| Scaling | - |
| Grants | skill (med) |
| Range | self |
| Cooldown | high |
| Cast time | instant |
| Hold | no |

#### Vroop

Shoots a fireball-like bullet. When it hits an enemy, a wall, or the end of the range, creates a vortex that drags enemies to its center. Sets up an AoE follow-up on the whole clump.

| | |
|---|---|
| Scaling | - |
| Grants | defence (high), skill (low) |
| Range | med |
| Cooldown | high |
| Cast time | high |
| Hold | no |

#### Brrr

An ice patch that grows in a line towards the direction of the cursor; on release the whole area bursts and throws shards.

| | |
|---|---|
| Scaling | skill |
| Grants | skill (med), health (med) |
| Range | high |
| Cooldown | med |
| Cast time | instant |
| Hold | charged |

#### Fwoosh

A short-lived wall of fire along a line toward the cursor. Enemies pay HP to cross it, and it blocks their bullets (not yours).

| | |
|---|---|
| Scaling | skill |
| Grants | skill (low), health (med) |
| Range | med |
| Cooldown | med |
| Cast time | low |
| Hold | no |

#### Slurp

An aura that drains every enemy in range each tick and heals the caster for a fraction. Steady damage and self-healing on one button.

| | |
|---|---|
| Scaling | health |
| Grants | health (med), defence (med) |
| Range | low |
| Cooldown | med |
| Cast time | instant |
| Hold | channeled |
