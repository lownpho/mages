extends SpellResource
class_name WhumfResource

## Whumf lays terrain, so its numbers are the field's: how much floor it covers and what
## the floor does. The clouds carry the rest (see SporeCloud).

@export_group("Whumf")
## Per cloud, per half second. Deliberately tiny — the clouds are ammunition, not a nuke,
## and a field you can stand your own turrets in can't be a damage button too.
@export var tick_damage: ScalingProfile
## What one cloud contributes when light sets the field off. Each victim takes this
## once however many clouds it is standing in, so the chain buys area, never a bigger hit.
@export var blast_damage: ScalingProfile
@export var cloud_lifetime: float = 12.0
