# Weapons

Three weapon families with 5 tiers each. Every weapon occupies the weapon equipment slot.
Weapons consume mana per shot and define the player's basic attack pattern.

Each weapon supports a different combat range. The weapon choice is the primary build
decision — it determines where you fight and what stats matter most.

Damage formula: `base_damage + skill × skill_scaling`

---

## Staff

Homing projectile that targets the enemy closest to the mouse cursor. Slow fire rate,
high base damage, high mana cost. The far-range weapon — powerful shots from a safe
distance, with +mana to fuel expensive spells.

<!-- data:staff -->
| Tier              | Base damage | Range | Fire rate | Mana cost | Skill scaling | +Mana |
|-------------------|-------------|-------|-----------|-----------|---------------|-------|
| Staff             | 20          | 12    | 0.7       | 2         | 0.7           | 0     |
| Good Staff        | 30          | 12    | 0.8       | 3         | 0.7           | 5     |
| Better Staff      | 50          | 12    | 0.8       | 3         | 0.7           | 10    |
| Even Better Staff | 80          | 12    | 0.9       | 4         | 0.7           | 20    |
| Ultimate Staff    | 120         | 12    | 1.0       | 5         | 0.7           | 35    |
<!-- end:staff -->

**Design idea:** Far-range weapon. High base damage means each shot counts. Slow fire
rate (0.7–1.0 shots/sec) creates natural windows for spell casts and Focus. The +mana
funds expensive spells (Meteor, Fireball, Piercing Lights). Homing lets you hit reliably
from max distance without precise aim.

---

## Wand

Homing projectile that targets the enemy closest to the mouse cursor. Fast fire rate,
low mana cost, full skill scaling. The mid-range weapon — constant damage output with
+skill for aggressive spellcasting.

<!-- data:wand -->
| Tier             | Base damage | Range | Fire rate | Mana cost | Skill scaling | +Skill |
|------------------|-------------|-------|-----------|-----------|---------------|--------|
| Wand             | 8           | 8     | 1.2       | 1         | 1.0           | 0      |
| Good Wand        | 12          | 8     | 1.5       | 2         | 1.0           | 10     |
| Better Wand      | 18          | 8     | 1.8       | 2         | 1.0           | 15     |
| Even Better Wand | 28          | 8     | 2.0       | 3         | 1.0           | 25     |
| Ultimate Wand    | 40          | 8     | 2.5       | 4         | 1.0           | 40     |
<!-- end:wand -->

**Design idea:** Mid-range DPS weapon. Fire rate scales with tier (1.2–2.5 shots/sec),
making higher-tier Wands feel noticeably faster. Full 1.0 skill scaling means every point
of skill pays off on every shot. Low base damage — the Wand's power comes from skill
stacking and fire rate, not raw stats. The +skill reinforces the DPS build. Mana-efficient
early but costs climb at higher tiers — Ultimate Wand at 2.5 shots/sec and 4 mana/shot
burns 10 mana/sec.

---

## Rune

Shotgun pattern. Short range, slow fire rate. The only weapon that gives +HP.
The close-range weapon — burst damage up close with survivability to match.

<!-- data:rune -->
| Tier             | Damage/bullet | Bullets | Range | Fire rate | Mana cost | Skill scaling | Angle | +Skill | +HP |
|------------------|---------------|---------|-------|-----------|-----------|---------------|-------|--------|-----|
| Rune             | 5             | 5       | 4     | 0.6       | 3         | 1.0           | 60    | 0      | 5   |
| Good Rune        | 7             | 5       | 4     | 0.7       | 4         | 1.0           | 56    | 10     | 15  |
| Better Rune      | 12            | 5       | 4     | 0.7       | 5         | 1.0           | 52    | 15     | 30  |
| Even Better Rune | 18            | 5       | 4     | 0.8       | 7         | 1.0           | 48    | 25     | 50  |
| Ultimate Rune    | 25            | 5       | 4     | 1.0       | 9         | 1.0           | 45    | 40     | 80  |
<!-- end:rune -->

**Design idea:** Close-range weapon. 5-bullet shotgun (0.6–1.0 bursts/sec) for massive
burst at point blank. At range 4, all bullets hit the same target — at distance, they
spread across the arc. The +HP is unique among weapons and defines the close-range build path.
High mana cost means frequent Focus, but high HP makes Focus safe.
