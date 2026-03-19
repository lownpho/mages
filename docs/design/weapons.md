# Weapons

Three weapon families with 5 tiers each. Every weapon occupies the weapon equipment slot.
Weapons consume mana per shot and define the player's basic attack pattern.

Damage formula: `base_damage + skill × skill_scaling`

---

## Wand

Homing projectile that targets the enemy closest to the mouse cursor. Fast fire rate, low mana
cost, full skill scaling. The precision weapon.

| Tier | Base damage | Variability | Range | Fire rate | Mana cost | Skill scaling | +Skill |
|------|-----------|-------------|-------|-----------|-----------|---------------|--------|
| Wand | 10 | 10 | 10 | 1.0 | 1 | 1.0 | 0 |
| Good Wand | 15 | 10 | 10 | 1.0 | 1 | 1.0 | 10 |
| Better Wand | 25 | 10 | 10 | 1.0 | 2 | 1.0 | 15 |
| Even Better Wand | 40 | 10 | 10 | 1.0 | 2 | 1.0 | 25 |
| Ultimate Wand | 60 | 10 | 10 | 1.0 | 3 | 1.0 | 40 |

**Design idea:** Full skill build weapon.

---

## Staff

No special projectile behavior. High base damage, slow fire rate, low skill scaling. The
mana build weapon — it gives +mana instead of +skill, fueling channeled spells.

| Tier | Base damage | Variability | Range | Fire rate | Mana cost | Skill scaling | +Mana |
|------|-----------|-------------|-------|-----------|-----------|---------------|-------|
| Staff | 15 | 20 | 6 | 0.5 | 2 | 0.5 | 0 |
| Good Staff | 18 | 20 | 6 | 0.5 | 2 | 0.5 | 5 |
| Better Staff | 33 | 20 | 6 | 0.5 | 3 | 0.5 | 10 |
| Even Better Staff | 60 | 20 | 6 | 0.5 | 3 | 0.5 | 20 |
| Ultimate Staff | 90 | 20 | 6 | 0.5 | 4 | 0.5 | 35 |

**Design idea:** Mana build weapon. High base damage means it hits hard without skill gear.
Low skill scaling (0.5) means skill-stacking benefits the Wand more. The +mana stat modifier
deepens the mana pool for channeled spells (Laser, Barrier, Charge Blast). Staff users don't
need skill — they need mana to keep channeling.

---

## Rune

Shotgun pattern that homes to the nearest enemy. Short range, high variability, slow fire rate.
The only weapon that gives +HP. The tank weapon.

| Tier | Base damage | Variability | Range | Fire rate | Mana cost | Skill scaling | Angle | +Skill | +HP |
|------|-----------|-------------|-------|-----------|-----------|---------------|-------|--------|-----|
| Rune | 6 | 35 | 4 | 2.0 | 2 | 1.0 | 60 | 0 | 5 |
| Good Rune | 9 | 35 | 4 | 2.0 | 3 | 1.0 | 56 | 10 | 15 |
| Better Rune | 15 | 35 | 4 | 2.0 | 4 | 1.0 | 52 | 15 | 30 |
| Even Better Rune | 21 | 35 | 4 | 2.0 | 5 | 1.0 | 48 | 25 | 50 |
| Ultimate Rune | 30 | 35 | 4 | 2.0 | 6 | 1.0 | 45 | 40 | 80 |

**Design idea:** Tanky build weapon. Base tier fires a shotgun pattern; higher tiers home to
nearest enemy.

**Open question:** Shotgun with random bullet spread instead of radial pattern?
