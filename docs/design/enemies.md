# Enemies

Four enemy types covering different threat profiles. Each enemy challenges a different player
strategy and interacts with the Focus mechanic differently.

Player base stats for reference: 100 HP, 80 speed, 10 skill, 30 mana.

All enemies can drop any item. Drop chance scales with toughness (Husk > Ranger > Small Demon
\> Skitter). Drop tier is weighted toward the enemy's power level — tougher enemies in later
dungeons drop higher-tier gear.

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

**Role:** Focus punisher. At 80 speed (matching the player), Skitters reach you during Focus.
Low HP means they die fast if you can track them, but their erratic pattern makes them hard to
hit. Forces reactive play — you can't ignore them and Focus.

| Stat | Value |
|------|-------|
| HP | 15 |
| Speed | 80 |
| Attack | Fast single hit |

---

## Small Demon

**Behavior:** Detect player, chase, attack when in range. Straightforward aggression.

**Role:** Baseline threat. Fast enough (60 speed) to pressure the player, slow enough to kite.
Creates the basic Focus tension — Focus when it's far, move when it's close.

| Stat | Value |
|------|-------|
| HP | 20 |
| Speed | 60 |
| Attack | Single melee |

---

## Husk

**Behavior:** Detect player, chase, attack when in range. Uses AoE when close, single attack
when far.

**Role:** Mana tax. 50 HP requires sustained fire to bring down, draining the player's mana.
Dual attack means no safe distance — you take damage either way. Forces extra Focus cycles
just to have enough mana to kill it.

| Stat | Value |
|------|-------|
| HP | 50 |
| Speed | 40 |
| Attack | AoE (close range), single (far range) |

---

## Ranger

**Behavior:** Detect player, follow at distance, attack in range. Ranged attacker.

**Role:** Positioning threat. Slow (20 speed) but fires at range. You can't outrun its
projectiles by kiting. Forces the player to either close distance to kill it quickly or find
cover. Makes room geometry matter.

| Stat | Value |
|------|-------|
| HP | 30 |
| Speed | 20 |
| Attack | Single ranged |
