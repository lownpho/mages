extends Resource
class_name LootTable

## A weighted list of candidate items. pick() returns exactly one, chosen by relative
## weight. Reuses LootDrop's `chance` as a relative weight, so values need not sum to 1 —
## an entry weighted 2.0 is twice as likely as one weighted 1.0.
@export var entries: Array[LootDrop] = []

func pick() -> ItemResource:
	var total := 0.0
	for e in entries:
		if e.item:
			total += e.chance
	if total <= 0.0:
		return null
	var roll := randf() * total
	for e in entries:
		if e.item:
			roll -= e.chance
			if roll < 0.0:
				return e.item
	return null
