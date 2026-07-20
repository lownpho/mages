extends SpellResource
class_name SummonResource

## Summon: spawns `count` minions in front of the caster that hunt enemies until their
## lifetime runs out, splitting enemy aggro off the player. Each minion is a plain
## Creature flipped to the player's faction (target_groups / bullet layer authored on the
## minion scene), and its whole attack rides minion_spell, reusing the bullet-spell + bullet
## systems. The minion's damage lives on minion_spell's bullet. What makes it Halp vs Bzzz
## is the minion scene (art + FSM) and these numbers, not code. The spawner injects these
## per-tier values (see summon_spawner); the minion scene carries no per-tier data of its own.
##
## Caster scaling: the spawner stamps the caster's own stats (skill/speed/defence) onto each
## minion, so the minion fires exactly as if the player cast minion_spell — the minion
## bullet's own skill/speed/defence_scaling pick which stat grows it (Bzzz=speed,
## Jimmy=defence). No summon-specific damage math, no scaling selector.
@export var minion_scene: PackedScene
@export var count: int = 3
@export var minion_health: int = 8
## Seconds each minion survives before it expires.
@export var minion_lifetime: float = 15.0
@export var minion_spell: SpellResource
## The spritesheet for this tier. The minion scene authors the animation layout
## (regions/frames/durations, identical across a summon's tiers); the spawner swaps
## this texture onto it, so one minion scene serves tiers that look different
## (e.g. Jimmy's three sizes) without per-tier scenes.
@export var minion_sheet: Texture2D
