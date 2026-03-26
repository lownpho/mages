# Spells

Spells are active abilities with mana costs and cooldowns, equipped in the 4 spell slots.
Some are instant, some have cast times (rooting the player), some are channeled (draining
mana per second while active).

All damage spells scale with skill: `base_damage + skill × scaling`. Mana is fuel, not an
offensive stat — deeper pools let you cast more often, but skill determines how hard each
cast hits.

The game is focused around spells — cooldowns are generally low so you're casting often.

Spells are not locked to any build. Each spell has a **range fit** rating showing how
naturally it aligns with the three combat ranges:

- **Far** — expensive, long-cooldown, cast-time spells. Big commitments, big payoffs.
- **Mid** — cheap, short-cooldown, instant spells. Constant damage output.
- **Close** — sustain, support, and area control. Keep you alive and punish enemies nearby.

---

## Direct Damage

### Fireball

Single exploding projectile with AoE. Expensive burst with a brief cast commitment.

<!-- data:fireball -->
| Tier                  | Flavour              | Cost | Cooldown | Cast time | Damage | Scaling | Range | AoE |
|-----------------------|----------------------|------|----------|-----------|--------|---------|-------|-----|
| Fireball              | Fireball             | 15   | 6s       | 0.5s      | 20     | 2.0     | 12    | 3   |
| Greater Fireball      | Bigger Fireball      | 30   | 6s       | 0.5s      | 45     | 3.0     | 16    | 4   |
| Even Greater Fireball | Even Bigger Fireball | 60   | 6s       | 0.5s      | 80     | 4.5     | 20    | 5   |
<!-- end:fireball -->

<!-- data:fireball_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 3   | 2   | 1     |
<!-- end:fireball_fit -->

### Meteor

Meteor falls at target location after a delay. The biggest single hit in the game. Long
cast time, long cooldown, enormous cost. Every cast is a major commitment.

<!-- data:meteor -->
| Tier     | Flavour            | Cost | Cooldown | Cast time | Damage | Scaling | Delay | AoE |
|----------|--------------------|------|----------|-----------|--------|---------|-------|-----|
| Meteor   | Meteor             | 20   | 12s      | 1s        | 40     | 3.0     | 1.5s  | 4   |
| Meteor 2 | Bigger Meteor      | 45   | 12s      | 1s        | 80     | 4.5     | 1.5s  | 5   |
| Meteor 3 | Even Bigger Meteor | 80   | 12s      | 1s        | 140    | 6.0     | 1.5s  | 6   |
<!-- end:meteor -->

<!-- data:meteor_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 3   | 1   | 1     |
<!-- end:meteor_fit -->

### Piercing Lights

Projectiles spawn around the caster and fly in the direction of the mouse cursor at the
moment of casting. They pierce through enemies until hitting a wall or leaving the screen.
No homing — aim matters. Damage is per projectile.

<!-- data:piercing_lights -->
| Tier              | Flavour     | Cost | Cooldown | Cast time | Damage | Scaling | Projectiles |
|-------------------|-------------|------|----------|-----------|--------|---------|-------------|
| Piercing Lights   | Pew Pew     | 20   | 6s       | 0.5s      | 10     | 0.2     | 10          |
| Piercing Lights 2 | Pew Pew Pew | 40   | 6s       | 0.5s      | 25     | 0.3     | 14          |
| Piercing Lights 3 | Peeew Peeew | 70   | 6s       | 0.5s      | 45     | 0.4     | 20          |
<!-- end:piercing_lights -->

<!-- data:piercing_lights_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 3   | 2   | 1     |
<!-- end:piercing_lights_fit -->

### Frost Burst

Channeled. Target a point on the ground. The longer you channel, the more ice builds
up — and the bigger the burst of ice shards when you release. High risk/reward — stand
still longer for a bigger payoff.

<!-- data:frost_burst -->
| Tier          | Flavour        | Cost   | Cooldown | Cast time | 1s damage | 2s damage | 3s+ damage | Scaling | 1s radius | 2s radius | 3s+ radius |
|---------------|----------------|--------|----------|-----------|-----------|-----------|------------|---------|-----------|-----------|------------|
| Frost Burst   | Chill          | 8/sec  | 8s       | instant   | 20        | 50        | 90         | 0.5     | 2         | 3         | 5          |
| Frost Burst 2 | Deep Freeze    | 14/sec | 8s       | instant   | 40        | 85        | 150        | 0.8     | 3         | 4         | 6          |
| Frost Burst 3 | Absolute Zero  | 20/sec | 8s       | instant   | 65        | 130       | 220        | 1.2     | 3         | 5         | 8          |
<!-- end:frost_burst -->

<!-- data:frost_burst_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 3   | 2   | 2     |
<!-- end:frost_burst_fit -->

### Chain Lightning

Projectile that bounces between enemies. Cheap, fast, spammable. The filler spell — low
commitment, constant output.

<!-- data:chain_lightning -->
| Tier              | Flavour  | Cost | Cooldown | Cast time | Damage | Scaling | Bounces |
|-------------------|----------|------|----------|-----------|--------|---------|---------|
| Chain Lightning   | Zap      | 5    | 2s       | instant   | 8      | 0.5     | 3       |
| Chain Lightning 2 | More Zap | 10   | 2s       | instant   | 15     | 0.8     | 4       |
| Chain Lightning 3 | Zaaaap   | 15   | 2s       | instant   | 25     | 1.2     | 6       |
<!-- end:chain_lightning -->

<!-- data:chain_lightning_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 3   | 2     |
<!-- end:chain_lightning_fit -->

### Laser

Continuous piercing beam that follows the cursor. Channeled. Unlimited range — beam
travels until it hits a wall. Sustained DPS that can sweep across the room.

<!-- data:laser -->
| Tier    | Flavour        | Cost   | Cooldown | Cast time | Damage/tick | Scaling |
|---------|----------------|--------|----------|-----------|-------------|---------|
| Laser   | Whoop          | 4/sec  | 3s       | instant   | 12          | 0.6     |
| Laser 2 | Shoop          | 8/sec  | 3s       | instant   | 22          | 0.8     |
| Laser 3 | Shoop Da Whoop | 15/sec | 3s       | instant   | 35          | 1.0     |
<!-- end:laser -->

<!-- data:laser_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 3   | 1     |
<!-- end:laser_fit -->

### Charge Blast

Hold to charge a projectile that grows larger with each tick — release to fire. Pierces
through enemies, dies on walls. You can move freely while charging. Higher tiers charge
more ticks for bigger blasts. Quick commitment — 1.5 to 2.5 seconds to full charge.

<!-- data:charge_blast -->
| Tier           | Flavour       | Cost   | Cooldown | Charge time | Damage/tick | Scaling | Max ticks |
|----------------|---------------|--------|----------|-------------|-------------|---------|-----------|
| Charge Blast   | Blast         | 4/sec  | 2s       | 0.5s/tick   | 15          | 0.5     | 3         |
| Charge Blast 2 | Bigger Blast  | 7/sec  | 2s       | 0.5s/tick   | 25          | 0.7     | 4         |
| Charge Blast 3 | Biggest Blast | 12/sec | 2s       | 0.5s/tick   | 40          | 1.0     | 5         |
<!-- end:charge_blast -->

<!-- data:charge_blast_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 3   | 1     |
<!-- end:charge_blast_fit -->

---

## Control

### Vortex

Single cast. Creates a vortex at target point that pulls enemies toward it while dealing
low damage. Fixed duration. Drains mana per second while active — if you run out of mana,
the vortex cancels early. You can move and act freely while it runs.

<!-- data:vortex -->
| Tier     | Flavour       | Cost   | Cooldown | Cast time | Damage/tick | Scaling | Pull radius | Duration |
|----------|---------------|--------|----------|-----------|-------------|---------|-------------|----------|
| Vortex   | Pull          | 6/sec  | 6s       | instant   | 8           | 0.3     | 4           | 4s       |
| Vortex 2 | Stronger Pull | 10/sec | 6s       | instant   | 15          | 0.5     | 5           | 5s       |
| Vortex 3 | Crushing Pull | 16/sec | 6s       | instant   | 25          | 0.7     | 6           | 6s       |
<!-- end:vortex -->

<!-- data:vortex_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 3   | 2     |
<!-- end:vortex_fit -->

### Drain

Channeled beam that deals damage and heals you for a percentage of damage dealt. Sustain
channel — stay alive by leeching. Beam range of 6.

<!-- data:drain -->
| Tier    | Flavour        | Cost   | Cooldown | Cast time | Damage/tick | Scaling | Heal % | Range |
|---------|----------------|--------|----------|-----------|-------------|---------|--------|-------|
| Drain   | Siphon         | 4/sec  | 8s       | instant   | 10          | 0.4     | 50%    | 6     |
| Drain 2 | Greater Siphon | 7/sec  | 8s       | instant   | 18          | 0.6     | 75%    | 6     |
| Drain 3 | Life Drain     | 12/sec | 8s       | instant   | 30          | 0.8     | 100%   | 6     |
<!-- end:drain -->

<!-- data:drain_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 2   | 3     |
<!-- end:drain_fit -->

---

## Defense and Utility

### Heal

Restores health. Instant, no-nonsense sustain.

<!-- data:heal -->
| Tier                 | Flavour       | Cost | Cooldown | Cast time | Healing | Scaling |
|----------------------|---------------|------|----------|-----------|---------|---------|
| Heal                 | Heal          | 8    | 12s      | instant   | 15      | 0.5     |
| Greater Healing      | Stronger Heal | 20   | 12s      | instant   | 40      | 0.8     |
| Even Greater Healing | Great Heal    | 45   | 12s      | instant   | 80      | 1.2     |
<!-- end:heal -->

<!-- data:heal_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 2   | 3     |
<!-- end:heal_fit -->

### Barrier

Channeled. Incoming damage is redirected to mana instead of HP. Stops movement while
active. Scales with mana pool — more mana means more damage you can absorb.

<!-- data:barrier -->
| Tier                 | Flavour             | Cost   | Cooldown | Cast time | Damage-to-mana ratio |
|----------------------|---------------------|--------|----------|-----------|----------------------|
| Barrier              | Protect             | 2/sec  | 2s       | instant   | 0.5                  |
| Greater Barrier      | More Protection     | 5/sec  | 2s       | instant   | 0.3                  |
| Even Greater Barrier | A Lot of Protection | 10/sec | 2s       | instant   | 0.0 (full absorb)    |
<!-- end:barrier -->

<!-- data:barrier_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 1   | 3     |
<!-- end:barrier_fit -->

### Blink

Teleport to cursor position (within the current room). Universal escape.

<!-- data:blink -->
| Tier  | Flavour | Cost | Cooldown | Cast time |
|-------|---------|------|----------|-----------|
| Blink | Blink   | 10   | 4s       | instant   |
<!-- end:blink -->

Single tier only.

<!-- data:blink_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 2   | 1     |
<!-- end:blink_fit -->

### Haste

Converts skill to speed for a duration. Best for builds that already stack skill and
want repositioning power.

<!-- data:haste -->
| Tier  | Flavour | Cost | Cooldown | Cast time | Duration | Scaling |
|-------|---------|------|----------|-----------|----------|---------|
| Haste | Fast    | 10   | 30s      | 1s        | 30s      | 1.5     |
<!-- end:haste -->

Single tier only.

<!-- data:haste_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 3   | 1     |
<!-- end:haste_fit -->

---

## Summons

### Summoning

Summon a group of small minions that swarm and attack the nearest enemy. Minions are
fragile but numerous — their value is in combined DPS and distraction. Extra bodies
between you and enemies.

<!-- data:summoning -->
| Tier        | Flavour     | Cost | Cooldown | Count | Minion HP | Minion damage | Scaling | Duration |
|-------------|-------------|------|----------|-------|-----------|---------------|---------|----------|
| Summoning   | Summon Few  | 15   | 14s      | 3     | 8         | 5             | 0.3     | 15s      |
| Summoning 2 | Summon More | 25   | 14s      | 5     | 12        | 8             | 0.5     | 18s      |
| Summoning 3 | Summon Many | 50   | 14s      | 8     | 18        | 12            | 0.7     | 22s      |
<!-- end:summoning -->

<!-- data:summoning_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 2   | 3     |
<!-- end:summoning_fit -->

### Summon Golem

Summon a tanky creature that targets the nearest enemy and draws aggro. Recast to
dismiss. Primary value is absorbing enemy attention — buys safe Focus time.

<!-- data:summon_golem -->
| Tier           | Flavour            | Cost | Cooldown | Golem HP | Golem damage | Scaling | Duration |
|----------------|--------------------|------|----------|----------|--------------|---------|----------|
| Summon Golem   | Friend             | 20   | 20s      | 60       | 8            | 0.3     | 20s      |
| Summon Golem 2 | Bigger Friend      | 35   | 20s      | 120      | 15           | 0.5     | 25s      |
| Summon Golem 3 | Even Bigger Friend | 60   | 20s      | 200      | 22           | 0.8     | 30s      |
<!-- end:summon_golem -->

<!-- data:summon_golem_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 1   | 3     |
<!-- end:summon_golem_fit -->

---

## Idols (Placed Objects)

### Strength Idol

Place an idol. Bullets passing through it gain increased damage. Best with fast-firing
weapons that send more bullets through per second.

<!-- data:strength_idol -->
| Tier            | Flavour         | Cost | Cooldown | Cast time | Duration | Damage bonus |
|-----------------|-----------------|------|----------|-----------|----------|--------------|
| Strength Idol   | Empower         | 10   | 4s       | 0.5s      | 20s      | +25%         |
| Strength Idol 2 | Greater Empower | 18   | 4s       | 0.5s      | 25s      | +50%         |
| Strength Idol 3 | Supreme Empower | 30   | 4s       | 0.5s      | 30s      | +75%         |
<!-- end:strength_idol -->

<!-- data:strength_idol_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 2   | 3   | 2     |
<!-- end:strength_idol_fit -->

### Numbers Idol

Place an idol. Bullets passing through it are duplicated. Fast-firing weapons benefit
the most.

<!-- data:numbers_idol -->
| Tier           | Flavour       | Cost | Cooldown | Cast time | Duration | Extra bullets |
|----------------|---------------|------|----------|-----------|----------|---------------|
| Numbers Idol   | Split         | 20   | 4s       | 0.5s      | 10s      | +1            |
| Numbers Idol 2 | Greater Split | 35   | 4s       | 0.5s      | 12s      | +2            |
| Numbers Idol 3 | Supreme Split | 55   | 4s       | 0.5s      | 15s      | +3            |
<!-- end:numbers_idol -->

<!-- data:numbers_idol_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 3   | 2     |
<!-- end:numbers_idol_fit -->

### Healing Idol

Place an idol that heals over time in an area. Plant it where you're fighting.

<!-- data:healing_idol -->
| Tier           | Flavour      | Cost | Cooldown | Cast time | Healing     | Radius |
|----------------|--------------|------|----------|-----------|-------------|--------|
| Healing Idol   | Mend         | 10   | 30s      | 0.5s      | 30 over 10s | 4      |
| Healing Idol 2 | Greater Mend | 25   | 30s      | 0.5s      | 50 over 10s | 5      |
| Healing Idol 3 | Supreme Mend | 45   | 30s      | 0.5s      | 80 over 10s | 6      |
<!-- end:healing_idol -->

<!-- data:healing_idol_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 1   | 3     |
<!-- end:healing_idol_fit -->

### Iron Idol

Place an idol that reduces damage taken while you stand within its radius. Hold your
ground inside it.

<!-- data:iron_idol -->
| Tier        | Flavour         | Cost | Cooldown | Cast time | Damage reduction | Radius | Duration |
|-------------|-----------------|------|----------|-----------|------------------|--------|----------|
| Iron Idol   | Bulwark         | 8    | 6s       | 0.5s      | 20%              | 4      | 25s      |
| Iron Idol 2 | Greater Bulwark | 15   | 6s       | 0.5s      | 35%              | 5      | 28s      |
| Iron Idol 3 | Supreme Bulwark | 25   | 6s       | 0.5s      | 50%              | 5      | 30s      |
<!-- end:iron_idol -->

<!-- data:iron_idol_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 1   | 3     |
<!-- end:iron_idol_fit -->

### Cursed Idol

Place an idol that curses enemies in its radius — damage over time and slow. Enemies
entering the radius take sustained damage and move slower. No skill scaling — value
comes from zone control and duration.

<!-- data:cursed_idol -->
| Tier          | Flavour  | Cost | Cooldown | Cast time | Damage/sec | Slow | Radius | Duration |
|---------------|----------|------|----------|-----------|------------|------|--------|----------|
| Cursed Idol   | Hex      | 10   | 6s       | 0.5s      | 6          | 25%  | 3      | 15s      |
| Cursed Idol 2 | Foul Hex | 18   | 6s       | 0.5s      | 12         | 40%  | 4      | 18s      |
| Cursed Idol 3 | Vile Hex | 30   | 6s       | 0.5s      | 20         | 55%  | 5      | 22s      |
<!-- end:cursed_idol -->

<!-- data:cursed_idol_fit -->
| Far | Mid | Close |
|-----|-----|-------|
| 1   | 2   | 3     |
<!-- end:cursed_idol_fit -->
