extends SpellResource
class_name NyoomResource

@export_group("Nyoom")
## Seconds the speed buff lasts.
@export var duration: float = 10.0
## Speed gained per point of the caster's skill at cast time (the skill is
## spent — converted away — for the duration). 1.0 = a 1:1 trade.
@export var skill_to_speed_scaling: float = 1.0
