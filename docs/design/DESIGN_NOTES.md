# Design Notes

An analysis of the game design based on the current prototype, the balance spreadsheet, and
where the systems are heading. Updated to reflect design decisions that have been made since
the initial prototype.

---

## What the game is

A top-down 2D action RPG where you play a mage. You explore a world, equip weapons, hats, and
robes that shape your stats, and fight enemies using mouse-aimed projectile combat. A Focus
mechanic lets you stand still to recover mana. Four spell slots let you equip powerful active
abilities alongside your weapon.

Current prototype state: one open room, 2 test weapon types, 3 test hat types, 1 enemy type,
no spells, no robes, no death screen, no win condition. The balance sheet defines the full
content plan that hasn't been built yet.

---

## The Focus mechanic — the core loop

Focus (hold a key, stop moving, recover mana) is the signature mechanic. It creates a central
tension: **mana powers both your weapon and your spells, and recovering it requires standing
still in danger**.

The balance sheet makes Focus even more important than it was in the prototype. Spells cost
significant mana (5-60 per cast, or 2-20/sec for channeled spells), and weapons cost 1-6 mana
per shot. A player who uses spells aggressively will burn through mana fast and need to Focus
often. This is the intended rhythm: fight, burn mana, find a window to Focus, fight again.

For Focus to work as the core loop, these things need to be true:

- **Enemies must punish standing still.** The Skitter (80 speed, rush-in/rush-out) is designed
  exactly for this — it matches the player's speed and will catch you during Focus. The current
  prototype only has the SmallDemon at 16 speed, which is trivially kiteable. Implementing the
  Skitter is the single most important thing for making Focus feel real.

- **Mana must run out at meaningful moments.** The prototype has 50 base mana with 1 mana/shot
  weapons, so you get 50 shots before needing to Focus. With the planned weapons (1-6
  mana/shot) and spells (5-60 mana/cast), mana will deplete much faster — a single Fireball
  costs 10-50 mana. The tension should emerge naturally once spells are in.

- **Focus recovery rate must be tuned against spell costs.** Currently 1 mana/tick. If a
  Fireball costs 10 mana, you need 10 ticks of standing still to earn one cast. That's the
  right kind of tradeoff if the tick rate is tuned well.

---

## The spell system — decided

The balance sheet resolves the biggest open question from the prototype. The answer is a
variant of **Option A from the original notes**: spells are active abilities with both mana
costs and cooldowns. Weapons remain your basic mana-consuming attack; spells are powerful
situational abilities you weave in.

This creates a **two-resource combat system**: mana is the shared pool, cooldowns gate spell
frequency, and Focus is how you refill. Spells split into two scaling categories:

- **Instant spells** (Fireball, Chain Lightning, Meteor, Piercing Lights) have high skill
  scaling — they reward the glass cannon build.
- **Channeled spells** (Laser, Charge Blast, Tornado, Barrier) have high base damage and low
  skill scaling — they reward the mana build. More mana = longer channel = more total damage.

A player must decide: do I stack skill for burst damage, or mana for sustained channels?

### Spell families (16 planned, most with 3 tiers)

**Direct damage:**

| Spell | Effect | Cost | Cooldown | Cast time | Notes |
|-------|--------|------|----------|-----------|-------|
| Fireball | Exploding AoE projectile | 10-50 | 8s | instant | Skill-scaling (2-4), range 10-18 |
| Piercing Lights | Homing projectiles that pierce | 15-50 | 10s | instant | 10-18 projectiles, scales 0.3-0.5 |
| Meteor | Delayed AoE at target location | 10-50 | 15s | 0.5s | 1.5s delay before impact, scaling 3-5 |
| Chain Lightning | Bouncing projectile between enemies | 5-18 | 4s | instant | 3-5 bounces, low cost, short CD |
| Charge Blast | Channeled piercing beam, dies on walls | 5/sec | 3s | 0.5s/tick | Up to 3 ticks, more charge = more power |
| Laser | Continuous beam following cursor | 5-20/sec | 6s | instant | Channeled, follows mouse |

**Control and area denial:**

| Spell | Effect | Cost | Cooldown | Cast time |
|-------|--------|------|----------|-----------|
| Tornado | Follows a mouse-drawn path, DoT | 10 | 15s | 1s |
| Curse Zone | DoT area | 10 | 10s | instant |
| Frost | Slow + DoT | 5 | 15s | instant |

**Defense and utility:**

| Spell | Effect | Cost | Cooldown | Cast time |
|-------|--------|------|----------|-----------|
| Heal | Restores health | 5-50 | 20s | instant |
| Barrier | Redirects damage to mana | 2-10/sec | 3s | instant |
| Blink | Teleport to cursor | 10 | 5s | instant |
| Haste | Converts skill to speed | 10 | 45s | 1s |

**Summons:**

| Spell | Effect | Cost | Cooldown |
|-------|--------|------|----------|
| Summoning | Spawn small minions | 15-50 | 20s |
| Summon Golem | Tanky summon that draws aggro, recast to kill | 20-60 | 30s |

**Idols (placed objects):**

| Spell | Effect | Cost | Cooldown | Cast time |
|-------|--------|------|----------|-----------|
| Strength Idol | Bullets through it gain damage | 10 | 5s | 1s |
| Numbers Idol | Bullets through it duplicate | 20 | 5s | 1s |
| Healing Idol | Area heal over time | 10-25 | 60s | instant |

### Design observations on spells

The spell list has strong variety across roles (damage, control, defense, summons, placement).
A few things stand out:

- **Cast times create a Focus-like vulnerability.** Tornado (1s), Haste (1s), Charge Blast
  (0.5s/tick), and the Idols (1s) all root you while casting. This is a second axis of
  "standing still = danger" that reinforces Focus as the core tension.

- **Channeled spells are the mana build's core.** Laser (0.2-0.5 scaling), Charge Blast
  (0.2-0.5), Tornado (0.3-0.7), and Barrier all have high base damage with low skill scaling.
  They compete directly with Focus for mana — you literally cannot Focus and channel at the
  same time. This creates the mana build's rhythm: channel → deplete → Focus → channel again.

- **Idol spells are the most unique mechanic.** Placing an object that modifies your bullets
  creates positioning gameplay — you want to fire through your Strength Idol, which means
  positioning it between you and enemies. This interacts with Focus too: do you place an idol
  and Focus behind it, or save the mana?

- **Chain Lightning is the spam spell.** 5 mana, 4s cooldown, bounces between enemies. It's
  the cheapest and fastest spell, clearly designed for frequent use. Pairs well with Focus
  rhythm — Focus for 5 ticks, cast Chain Lightning, repeat.

- **The Golem is the anti-Focus spell.** Summon a tank that draws aggro, buying you safe Focus
  time. Expensive (20-60 mana) but directly solves the Focus vulnerability problem. Good design
  — it costs the resource you're trying to recover.

---

## Weapon design — three families with clear identities

The balance sheet defines 3 weapon families with 5 tiers each, replacing the 2 test weapons
in the prototype. Each weapon family supports a different playstyle:

### Wand — the skill weapon

| Tier | Base dmg | Skill scaling | Mana cost | Fire rate | Special |
|------|----------|---------------|-----------|-----------|---------|
| Wand | 10 | 1.0 | 1 | 1.0 | Homing to closest mouse target |
| Good | 15 | 1.0 | 1 | 1.0 | +10 skill |
| Better | 25 | 1.0 | 2 | 1.0 | +15 skill |
| Even Better | 40 | 1.0 | 2 | 1.0 | +25 skill |
| Ultimate | 60 | 1.0 | 3 | 1.0 | +40 skill |

**Identity:** Precise, efficient, fast-firing, long range (10). Homing to the target nearest
your cursor means you aim by pointing, not by lining up shots. Full 1.0 skill scaling means
this weapon benefits the most from skill-stacking gear (hats). Low mana cost (1-3) means you
can fire a lot before needing to Focus. The glass-cannon weapon.

### Staff — the mana weapon

| Tier | Base dmg | Skill scaling | Mana cost | Fire rate | Special |
|------|----------|---------------|-----------|-----------|---------|
| Staff | 15 | 0.5 | 2 | 0.5 | None |
| Good | 18 | 0.5 | 2 | 0.5 | +5 mana |
| Better | 33 | 0.5 | 3 | 0.5 | +10 mana |
| Even Better | 60 | 0.5 | 3 | 0.5 | +20 mana |
| Ultimate | 90 | 0.5 | 4 | 0.5 | +35 mana |

**Identity:** High base damage, slow fire rate (0.5 = every 2 seconds), no special behavior.
The Staff gives **+mana instead of +skill** — it's the mana build weapon. The 0.5 skill
scaling means it doesn't benefit much from skill stacking; its power comes from raw base
damage. The +mana deepens the pool for channeled spells (Laser, Barrier, Charge Blast).
Staff users stack mana gear (Robe, Hood) to fuel sustained channels, not skill gear to boost
per-hit damage. A methodical weapon for players who deal damage through channeled spells.

### Rune — the tank weapon

| Tier | Base dmg | Skill scaling | Mana cost | Fire rate | Special | +HP |
|------|----------|---------------|-----------|-----------|---------|-----|
| Rune | 6 | 1.0 | 2 | 2.0 | Shotgun homing to nearest | +5 |
| Good | 9 | 1.0 | 3 | 2.0 | Homing to nearest | +15 |
| Better | 15 | 1.0 | 4 | 2.0 | Homing to nearest | +30 |
| Even Better | 21 | 1.0 | 5 | 2.0 | Homing to nearest | +50 |
| Ultimate | 30 | 1.0 | 6 | 2.0 | Homing to nearest | +80 |

**Identity:** Shotgun burst that auto-targets the nearest enemy, very slow fire rate (every 2
seconds), low per-bullet damage but multiple projectiles. The defining feature: **it's the only
weapon that gives +HP**. The rune is the survivability weapon — you trade DPS for durability.
Short range (4) and high variability (35) mean it's unreliable at distance but devastating up
close. The base tier fires a shotgun pattern; higher tiers switch to homing. Pairs naturally
with robes (HP/mana gear) for a tanky build.

### Weapon balance observations

- **Each weapon gives a different stat.** Wand gives +skill (burst offense), Staff gives +mana
  (sustained offense via channels), Rune gives +HP (survivability). The weapon choice defines
  the build path.

- **Wand is mana-efficient, staff is mana-hungry, rune is burst-dependent.** This creates three
  different Focus rhythms. Wand users Focus rarely but briefly. Staff users channel then Focus
  to refill. Rune users dump mana in bursts then Focus for extended periods.

- **The "shotgun with random bullets?" note on the rune** suggests the designer is considering
  whether the rune's spread should be radial (ring pattern, like the current test weapon) or
  randomized (actual shotgun cone). Random spread would feel more chaotic and fit the "tank
  who doesn't aim precisely" identity.

---

## Equipment — hats and robes

### Hats — offensive stats (3 families × 5 tiers)

| Family | Primary stat | Secondary stat | Identity |
|--------|-------------|----------------|----------|
| Hat | Skill (10→150) | — | Pure damage. Glass cannon. |
| Headband | Skill (7→120) | Speed (5→50) | Damage + mobility. Aggressive kiting. |
| Hood | Skill (7→120) | HP + Mana (3/3→30/30) | Damage + survivability. Balanced offense. |

Hats are the offensive slot. Every hat gives skill (the damage stat). The choice is whether
you want pure damage (hat), damage + mobility (headband), or damage + durability (hood).

### Robes — defensive stats (3 families × 5 tiers)

| Family | Primary stat | Secondary stat | Identity |
|--------|-------------|----------------|----------|
| Mantle | HP (10→130) | Mana (0→50) | Tank. Absorb hits. |
| Robe | Mana (10→130) | HP (0→50) | Caster / Channeler. Fuel for channels and spells. |
| Vesture | HP + Mana (5/5→50/50) | Skill + Speed (0/0→40/15) | Generalist. A bit of everything. |

Robes are the defensive/utility slot. The original design notes suggested this split and the
balance sheet confirms it: **hat = offense, robe = defense/utility**. The Vesture is the
interesting outlier — it's the only robe that gives offensive stats, creating a "jack of all
trades" build option.

### Build archetypes that emerge

The weapon choice defines the build path — each weapon gives a different stat:

| Build | Weapon (+stat) | Hat | Robe | Playstyle |
|-------|---------------|-----|------|-----------|
| Glass cannon | Wand (+skill) | Hat | Robe | Max skill. Burst damage via instant spells. |
| Kite mage | Wand (+skill) | Headband | Vesture | High speed + skill. Fire while running. |
| Channeler | Staff (+mana) | Hood | Robe | Max mana. Sustained damage via Laser/Barrier. |
| Tank | Rune (+HP) | Hood | Mantle | Max HP. Survive up close. Barrier converts HP to mana. |
| Hybrid | Any | Hood | Vesture | Balanced stats. Can use both instant and channeled spells. |

The three core builds (glass cannon, channeler, tank) are defined by their weapon and offensive
stat (skill vs. mana vs. neither). Utility (speed, Blink, Haste) benefits all builds equally.

---

## Enemy design — four archetypes

The balance sheet defines 4 enemy types that cover different threat profiles:

| Enemy | HP | Speed | Behavior | Attack |
|-------|----|-------|----------|--------|
| Skitter | 15 | 80 | Rush in, attack briefly, rush out, repeat | Fast single hit |
| Small Demon | 20 | 60 | Detect → chase → attack in range | Single melee |
| Husk | 50 | 40 | Detect → chase → attack in range | AoE when close, single when far |
| Ranger | 30 | 20 | Detect → follow → attack in range | Single ranged |

### How they interact with Focus

- **Skitter** is the Focus punisher. At 80 speed (matching the player), it rushes in fast,
  hits, and retreats. You cannot safely Focus while a Skitter is active — it will reach you.
  Low HP (15) means it dies fast if you can hit it, but its hit-and-run pattern makes it hard
  to track. Forces reactive play.

- **Small Demon** is the baseline threat. At 60 speed it's fast enough to pressure you but
  slower than the player. You can kite it, but not ignore it. Creates the basic tension: Focus
  when it's far away, move when it's close.

- **Husk** is the mana tax. 50 HP means it takes many shots to kill, draining your mana.
  Its dual attack (AoE close, single far) means there's no safe distance — you take damage
  either way. Forces you to Focus more just to have enough mana to bring it down.

- **Ranger** is the positioning threat. Slow (20 speed) but ranged — it fires at you from
  a distance. You can't just run away and Focus because the Ranger hits you from afar. You
  have to either close distance to kill it quickly or find cover. Makes room geometry matter.

Together, these four enemies prevent any single strategy from dominating. Kiting doesn't work
against Skitters and Rangers. Standing still doesn't work against anything. Spell-spamming
runs you out of mana against Husks. The player has to adapt.

### Compared to current prototype

The prototype's SmallDemon has 100 HP and 16 speed — very different from the sheet's 20 HP
and 60 speed. The sheet version is faster but much squishier, which is better design: enemies
should be threatening because they're aggressive, not because they're HP sponges.

---

## Stat system — how the numbers work

Four stats drive all combat math:

| Stat | Base | Role |
|------|------|------|
| Skill | 10 | Burst offense: `base_damage + skill × skill_scaling` |
| Max Mana | 30 | Sustained offense (channel duration) + sustain (shots before Focus) |
| Max HP | 100 | Passive defense: survive hits |
| Speed | 80 | Active defense: outrun threats |

All equipment modifiers are flat additions. There are no percentage bonuses, no diminishing
returns, and no negative modifiers (no item gives -stat).

### Two offensive paths

- **Skill** scales instant spells (Fireball: 2-4 scaling, Meteor: 3-5) and weapons (Wand: 1.0).
  Stacking skill makes each hit harder. The glass cannon's offensive stat.
- **Mana** scales channeled spells by duration. Laser (0.2-0.5 scaling, 15-40 base damage/tick)
  doesn't need skill to hit hard — it needs mana to keep running. The channeler's offensive stat.

This split means skill gear and mana gear serve different builds, creating a real choice.

### Stat scaling at different tiers

A max-skill build (glass cannon):
- Ultimate Hat (+150 skill) + Ultimate Wand (+40 skill) = +190 skill
- Total skill: 10 + 190 = 200
- Wand damage: `60 + 200 × 1.0 = 260` per shot

A max-mana build (channeler):
- Ultimate Staff (+35 mana) + Ultimate Robe (+130 mana) + Ultimate Hood (+30 mana) = +195 mana
- Total mana: 30 + 195 = 225
- Laser 2 channel time: 225 ÷ 10/sec = 22.5 seconds at 64 DPS = 1440 total damage

A max-HP build (tank):
- Ultimate Rune (+80 HP) + Ultimate Hood (+30 HP) + Ultimate Mantle (+130 HP) = +240 HP
- Total HP: 100 + 240 = 340

### Observations

- **No negative trade-offs on items.** Every item is a pure upgrade over having nothing. The
  "build choice" is about opportunity cost (which stats you don't boost), not accepting
  downsides. Simpler but less interesting than items with costs.

- **Weapon choice defines build path.** Wand (+skill) → glass cannon, Staff (+mana) →
  channeler, Rune (+HP) → tank. This is the primary build-defining decision.

- **The 5-tier structure implies progression.** Items go from basic → good → better → even
  better → ultimate. This suggests either a loot drop system (roguelike: find better items
  as you go deeper) or a crafting/upgrade system. The tier names are placeholder-y, so the
  progression mechanic is still open.

---

## World structure — decided

The game has a persistent overworld with procedurally generated dungeons branching off it.

### Overworld

A procedurally generated open world with roaming enemies and dungeon entrances. The overworld
serves as the connective tissue — you explore, fight, gear up from drops, and choose which
dungeon to enter next. Enemies in the overworld provide a baseline challenge and item drops
to prepare for dungeons.

### Dungeons

Each dungeon entrance leads to a multi-room instanced dungeon. Key properties:

- **Procedurally generated.** Room layouts, enemy placement, and loot are generated per dungeon.
- **Enemies are pre-placed** in rooms (not spawned in waves). You enter a room, see what you're
  up against, and plan your approach. This makes room geometry and enemy composition part of
  the puzzle — you can assess the threat before engaging.
- **One or more floors.** Deeper floors are harder. Longer dungeons have more floors and tougher
  compositions.
- **Each dungeon favors a different playstyle.** A dungeon heavy on Skitters and tight corridors
  punishes Channelers who need to stand still. A dungeon with Rangers and open rooms punishes
  Kite Mages who rely on distance. This encourages build flexibility — either adapt your spell
  loadout per dungeon, or build a hybrid that can handle anything.
- **Dungeon boss** guards the exit. The boss is the final challenge of the dungeon. You can
  always leave the dungeon (retreat), but you only get the reward by beating the boss.
- **Badge reward.** Completing a dungeon (beating its boss) awards a badge. Badges are the
  progression currency — collect all badges to unlock the final boss.

### Progression loop

1. Explore the overworld, fight enemies, collect drops.
2. Enter a dungeon, fight through pre-placed rooms across one or more floors.
3. Beat the dungeon boss, earn a badge.
4. Return to the overworld, gear up, enter the next dungeon.
5. Collect all badges → unlock and fight the final boss.

This gives the game a clear win condition (beat all dungeons, beat the final boss) while
keeping the moment-to-moment gameplay open and exploratory.

---

## Item drops — decided

Enemies drop items based on their toughness. Every enemy can drop any item, but the drop tier
is weighted toward the enemy's power level.

### How it works

- **Drop chance scales with enemy toughness.** A Skitter (15 HP, fast but fragile) has a lower
  drop chance than a Husk (50 HP, tanky). Dungeon bosses have guaranteed or near-guaranteed
  drops.
- **Drop tier matches enemy level.** Enemies have an implicit power level (based on the dungeon
  or overworld zone). Drops are weighted toward items close to that level. A tier-3 enemy
  mostly drops tier-2 to tier-4 items, rarely tier-1 or tier-5. This means you naturally find
  better gear as you face tougher enemies.
- **Any item from any enemy.** There are no enemy-specific loot tables. A Skitter can drop a
  Rune, a Ranger can drop a Hat. This keeps drops surprising and prevents farming a specific
  enemy type for a specific item. The constraint is tier, not type.

### How this interacts with builds

- **Early game:** Low-tier enemies drop low-tier items. You work with what you find — your
  build emerges from your drops, not from a plan.
- **Mid game:** As you clear dungeons and face tougher enemies, drops improve. You start making
  deliberate build choices — do I keep this Better Wand or swap to the Better Staff I just
  found?
- **Late game:** Overworld enemies near endgame dungeons and dungeon bosses drop high-tier
  items. By this point you're committed to a build and looking for upgrades within your chosen
  path.

Spell drops follow the same rules — any enemy can drop any spell, tier-weighted to the enemy's
level. With 16 spell families and 4 slots, finding a new spell is always a decision: equip it
now, or keep what you have?

---

## Open design questions (updated)

Resolved since last revision: spell scaling split (instant vs. channeled), Staff identity
(+mana), incomplete spell numbers, world structure (overworld + dungeons), item drop system
(toughness-based, tier-weighted), win condition (all badges → final boss).

What remains:

1. **How many dungeons?** The badge system needs a defined count. More dungeons = longer game,
   more playstyle variety required, more content to generate. Too few and the final boss comes
   too fast.

2. **What differentiates each dungeon's playstyle?** Enemy composition is one axis (more
   Skitters vs. more Rangers). Room geometry is another (tight corridors vs. open arenas).
   Environmental hazards? Elemental themes? The dungeons need clear identities.

3. **What makes Focus risky?** The Skitter is the design answer, but room geometry matters
   too. Open rooms make Focus easy (run away, Focus at range). Tight rooms with obstacles
   make Focus a real gamble. Room design should serve Focus tension.

4. **How does the overworld scale?** Do overworld enemies get tougher as you collect badges?
   Or is the overworld a fixed difficulty and dungeons provide the scaling? If overworld
   enemies don't scale, the overworld becomes trivial once you're geared.

5. **Boss design.** Dungeon bosses and the final boss need distinct mechanics. Are bosses
   scaled-up versions of existing enemy types, or unique encounters with special attacks?

6. **Death penalty.** What happens when you die? Lose all items (roguelike)? Respawn at
   dungeon entrance (ARPG)? Lose the current dungeon run but keep overworld progress?
   The answer determines how punishing the game is and how much build commitment matters.
