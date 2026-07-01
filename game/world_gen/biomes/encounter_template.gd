class_name EncounterTemplate extends Resource
## One rollable enemy group for an encounter anchor. An anchor tile (Group G) picks a
## template by `weight`, then realizes it: SOLITARY = one enemy, PACK = N copies of a
## single picked entry, MIXED = N enemies each independently picked from `entries`. N is a
## hash-rolled count in [count_min, count_max]. Pure data — the spawning lives in Group G.
##
## `entries` is stored as two parallel arrays (scene + weight) so it needs no extra
## sub-resource type; keep them the same length (see `is_valid`).

enum Kind { SOLITARY, PACK, MIXED }

@export var kind: Kind = Kind.SOLITARY
@export var entry_scenes: Array[PackedScene] = []   ## the creatures this template can spawn
@export var entry_weights: Array[float] = []        ## relative pick weight per entry (parallel to entry_scenes)
@export_range(1, 20, 1, "or_greater") var count_min: int = 1
@export_range(1, 20, 1, "or_greater") var count_max: int = 1
@export_range(0.0, 10.0, 0.1, "or_greater") var weight: float = 1.0  ## chance this template is the one an anchor rolls


## Sum of entry weights (for weighted picks); falls back to entry count if all unset.
func total_entry_weight() -> float:
	var t := 0.0
	for w in entry_weights:
		t += w
	return t if t > 0.0 else float(entry_scenes.size())


## Data-integrity check used by the content test. Returns "" when valid, else the reason.
func why_invalid() -> String:
	if entry_scenes.is_empty():
		return "no entry_scenes"
	if not entry_weights.is_empty() and entry_weights.size() != entry_scenes.size():
		return "entry_weights length %d != entry_scenes length %d" % [entry_weights.size(), entry_scenes.size()]
	if count_min < 1 or count_max < count_min:
		return "bad count range [%d, %d]" % [count_min, count_max]
	if kind == Kind.SOLITARY and (count_min != 1 or count_max != 1):
		return "SOLITARY must have count 1..1"
	return ""
