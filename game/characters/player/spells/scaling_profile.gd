extends Resource
class_name ScalingProfile

## A stat-scaled amount: base plus per-stat scaling, resolved from the caster's
## stats via compute(). The one primitive for stat-scaled numbers — a bullet's
## damage, a heal's restore, a blast's payload — held by composition wherever an
## effect resolves a number from the resource itself. Enemy casters leave the
## scalings at 0 (their skill/speed are 0 anyway) and just author base.

@export var base_damage: float = 0.0
@export var skill_scaling: float = 0.0
## Extra per point of caster *bonus* speed (speed above base_speed — an unequipped
## caster contributes 0), mirroring skill_scaling. 0 = no speed scaling.
@export var speed_scaling: float = 0.0
## Extra per point of caster defence (heal, Halo, …). 0 = none.
@export var defence_scaling: float = 0.0

# base plus per-stat scaling. speed/defence default to 0 so a skill-only caller
# (and enemy casts) are unaffected.
func compute(skill: int, speed: int = 0, defence: int = 0) -> int:
	return roundi(base_damage + skill * skill_scaling + speed * speed_scaling \
		+ defence * defence_scaling)
