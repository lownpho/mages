# Spells

Spells are active abilities with mana costs and cooldowns, equipped in the 4 spell slots.
Some are instant, some have cast times (rooting the player), some are channeled (draining
mana per second while active).

## Two damage paths

Spells fall into two scaling categories that support different builds:

- **Instant spells** (Fireball, Chain Lightning, Meteor, Piercing Lights) have **high skill
  scaling**. They reward the glass cannon build — more skill = harder hits.
- **Channeled spells** (Laser, Charge Blast, Vortex, Drain, Barrier) have **high base damage
  and low skill scaling**. They reward the mana build — more mana = longer channel = more
  total damage. A mana build doesn't need skill because these spells hit hard on base values
  alone.

This makes mana a genuine offensive stat for channeled builds. A glass cannon with 160 skill
fires a Fireball for massive burst. A mana build with 200 mana channels a Laser for 20
seconds of sustained damage. Different paths to comparable total output.

Utility spells (Blink, Haste, Heal) are build-agnostic with low or no scaling.

---

## Direct Damage

### Fireball

Single exploding projectile with AoE.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage | Scaling | Range | AoE |
|------|---------|------|----------|-----------|--------|---------|-------|-----|
| Fireball | Fireball | 10 | 8s | instant | 15 | 2 | 10 | 4 |
| Greater Fireball | Bigger Fireball | 20 | 8s | instant | 30 | 3 | 14 | 4 |
| Even Greater Fireball | Even Bigger Fireball | 50 | 8s | instant | 70 | 4 | 18 | 5 |

### Piercing Lights

Summon homing projectiles that pierce through enemies until hitting a wall or leaving the
screen. Target the nearest enemy.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage | Scaling | Projectiles |
|------|---------|------|----------|-----------|--------|---------|-------------|
| Piercing Lights | Pew Pew | 15 | 10s | instant | 10 | 0.3 | 10 |
| Piercing Lights 2 | Pew Pew Pew | 30 | 10s | instant | 30 | 0.4 | 13 |
| Piercing Lights 3 | Peeew Peeew | 50 | 10s | instant | 50 | 0.5 | 18 |

### Meteor

Random meteor falls at target location after a delay.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage | Scaling | Delay |
|------|---------|------|----------|-----------|--------|---------|-------|
| Meteor | Meteor | 10 | 15s | 0.5s | 30 | 3 | 1.5s |
| Meteor 2 | Bigger Meteor | 20 | 15s | 0.5s | 60 | 4 | 1.5s |
| Meteor 3 | Even Bigger Meteor | 50 | 15s | 0.5s | 90 | 5 | 1.5s |

### Chain Lightning

Projectile that bounces between enemies.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage | Scaling | Bounces |
|------|---------|------|----------|-----------|--------|---------|---------|
| Chain Lightning | Zap | 5 | 4s | instant | 10 | 1 | 3 |
| Chain Lightning 2 | More Zap | 10 | 4s | instant | 20 | 1.5 | 4 |
| Chain Lightning 3 | Zaaaap | 18 | 4s | instant | 30 | 2 | 5 |

### Charge Blast

Channeled piercing beam that charges up in ticks. Dies on walls. Higher tiers charge more
ticks for bigger blasts. Low skill scaling — rewards mana pool (more fuel to charge longer).

| Tier | Flavour | Cost | Cooldown | Charge time | Damage/tick | Scaling | Max ticks |
|------|---------|------|----------|-------------|-------------|---------|-----------|
| Charge Blast | Blast | 5/sec | 3s | 0.5s/tick | 12 | 0.2 | 3 |
| Charge Blast 2 | Bigger Blast | 8/sec | 3s | 0.5s/tick | 22 | 0.3 | 4 |
| Charge Blast 3 | Biggest Blast | 12/sec | 3s | 0.5s/tick | 35 | 0.5 | 5 |

### Laser

Continuous piercing beam that follows the cursor. Channeled. High base damage, low skill
scaling — the signature mana build spell. Total damage = base DPS × channel duration, and
channel duration = mana pool ÷ cost/sec.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage/tick | Scaling |
|------|---------|------|----------|-----------|-------------|---------|
| Laser | Whoop | 5/sec | 6s | instant | 15 | 0.2 |
| Laser 2 | Shoop | 10/sec | 6s | instant | 25 | 0.3 |
| Laser 3 | Shoop Da Whoop | 20/sec | 6s | instant | 40 | 0.5 |

### Eruption

Channeled. Target a point on the ground. The longer you channel, the bigger and more powerful
the explosion when you release. Variable risk/reward — stand still longer for a bigger payoff.
High base damage, low scaling.

| Tier | Flavour | Cost | Cooldown | Cast time | 1s damage | 2s damage | 3s+ damage | Scaling | 1s radius | 2s radius | 3s+ radius |
|------|---------|------|----------|-----------|-----------|-----------|------------|---------|-----------|-----------|------------|
| Eruption | Rumble | 6/sec | 10s | instant | 18 | 40 | 70 | 0.2 | 2 | 3 | 5 |
| Eruption 2 | Tremor | 10/sec | 10s | instant | 30 | 60 | 100 | 0.3 | 2 | 4 | 6 |
| Eruption 3 | Cataclysm | 15/sec | 10s | instant | 45 | 85 | 140 | 0.4 | 3 | 5 | 7 |

---

## Channeled Control

### Vortex

Channeled. Pull enemies toward a target point while dealing low damage. The crowd control
channel — cluster enemies for your Staff shots, AoE spells, or idol zones.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage/tick | Scaling | Pull radius |
|------|---------|------|----------|-----------|-------------|---------|-------------|
| Vortex | Pull | 8/sec | 10s | 1s | 8 | 0.2 | 4 |
| Vortex 2 | Stronger Pull | 12/sec | 10s | 1s | 14 | 0.3 | 5 |
| Vortex 3 | Crushing Pull | 18/sec | 10s | 1s | 22 | 0.4 | 6 |

### Drain

Channeled beam that deals damage and heals you for a percentage of damage dealt. The
channeler's sustain spell — Barrier prevents damage, Drain heals through it.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage/tick | Scaling | Heal % |
|------|---------|------|----------|-----------|-------------|---------|--------|
| Drain | Siphon | 4/sec | 15s | instant | 10 | 0.2 | 50% |
| Drain 2 | Greater Siphon | 7/sec | 15s | instant | 18 | 0.3 | 75% |
| Drain 3 | Life Drain | 12/sec | 15s | instant | 28 | 0.5 | 100% |

---

## Defense and Utility

### Heal

Restores health.

| Tier | Flavour | Cost | Cooldown | Cast time | Healing | Scaling |
|------|---------|------|----------|-----------|---------|---------|
| Heal | Heal | 5 | 20s | instant | 5 | 1 |
| Greater Healing | Stronger Heal | 15 | 20s | instant | 30 | 1.2 |
| Even Greater Healing | Great Heal | 50 | 20s | instant | 100 | 1.5 |

### Barrier

Channeled. Incoming damage is redirected to mana instead of HP. Stops movement while active.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage-to-mana ratio |
|------|---------|------|----------|-----------|----------------------|
| Barrier | Protect | 2/sec | 3s | instant | 0.5 |
| Greater Barrier | More Protection | 5/sec | 3s | instant | 0.3 |
| Even Greater Barrier | A Lot of Protection | 10/sec | 3s | instant | 0.0 (full absorb) |

### Blink

Teleport to cursor position (within the current room).

| Tier | Flavour | Cost | Cooldown | Cast time |
|------|---------|------|----------|-----------|
| Blink | Blink | 10 | 5s | instant |

Single tier only.

### Haste

Converts skill to speed for a duration.

| Tier | Flavour | Cost | Cooldown | Cast time | Duration | Scaling |
|------|---------|------|----------|-----------|----------|---------|
| Haste | Fast | 10 | 45s | 1s | 30s | 1.5 |

Single tier only.

---

## Summons

### Summoning

Summon a group of small minions that swarm and attack the nearest enemy. Minions are fragile
but numerous — their value is in combined DPS and distraction.

| Tier | Flavour | Cost | Cooldown | Count | Minion HP | Minion damage | Scaling | Duration |
|------|---------|------|----------|-------|-----------|---------------|---------|----------|
| Summoning | Summon Few | 15 | 20s | 3 | 8 | 5 | 0.3 | 15s |
| Summoning 2 | Summon More | 25 | 20s | 5 | 12 | 8 | 0.4 | 18s |
| Summoning 3 | Summon Many | 50 | 20s | 8 | 18 | 12 | 0.5 | 22s |

### Summon Golem

Summon a tanky creature that targets the nearest enemy and draws aggro. Recast to dismiss.
The golem's primary value is absorbing enemy attention — its damage is secondary to its role
as an aggro tank that buys safe Focus time.

| Tier | Flavour | Cost | Cooldown | Golem HP | Golem damage | Scaling | Duration |
|------|---------|------|----------|----------|-------------|---------|----------|
| Summon Golem | Friend | 20 | 30s | 60 | 8 | 0.5 | 20s |
| Summon Golem 2 | Bigger Friend | 30 | 30s | 120 | 12 | 1.0 | 25s |
| Summon Golem 3 | Even Bigger Friend | 60 | 30s | 200 | 18 | 1.5 | 30s |

---

## Idols (Placed Objects)

### Strength Idol

Place an idol. Bullets passing through it gain increased damage.

| Tier | Flavour | Cost | Cooldown | Cast time | Duration |
|------|---------|------|----------|-----------|----------|
| Strength Idol | — | 10 | 5s | 1s | 30s |

### Numbers Idol

Place an idol. Bullets passing through it are duplicated.

| Tier | Flavour | Cost | Cooldown | Cast time | Duration |
|------|---------|------|----------|-----------|----------|
| Numbers Idol | — | 20 | 5s | 1s | 15s |

### Healing Idol

Place an idol that heals over time in an area.

| Tier | Flavour | Cost | Cooldown | Cast time | Healing | Radius |
|------|---------|------|----------|-----------|---------|--------|
| Healing Idol | Doctor | 10 | 60s | instant | 30 over 10s | 4 |
| Healing Idol 2 | Better Doctor | 25 | 60s | instant | 50 over 10s | 5 |
| Healing Idol 3 | Very Good Doctor | 45 | 60s | instant | 80 over 10s | 6 |

### Iron Idol

Place an idol that reduces damage taken while you stand within its radius. The tank's
defensive idol — plant it at your position and hold ground.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage reduction | Radius | Duration |
|------|---------|------|----------|-----------|-----------------|--------|----------|
| Iron Idol | Shield | 8 | 10s | 1s | 20% | 4 | 25s |
| Iron Idol 2 | Strong Shield | 15 | 10s | 1s | 35% | 5 | 28s |
| Iron Idol 3 | Fortress | 25 | 10s | 1s | 50% | 5 | 30s |

### Cursed Idol

Place an idol that curses enemies in its radius — damage over time and slow. Combines the
roles of the old Curse Zone and Frost into a single placed object. Enemies entering the
radius take sustained damage and move slower. No skill scaling — value comes from zone
control and duration.

| Tier | Flavour | Cost | Cooldown | Cast time | Damage/sec | Slow | Radius | Duration |
|------|---------|------|----------|-----------|------------|------|--------|----------|
| Cursed Idol | Hex | 10 | 10s | 1s | 6 | 25% | 3 | 15s |
| Cursed Idol 2 | Bad Hex | 18 | 10s | 1s | 12 | 40% | 4 | 18s |
| Cursed Idol 3 | Vile Hex | 30 | 10s | 1s | 20 | 55% | 5 | 22s |
