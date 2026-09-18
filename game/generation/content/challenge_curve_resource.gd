class_name ChallengeCurveResource
extends Resource
## The global Challenge settings in challenge_curve.tres. There are no per-Biome overrides.

## Ordinary encounters per walkable tile. Each key is a Challenge the curve passes through; the
## density ramps linearly between neighbouring keys, so authored keys are corners, not cliffs.
## Key 0 is required, and Challenges past the last key hold its value.
@export var encounters_per_tile: Dictionary[int, float] = {}
## Distinct enemy types per ordinary encounter. A whole count, so this one steps: each key's value
## holds until the next key.
@export var types_per_encounter: Dictionary[int, int] = {}
## How far below the local Challenge a Teaching room fills its encounters.
@export_range(1, 10, 1, "or_greater") var teach_dip := 1
## Play time before a defeated ordinary enemy may respawn, when its chunk next streams in.
@export_range(0.0, 3600.0, 1.0, "or_greater", "suffix:s") var respawn_delay := 300.0


## The global density at Challenge, interpolated between the authored keys. Challenges below the
## first key or above the last take that key's value.
func encounter_density(challenge: int) -> float:
	var keys := encounters_per_tile.keys()
	if keys.is_empty():
		return 0.0
	keys.sort()
	var at := maxi(challenge, keys[0])
	var low: int = keys[0]
	for high: int in keys:
		if high > at:
			return lerpf(encounters_per_tile[low], encounters_per_tile[high],
					float(at - low) / float(high - low))
		low = high
	return encounters_per_tile[low]


## The active step at Challenge. Challenges below the first step use that first step, which is
## always the required zero step for valid content.
func encounter_types(challenge: int) -> int:
	var keys := types_per_encounter.keys()
	if keys.is_empty():
		return 0
	keys.sort()
	var value: int = types_per_encounter[keys[0]]
	for at: int in keys:
		if at > challenge:
			break
		value = types_per_encounter[at]
	return value
