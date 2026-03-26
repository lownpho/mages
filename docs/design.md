# Game Design

A top-down 2D action RPG where you play a mage. Explore a world, equip weapons, hats, and
robes that shape your stats, and fight enemies using mouse-aimed projectile combat. Four
spell slots let you equip powerful active abilities alongside your weapon.

The game is focused around spells — cooldowns are generally low so you're casting often.

---

## Core Stats

<!-- data:player_stats -->
| Stat  | Base | Role                                                        |
|-------|------|-------------------------------------------------------------|
| HP    | 100  | Passive defense. Survive hits, Focus safely under fire.     |
| Mana  | 30   | Fuel. More shots, more casts, longer channels before Focus. |
| Skill | 10   | Offense. Damage scaling on weapons and all damage spells.   |
| Speed | 80   | Active defense and offense. Outrun threats, reposition between casts, and increase weapon fire rate. |
<!-- end:player_stats -->

Low base mana means spells are real commitments — a single Fireball (15 mana) costs half
your pool. Focus matters early and often.

Low base skill means every point from gear is meaningful — a +10 hat at base is a major
power increase. Endgame skill (160+) is a transformation.

All damage scales with skill. Mana is fuel, not an offensive stat — deeper pools let you
cast more often, but skill determines how hard each cast hits.

---

## The Focus Mechanic

Hold a key, stop moving, recover mana. This is the core tension: **mana powers both your
weapon and your spells, and recovering it requires standing still in danger.**

How you Focus depends on your build:
- **Far-range builds:** Focus rarely but dangerously — no HP safety net.
- **Mid-range builds:** Focus at moderate intervals — speed creates safe distance.
- **Close-range builds:** Focus constantly — HP makes it safe at any position.

For Focus to work:
- Enemies must punish standing still (Skitters match player speed).
- Mana must run out at meaningful moments (30 base, spells cost 5–80).
- Recovery rate must be tuned against spell costs (currently 1 mana/tick).

---

## Builds and Range

Your weapon determines your combat range, and your gear determines your stat profile.
Every equipment choice is a tradeoff — no item has negative stats, so the cost of any
choice is the stats you *didn't* pick.

Three weapons define three combat ranges:

| | Far | Mid | Close |
|---|---|---|---|
| Weapon | Staff (+mana) | Wand (+skill) | Rune (+HP, +skill) |
| Damage source | Big spells | Weapon + fast spells | Weapon + attrition |
| Defense | Distance | Speed | HP + sustain spells |
| Spell profile | Expensive, long CD, cast times | Cheap, short CD, instant | Sustain, defense, area control |

Builds aren't locked — mixing gear and spells across ranges creates hybrids naturally.
A Wand user stacking speed with fire-and-forget spells plays very differently from one
stacking skill with channeled beams, even though both fight at mid range.

---

## Damage Formula

- **Weapons:** `base_damage + skill * skill_scaling`
- **Spells:** `base_damage + skill * scaling`

One damage path. No mana-based damage scaling.

---

## World Structure

TBD — procedurally generated overworld with dungeons branching off it.

### Overworld

TBD

### Dungeons

TBD — multi-room instanced dungeons. Each dungeon favors different builds through
enemy composition and room geometry.

### Progression

TBD — collect badges from dungeon bosses to unlock the final boss.
