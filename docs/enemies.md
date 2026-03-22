# Enemies

Four enemy types covering different threat profiles. Each enemy challenges different combat
ranges and interacts with the Focus mechanic differently.

Player base stats for reference: 100 HP, 80 speed, 10 skill, 30 mana.

All enemies can drop any item. Drop chance scales with toughness (Husk > Ranger > Small
Demon > Skitter). Drop tier is weighted toward the enemy's power level — tougher enemies
in later dungeons drop higher-tier gear.

---

## Overview

| Enemy | HP | Speed | Behavior | Attack style |
|-------|----|-------|----------|-------------|
| Skitter | 15 | 80 | Rush in, attack briefly, rush out, repeat | Fast single hit |
| Small Demon | 20 | 60 | Detect → chase → attack in range | Single melee |
| Husk | 50 | 40 | Detect → chase → attack in range | AoE when close, single when far |
| Ranger | 30 | 20 | Detect → follow → attack in range | Single ranged |

---

## Skitter

**Behavior:** Rush in, attack for a few seconds, rush out, repeat. Hit-and-run pattern.

**Role:** Focus punisher and cast interrupter. At 80 speed (matching the player), Skitters
reach you during Focus or cast times. Low HP means they die fast if you can track them, but
their erratic pattern makes them hard to hit.

**Range pressure:**
- **Far:** Terrifying. Interrupts cast times, closes gap on your fragile HP. Your biggest threat.
- **Mid:** Annoying. Forces repositioning, but you have speed to stay ahead and Wand to track it.
- **Close:** Trivial. One Rune burst kills it. It runs into your damage zone.

<!-- data:skitter -->
| Stat            | Value      |
|-----------------|------------|
| HP              | 15         |
| Speed           | 80         |
| Damage          | 8          |
| Attack range    | 24 (melee) |
| Detection range | 96         |
| Attack speed    | 0.3s       |
<!-- end:skitter -->

---

## Small Demon

**Behavior:** Detect player, chase, attack when in range. Straightforward aggression.

**Role:** Baseline threat. Fast enough (60 speed) to pressure, slow enough to kite. Creates
the basic Focus tension — Focus when it's far, move when it's close.

**Range pressure:**
- **Far:** One Staff shot kills it. Manageable from distance.
- **Mid:** Two Wand shots. You kite and fire, standard rhythm.
- **Close:** One Rune burst. It walks into your shotgun.

<!-- data:small_demon -->
| Stat            | Value      |
|-----------------|------------|
| HP              | 20         |
| Speed           | 60         |
| Damage          | 12         |
| Attack range    | 32 (melee) |
| Detection range | 80         |
| Attack speed    | 0.8s       |
<!-- end:small_demon -->

---

## Husk

**Behavior:** Detect player, chase, attack when in range. Uses AoE when close, single
attack when far.

**Role:** Mana tax. 50 HP requires sustained fire to bring down, draining the player's
mana pool. Dual attack means no safe distance — you take damage either way. Forces extra
Focus cycles.

**Range pressure:**
- **Far:** 2 Staff shots or one expensive spell. Drains your mana pool, which you need for big casts.
- **Mid:** 3 Wand shots. Manageable but delays your DPS rotation against other enemies.
- **Close:** 1 Rune burst at point blank. Most efficient kill, but you eat the AoE.

<!-- data:husk -->
| Stat            | Value                            |
|-----------------|----------------------------------|
| HP              | 50                               |
| Speed           | 40                               |
| Damage          | 15 (AoE close) / 10 (single far) |
| Attack range    | 24 (AoE) / 64 (single)           |
| Detection range | 96                               |
| Attack speed    | 1.2s                             |
<!-- end:husk -->

---

## Ranger

**Behavior:** Detect player, follow at distance, attack in range. Ranged attacker.

**Role:** Positioning threat. Slow (20 speed) but fires at range 128. You can't outrun
its projectiles by kiting. Forces you to close distance or find cover. Makes room geometry
matter.

**Range pressure:**
- **Far:** Threatens your preferred position. You're already at range, but so is the Ranger. Forces you to prioritize it.
- **Mid:** Breaks your kiting pattern. Projectiles ignore your speed advantage. Must close to kill.
- **Close:** You need to get to it. Once there, one Rune burst. But closing distance means crossing open ground.

<!-- data:ranger -->
| Stat            | Value        |
|-----------------|--------------|
| HP              | 30           |
| Speed           | 20           |
| Damage          | 10           |
| Attack range    | 128 (ranged) |
| Detection range | 128          |
| Attack speed    | 2.0s         |
<!-- end:ranger -->
