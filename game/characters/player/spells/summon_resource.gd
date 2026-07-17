extends SpellResource
class_name SummonResource

## Summon: spawns `count` minions in front of the caster that hunt enemies until their
## lifetime runs out, splitting enemy aggro off the player. Each minion is a plain
## Creature flipped to the player's faction (target_groups / bullet layer authored on the
## minion scene), and its whole attack rides minion_weapon, reusing the weapon + bullet
## systems. The SpellResource's own base_damage / skill_scaling are unused — the minion's
## damage lives on minion_weapon's bullet. What makes it Halp vs Bzzz is the minion scene
## (art + FSM) and these numbers, not code. The spawner injects these per-tier values
## (see summon_spawner); the minion scene carries no per-tier data of its own.
@export var minion_scene: PackedScene
@export var count: int = 3
@export var minion_health: int = 8
## Seconds each minion survives before it expires.
@export var minion_lifetime: float = 15.0
@export var minion_weapon: SpellResource
## The spritesheet for this tier. The minion scene authors the animation layout
## (regions/frames/durations, identical across a summon's tiers); the spawner swaps
## this texture onto it, so one minion scene serves tiers that look different
## (e.g. Jimmy's three sizes) without per-tier scenes.
@export var minion_sheet: Texture2D

@export_group("Scaling")
## Which of the caster's stats the minions' damage grows with (the summon's
## archetype scaling: Halp=health, Bzzz=speed, Jimmy=defence, Beep Boop=skill).
@export_enum("skill", "speed", "health", "defence") var scaling_stat: String = "skill"
## Flat damage added to each minion's bullet per point of scaling_stat at cast
## time. The spawner deep-copies the weapon before bumping it, so the shared
## resource is never mutated. 0 = minions don't scale with the caster.
@export var damage_per_stat: float = 0.0
