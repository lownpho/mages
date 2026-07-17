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

## Deepwood (T2)

The second biome, tuned to pressure long-range, squishy builds and push the player into close
quarters. The payoff is a full T2 set, covered between the rare enemies
and the three bosses. Its rooms are placed by tier like the Glade, split across three
sub-biomes: animal, mimic, and insect.

### Animal deepwood

Roster: thornback, owl, grimling, mosshulk, grimlord *(rare)*, gnarlking *(boss)*.

Drops:
-

### Mimic deepwood

Roster: stalker, bramble stalker, shade, mirror sprite, snake, elder stalker *(rare)*, mother
tree *(boss)*.

### Insect deepwood

Roster: wasp, longleg, beetle, weaver *(rare)*, drone *(rare)*, hive queen *(boss)*.

### Rooms


### Deepwood drops

