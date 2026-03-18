# Balance

Analysis of the current numbers and proposed rebalanced values.

---

## Player base stats

| Stat | Current | Proposed | Reason |
|------|---------|----------|--------|
| Max HP | 100 | 100 | Works well as a baseline. |
| Max Mana | 50 | 30 | 50 is too generous. With Wand at 1 mana/shot, you get 50 shots before Focus. At 30, you get 30 — still a lot, but spells become a real mana commitment. A single Fireball (10 mana) now costs a third of your pool instead of a fifth. Focus matters earlier and more often. |
| Skill | 25 | 10 | 25 is too high relative to weapon base damage. With Wand (10 base, 1.0 scaling) at 25 skill, you deal 35 damage — already 2-shotting a 50 HP Husk. At 10 skill, Wand deals 20 damage. Husks take 3 shots. Skill from gear becomes more meaningful: a +10 skill hat doubles your effective skill instead of being a 40% bump. |
| Speed | 80 | 80 | 80 is correct — it matches the Skitter at 80, meaning the fastest enemy can keep up with the player. Kite Mage builds push past this with gear. |

### Why lower base mana matters

The game's core loop is: fight → run out of mana → Focus (danger) → fight again. If the base
mana pool is too large, the "run out of mana" step takes too long and Focus feels optional.

At 30 base mana:
- **Wand** (1-3 mana/shot): 10-30 shots before empty. 10-30 seconds of sustained fire at 1.0 fire rate.
- **Staff** (2-4 mana/shot): 7-15 shots before empty. 14-30 seconds at 0.5 fire rate.
- **Rune** (2-6 mana/shot): 5-15 shots before empty. 10-30 seconds at 2.0 fire rate.
- **Fireball** (10 mana): Costs a third of your base pool. Casting it is a real commitment.
- **Meteor** (10-50 mana): Tier 3 Meteor empties your entire base pool in one cast.

Mana-boosting gear becomes important: a Robe (+10 mana at tier 1) is a 33% increase to your
pool. A Hood (+3 mana) is still noticeable. The mana build with Ultimate Staff (+35) +
Ultimate Robe (+130) + Ultimate Hood (+30) reaches 225 mana — over 7x base. That's 22.5
seconds of Laser channeling at 10/sec, making mana a genuine offensive stat.

### Why lower base skill matters

Skill is the offensive stat for instant spells and weapons. Mana is the offensive stat for
channeled spells (more mana = longer channel = more total damage). If base skill is high,
gear bonuses are incremental. If base skill is low, every point of skill from gear feels
impactful — and the choice between skill gear and mana gear becomes meaningful.

At 10 base skill:
- **Naked Wand** (10 base + 10×1.0 scaling): 20 damage/shot.
- **Wand + Hat** (10 base + (10+10)×1.0): 30 damage/shot — a +10 hat is a 50% DPS increase.
- **Wand + Ultimate Hat** (10 base + (10+150)×1.0): 170 damage/shot — endgame feels like a transformation.

Compare to 25 base skill:
- **Naked Wand**: 35 damage/shot.
- **Wand + Hat**: 45 damage/shot — a +10 hat is only a 29% DPS increase.
- **Wand + Ultimate Hat**: 185 damage/shot — feels similar, but the *journey* from 35→185 is less dramatic than 20→170.

Lower base skill makes early gear upgrades feel more meaningful and makes the late-game power
spike more satisfying.

---

## Weapon balance

### Current issues

1. **Wand is too mana-efficient.** At 1 mana/shot with 1.0 scaling, it's the best damage per
   mana by far. You can fire 30 times (at proposed 30 mana) before Focusing. Staff fires 15
   times and Rune fires 15 times, but neither deals proportionally more damage per shot to
   compensate.

2. **Staff giving +skill contradicts its identity.** The Staff is the mana build weapon — it
   should fuel channeled spells, not boost instant spell damage. Giving +mana instead of
   +skill makes the weapon choice define the build: Wand users stack skill, Staff users
   stack mana. The 0.5 skill scaling means Staff doesn't benefit much from skill gear,
   pushing Staff users toward mana gear naturally.

3. **Rune's per-bullet damage is unclear.** The sheet lists 6 base damage — is this per
   bullet or total? If the Rune fires a 5-bullet shotgun, 6 damage per bullet is 30 total,
   which is reasonable. If it's 6 total across all bullets, it's terrible.

### Proposed weapon rebalance

**Wand** — increase mana cost slightly at higher tiers to make sustained fire more expensive.
The Wand should be mana-efficient early but not free at endgame.

| Tier | Base damage | Mana cost | Skill scaling | +Skill | Change |
|------|-----------|-----------|---------------|--------|--------|
| Wand | 8 | 1 | 1.0 | 0 | Base damage lowered (10→8) to reduce naked DPS |
| Good | 12 | 2 | 1.0 | 10 | Mana cost 1→2. Gear is the DPS, not the weapon. |
| Better | 18 | 2 | 1.0 | 15 | |
| Even Better | 28 | 3 | 1.0 | 25 | |
| Ultimate | 40 | 4 | 1.0 | 40 | Base 60→40. Ultimate Wand + Ultimate Hat skill (40+150=190) gives 40+190=230 damage at 4 mana. Still very strong. |

**Staff** — gives +mana instead of +skill. The mana build weapon. High base damage, low
scaling. Staff users don't stack skill — they stack mana to fuel channeled spells.

| Tier | Base damage | Mana cost | Skill scaling | +Mana | Change |
|------|-----------|-----------|---------------|-------|--------|
| Staff | 20 | 2 | 0.5 | 0 | Base up (15→20), scaling down (0.7→0.5). +Skill → +Mana. |
| Good | 30 | 3 | 0.5 | 5 | |
| Better | 50 | 3 | 0.5 | 10 | |
| Even Better | 80 | 4 | 0.5 | 20 | |
| Ultimate | 120 | 5 | 0.5 | 35 | 120 + 10×0.5 = 125 naked. Compare to Wand: 40 + 10×1.0 = 50 naked. Staff hits 2.5× harder per shot but fires 2× slower. The +35 mana fuels channeled spells. |

**Rune** — clarify as per-bullet damage, assume 5-bullet shotgun. Increase mana cost
progression to make the burst-Focus cycle more pronounced.

| Tier | Damage/bullet | Bullets | Mana cost | Skill scaling | +HP | Change |
|------|-------------|---------|-----------|---------------|-----|--------|
| Rune | 5 | 5 | 3 | 1.0 | 5 | Cost 2→3, base 6→5. Total burst: 5×(5+10×1.0) = 75 naked. |
| Good | 7 | 5 | 4 | 1.0 | 15 | |
| Better | 12 | 5 | 5 | 1.0 | 30 | |
| Even Better | 18 | 5 | 7 | 1.0 | 50 | |
| Ultimate | 25 | 5 | 9 | 1.0 | 80 | Total burst: 5×(25+50×1.0) = 375 at 9 mana. Empties pool in 3 bursts from base 30 mana. |

### DPS comparison at base stats (10 skill, 30 mana)

| Weapon | Damage/shot | Fire rate | Mana/shot | Shots per pool | Total damage | Time to empty |
|--------|-----------|-----------|-----------|----------------|--------------|---------------|
| Wand | 18 | 1.0/s | 1 | 30 | 540 | 30s |
| Staff | 25 | 0.5/s | 2 | 15 | 375 | 30s |
| Rune | 75 (burst) | 0.5/s | 3 | 10 | 750 | 20s |

Wand: sustained and efficient. Staff: fewer, heavier hits, same time to empty. Rune: highest
burst damage but empties pool fastest, forcing Focus sooner. Each weapon creates a different
Focus rhythm as intended.

**Key distinction:** Wand gives +skill (boosts per-hit damage), Staff gives +mana (fuels
channeled spells), Rune gives +HP (survivability). The weapon choice defines the build path.

---

## Equipment balance

### Hats — no changes needed

The hat progression is clean. Skill values scale appropriately and the three families
(Hat/Headband/Hood) offer a clear offensive choice. With lower base skill (10), even tier 1
hats (+7 to +10 skill) are meaningful — a 70-100% skill increase.

### Robes — adjust Vesture skill values

Mantle and Robe are fine — they offer HP or Mana with no offensive stats, which is correct for
the defensive slot. Vesture is the outlier that gives skill + speed, but its skill values are
too high at upper tiers. A Fancy Vesture (+20 skill) is as much as a Good Hat (+20 skill) while
also giving HP, mana, and speed. The Vesture should give less skill than a same-tier hat.

| Tier | +HP | +Mana | +Skill | +Speed | Change |
|------|-----|-------|--------|--------|--------|
| Vesture | 5 | 5 | 0 | 0 | No change |
| Better Vesture | 10 | 10 | 3 | 3 | Skill 5→3, Speed 5→3. Should be noticeably less than a same-tier hat. |
| Even Better Vesture | 15 | 15 | 7 | 5 | Skill 10→7, Speed 7→5. |
| Fancy Vesture | 30 | 30 | 12 | 8 | Skill 20→12, Speed 10→8. |
| Ultimate Vesture | 50 | 50 | 20 | 12 | Skill 40→20, Speed 15→12. Still the only robe with offense, but clearly weaker than a hat. |

---

## Enemy balance

### Current issues

1. **Prototype SmallDemon (100 HP, 16 speed) doesn't match the sheet (20 HP, 60 speed).**
   The sheet version is better — fast and fragile is more interesting than slow and tanky.

2. **Husk HP (50) may be too high for early game.** At 10 base skill with a naked Wand (18
   damage/shot), a Husk takes 3 shots. That's fine. With a Staff (25 damage/shot), 2 shots.
   Also fine. The Husk is a mana tax, not a brick wall.

3. **Ranger has no projectile stats.** Needs damage, projectile speed, and fire rate to
   function as a ranged threat.

### Proposed enemy stats

| Enemy | HP | Speed | Damage | Attack range | Detection range | Attack speed |
|-------|----|-------|--------|-------------|-----------------|-------------|
| Skitter | 15 | 80 | 8 | 24 (melee) | 96 | 0.3s (fast) |
| Small Demon | 20 | 60 | 12 | 32 (melee) | 80 | 0.8s |
| Husk | 50 | 40 | 15 (AoE) / 10 (single) | 24 (AoE) / 64 (single) | 96 | 1.2s |
| Ranger | 30 | 20 | 10 | 128 (ranged) | 128 | 2.0s |

**Reasoning:**
- **Skitter** deals low damage (8) but attacks fast (0.3s) and has short range (24). It rushes
  in, lands 2-3 quick hits (16-24 damage), then retreats. Against base 100 HP that's a 16-24%
  HP chunk — meaningful but not lethal. Against a Sniper standing still during Focus, it's
  frightening.
- **Small Demon** is the baseline: moderate damage (12), moderate speed. A predictable melee
  threat. Detection range 80 means you see it about when it sees you.
- **Husk** AoE at close range (15 damage, 24 range) punishes melee builds, while its single
  ranged attack (10 damage, 64 range) means you can't safely ignore it. Slow attack speed
  (1.2s) gives reaction windows.
- **Ranger** fires from 128 range (quite far) with slow projectiles. 10 damage every 2 seconds
  is low DPS, but the threat is that you take damage while Focusing at what you thought was a
  safe distance. It forces you to deal with it rather than ignore it.

### Kill time analysis (base 10 skill, no gear)

| Enemy | Wand shots | Staff shots | Rune bursts | Time to kill (Wand) |
|-------|-----------|-------------|-------------|---------------------|
| Skitter (15 HP) | 1 | 1 | 1 | 1.0s |
| Small Demon (20 HP) | 2 | 1 | 1 | 2.0s |
| Husk (50 HP) | 3 | 2 | 1 | 3.0s |
| Ranger (30 HP) | 2 | 2 | 1 | 2.0s |

At base stats, everything dies fast. The challenge isn't individual HP pools — it's enemy
*composition*. A room with 2 Skitters, a Husk, and a Ranger requires 8 Wand shots (8 mana)
and constant repositioning. That's the Focus tension: you can kill things quickly, but there
are always more things, and you need mana for all of them.

---

## Spell balance

### Two damage paths

The spell system splits into two scaling categories to support the three core builds:

- **Instant spells** (Fireball, Chain Lightning, Meteor, Piercing Lights): high skill scaling.
  Reward the glass cannon — more skill = harder hits per cast.
- **Channeled spells** (Laser, Charge Blast, Tornado, Barrier): high base damage, low skill
  scaling (0.2-0.7). Reward the mana build — more mana = longer channel = more total damage.

This makes mana a genuine offensive stat. A glass cannon and a mana build can deal comparable
total damage through completely different means.

### Instant spells: cost vs. impact at 30 base mana

Instant spells need to feel worth their mana cost relative to weapon shots. A Fireball costs
10 mana — that's 10 Wand shots (180 total damage) or one Fireball (15 + 10×2 = 35 damage in
an AoE). Fireball only wins if it hits multiple enemies or the AoE utility matters. This is
correct — instant spells are burst tools, not replacements for weapons.

### Channeled spells: mana pool as offense

Channeled spells don't compete with weapons on per-hit damage. Their value is sustained DPS
over time, gated by mana pool size.

**Laser 2** (25 base, 0.3 scaling, 10 mana/sec):
- Glass cannon (160 skill, 160 mana): 25 + 160×0.3 = **73 DPS** for 16s = **1168 total**
- Mana build (130 skill, 225 mana): 25 + 130×0.3 = **64 DPS** for 22.5s = **1440 total**

The glass cannon hits harder per tick but runs dry faster. The mana build sustains 40% longer
and deals 23% more total damage from the same spell. Both viable, different strengths.

**Barrier** (damage → mana conversion) naturally rewards mana pool — more mana = more damage
you can absorb before running empty. No skill scaling needed; it's inherently a mana/tank
spell.

### Spells that may need adjustment

- **Chain Lightning** at 5 mana is extremely cheap relative to the 30 mana base pool. At
  10 + 10×1 = 20 damage with 3 bounces = 60 total, that's 12 damage/mana. Correctly
  positioned as the skill build's cheap filler spell.

- **Blink** at 10 mana (a third of base pool) is expensive for utility. Correct — a free
  escape devalues Focus risk. Blinking costs future firepower or channel time.

- **Even Greater Barrier** at 10/sec with full absorption is very strong for tanks and mana
  builds. With 225 mana (Staff + Robe + Hood), you channel for 22.5 seconds absorbing all
  damage. The 10/sec drain is a serious commitment — you can't fire your weapon or cast other
  spells while channeling. Balanced by the opportunity cost.
