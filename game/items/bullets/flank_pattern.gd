extends FirePattern
class_name FlankPattern

## Fires perpendicular to the aim — one bullet off each flank. The thornback drops
## these along its dash, base direction = the dash heading, so the bullets peel off
## sideways into a corridor the player has to clear.
func get_directions(direction: Vector2) -> Array[Vector2]:
	return [direction.rotated(PI / 2.0), direction.rotated(-PI / 2.0)]
