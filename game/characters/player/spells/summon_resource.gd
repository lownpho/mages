extends SpellResource
class_name SummonResource

## Summon: spawns `count` minions in front of the caster that hunt enemies until their
## lifetime runs out. Each minion is a plain Creature flipped to the player's faction, and
## its whole attack rides minion_spell — what makes it Halp vs Bzzz is the minion scene
## (art + FSM) and these per-tier numbers, which summon_spawner injects.

## Sampled per minion, so one summon can call in a mixed knot (a boss's adds) as easily as
## a uniform fan. A single entry is the ordinary case.
@export var minion_scenes: Array[PackedScene] = []
@export var count: int = 3
## FAN lines them up abreast in front of the caster (the player's summons, which should
## arrive between them and what they're aiming at); RING places them evenly around it (a
## boss calling adds in on top of itself); QUEUE strings them out single-file behind it,
## for a retinue whose idle behaviour is to march in the caster's wake.
@export_enum("Fan", "Ring", "Queue") var spawn_pattern: int = 0
## Ring radius, queue spacing, and the distance in front the fan centres on.
@export var spawn_distance: float = 16.0
@export var minion_health: int = 8
## Seconds each minion survives before it expires.
@export var minion_lifetime: float = 15.0
## Stamped onto the minion's first empty Cast beat, and the cast every view of this spell
## reports. A minion that authors its own beats keeps them (see summon_spawner) — Poot and
## Blops name their plain rung here, which is exactly what they fire off coated floor.
@export var minion_spell: SpellResource
## The spritesheet for this tier. The minion scene authors the animation layout
## (regions/frames/durations, identical across a summon's tiers); the spawner swaps
## this texture onto it, so one minion scene serves tiers that look different
## (e.g. Jimmy's three sizes) without per-tier scenes.
@export var minion_sheet: Texture2D
