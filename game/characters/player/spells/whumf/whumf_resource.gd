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
## Clouds ringed around the caster; one more always lands under it, so 0 is a single
## patch — a puffcap popping where it stood rather than a field laid around a mage.
@export var ring_clouds: int = 6
## Radius of that ring, in tiles. Under twice a cloud's own reach or the ring reads as
## separate patches instead of one field.
@export var spread_tiles: float = 1.6
## The cast eats whoever made it: a mine IS its payload. The player's Whumf leaves them
## standing; a puffcap is gone the moment its spores are down.
@export var consumes_caster: bool = false
