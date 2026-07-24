# Biomes

<!-- BEGIN GENERATED CATALOGUE -->
<!-- Generated from design/data/biomes.yaml by design/tools/build.py — do not edit by hand. -->

## Glade (T1/T2)

The opening biome, where the player learns the systems and fills out a first kit. Enemy density is low, variety is high, stakes are gentle. It has two sub-biomes: the starting glade, which is pure onboarding, and the veggie glade, which brings in the plant roster and its boss.

Player spawns with: **Fireball T1**, **Heal T1**, **Blam T1**.

Notation: `Nx` count, `+` means "together in the room", `-` separates the variations the generator may roll for that room (it picks one).

### Starting glade

Onboarding: single-enemy rooms first, small mixed groups by T2, then the biome's rare and boss at T3.

| Tier | Room | Enemy group variations |
|---|---|---|
| T0 | open | *(empty)* |
| T0 | scatter | *(empty)* |
| T1 | open | *(empty)* |
| T1 | scatter | 2x sproutling - 3x hopper - 2x hopper + 1x sproutling |
| T1 | open | 3x sproutling - 4x hopper - 2x sproutling + 2x hopper |
| T1 | blob | 2x sproutling + 2x wasp - 1x sproutling + 3x wasp |
| T1 | scatter | 1x dirt golem |
| T2 | scatter | *(empty)* |
| T2 | scatter | 3x wasp - 3x hopper - 2x hopper + 2x wasp |
| T2 | scatter | 2x mandrake - 1x mandrake + 2x hopper - 2x wasp + 2x sproutling |
| T2 | blob | 1x dirt golem + 2x wasp - 1x dirt golem + 2x hopper |
| T2 | open | 2x seedling + 2x wasp - 1x seedling + 1x dirt golem |
| T2 | open | 2x mandrake + 1x seedling - 2x mandrake + 2x sproutling |
| T3 | blob | 1x dirt golem + 2x wasp + 1x mandrake - 1x dirt golem + 2x mandrake + 1x seedling |
| T3 | open | 1x dirt golem + 2x hopper + 1x mandrake - 2x mandrake + 2x seedling |
| T3 | open | 1x viper *(rare)* |
| T3 | blob | 1x mandraker *(rare)* |
| T3 | boss | 1x fae |
| T3 | blob | door to deepwood *(unique)* |

Drops: Zaap T1, Pew T1, Nope T1, Bzzz T1, Ring T1, Fireball T2, Blam T2.

### Veggie glade

Brings in the plant roster: thornthrower and rosebud both show up from T1. Groups get denser and harder than the starting glade by T2. T3 keeps the shared rare pair (1x viper, 1x mandraker) and the biome boss.

Roster: thornthrower, rosebud, thornmess *(boss)*.

| Tier | Room | Enemy group variations |
|---|---|---|
| T0 | open | 2x sproutling - 3x hopper |
| T0 | scatter | 1x sproutling + 1x hopper - 2x hopper |
| T1 | open | 3x sproutling - 2x hopper + 1x thornthrower |
| T1 | scatter | 2x thornthrower - 3x sproutling - 1x thornthrower + 2x hopper |
| T1 | open | 2x rosebud - 2x thornthrower + 1x rosebud - 3x sproutling + 1x thornthrower |
| T1 | blob | 1x rosebud + 2x wasp - 2x thornthrower + 2x hopper |
| T1 | scatter | 1x dirt golem + 1x thornthrower |
| T2 | scatter | 4x thornthrower - 3x thornthrower + 1x rosebud |
| T2 | scatter | 2x rosebud + 2x wasp - 2x mandrake + 2x thornthrower |
| T2 | blob | 1x dirt golem + 3x thornthrower - 1x dirt golem + 2x rosebud |
| T2 | open | 2x seedling + 2x thornthrower - 2x rosebud + 1x dirt golem |
| T2 | open | 3x mandrake + 2x rosebud - 2x thornthrower + 2x seedling + 1x rosebud |
| T3 | blob | 1x dirt golem + 2x rosebud + 1x thornthrower + 1x mandrake - 1x dirt golem + 2x mandrake + 1x seedling |
| T3 | open | 2x thornthrower + 2x seedling + 1x rosebud - 1x dirt golem + 2x mandrake + 1x rosebud |
| T3 | open | 1x viper *(rare)* |
| T3 | blob | 1x mandraker *(rare)* |
| T3 | boss | 1x thornmess |
| T3 | blob | door to deepwood *(unique)* |

Drops: snipe T1, Ring T2, Jimmy T2.

### Glade drops

| Enemy | Items dropped |
|---|---|
| sproutling | pew t1, heal t1 |
| hopper | pew t1, heal t1 |
| wasp | bzzz t1, pew t1, zaap t1 |
| mandrake | blam t1 |
| seedling | ring t1, heal t1 |
| dirt golem | nope t1, ring t1 |
| thornthrower | snipe t1 |
| rosebud | ring t1, nope t1 |
| viper *(rare)* | blam t2 |
| mandraker *(rare)* | fireball t2, blam t2 |
| fae *(boss)* | blam t2, ring t2 |
| thornmess *(boss)* | jimmy t2, snipe t2, ring t2 |

<!-- END GENERATED CATALOGUE -->

---

# ideas

## Deepwood (T3)

The second biome, tuned to pressure long-range, squishy builds and push the player into close
quarters. Enemies have much more health and hit harder. Four sub-biomes in encounter order —
animal, mimic, insect, fungal — built over a shared pool of five deepwood natives that appears
in all four. Each sub-biome adds three commons, three rares (almost all variants of another
enemy) and its boss: 12 per sub-biome. Commons drop T2, rares guarantee T3, bosses drop their
T3 signatures.

Shared pool: moth, stalker, grimling, moss golem, snake.

Each sub-biome introduces at most three new mechanics; later ones reuse and combine earlier
ones (ledger in enemies.md). Spells introduced: Bwoom, ChargeDash, Thwomp, Halp, Blink, Oop,
Ploop, Zoing, Halo, Slurp, Fwoosh. Reserved for future T3 biomes: Kaboom, Krak, Brrr, Clang,
Chomp, Piercing Lights, Vroop, Beep Boop, Nyoom, Shing, Splay.

### Animal deepwood

Beasts that punish standing still: introduces the charge-dash and the burrow.

Roster: thornback, owl, mole, grimlord *(rare)*, razorback *(rare)*, great owl *(rare)*,
gnarlking *(boss)*.

Drops: ChargeDash T2, Bwoom T2, Thwomp T3, Halp T3.

### Mimic deepwood

Props with eyes: the disguise escalates, bursts relocate, and a log is a bomb. Introduces the
blink and self-detonation.

Roster: bramble stalker, shade, deadwood, elder stalker *(rare)*, umbra *(rare)*, adder
*(rare)*, mother tree *(boss)*.

Drops: Blink T2, Oop T2, Ploop T3, Fireball T3.

### Insect deepwood

Swarms and crawlers; the walls stop being safe. Introduces the wall crawl and the bullet
escort; detonation goes mobile.

Roster: longleg, beetle, ticktick, weaver *(rare)*, goliath *(rare)*, drone *(rare)*, hive
queen *(boss)*.

Drops: Snipe T2, Oop T2, Zoing T3, Halo T3, Bzzz T3.

### Fungal deepwood

The wood, rotting: they paint the floor, you contest it. Introduces spore clouds, split on
death, and the drain leech; recombines everything else.

Roster: sporespitter, leech, bloatcap, elder leech *(rare)*, rot golem *(rare)*, creeper mold
*(rare)*, rotmaw *(boss)*.

Drops: Fwoosh T2, Slurp T2, Slurp T3, Nope T3.

### Rooms

*(TBD — follow the glade recipe per sub-biome: single-mechanic showcases early, testing later,
mixed groups by depth, three rare rooms, a boss room, and a gate room to the next biome.)*

### Deepwood drops

The full per-enemy table lives in the enemies.md ideas section.

