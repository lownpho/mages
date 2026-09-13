class_name ChallengeCurveResource
extends Resource
## The global Challenge settings in challenge_curve.tres. There are no per-Biome overrides.

## Ordinary encounters per walkable tile. Each key is the Challenge a step begins at; its value holds
## until the next key. Key 0 is required.
@export var encounters_per_tile: Dictionary[int, float] = {}
## Distinct non-Filler enemy types per ordinary encounter, stepped like encounters_per_tile.
@export var types_per_encounter: Dictionary[int, int] = {}
## How far below the local Challenge a Teaching room fills its encounters.
@export_range(1, 10, 1, "or_greater") var teach_dip := 1
## Play time before a defeated ordinary enemy may respawn, when its chunk next streams in.
@export_range(0.0, 3600.0, 1.0, "or_greater", "suffix:s") var respawn_delay := 300.0
## Chance that a non-Teaching ordinary Room becomes a Breather.
@export_range(0.0, 1.0, 0.01) var breather_chance := 0.0
