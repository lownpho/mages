class_name Encounters extends RefCounted
## The encounter pass every painter family shares (Group G): deterministic anchor tiles that
## each expand into one weighted EncounterTemplate — solitary / pack-of-N / mixed. Split from
## the painters so ground/cover/decor and enemy placement stay independent, and both
## ForestPainter and CavePainter get identical spawning by calling BiomePainter._spawn_encounters.
##
## Everything here is a pure function of (world_seed, anchor tile): the anchor test, the template
## pick, entry picks, the pack count, and the per-member scatter channels. So a discarded chunk
## rebuilds the SAME creatures at the SAME tiles, and no per-chunk RNG ever crosses a border. The
## decision (which scenes, where) is factored into `rolls_at` with NO instancing, so it can be
## asserted headlessly without loading heavy enemy scenes.
##
## Group H (rares) overrides specific anchors: an anchor tile is any `is_anchor(seed, x, y)` cell;
## to substitute a spawn there it can supply its own scene in place of `rolls_at`'s result for that
## tile — same anchor identity, no parallel spawn path.

# Fraction of eligible tiles that become an encounter anchor. Tuning dial — higher = denser
# encounters. ~0.003 keeps a ≈1500-tile biome populated but not swarmed.
const ANCHOR_DENSITY := 0.003

# Tiles around world origin kept encounter-free — the spawn pocket (mirrors ForestPainter.SPAWN_CLEAR).
const SPAWN_CLEAR := 8

# Independent hash channels — high numbers to stay clear of the painters' (0..4), areas' (50/51),
# and macro's (30/31) channels so decisions don't correlate with terrain.
const CH_ANCHOR := 60      # anchor coin flip
const CH_TEMPLATE := 61    # weighted template pick
const CH_COUNT := 62       # pack/mixed member count
const CH_ENTRY := 100      # entry pick; +member index so MIXED members pick independently
const CH_SCATTER_X := 200  # per-member scatter x; +member*2 so a pack fans out
const CH_SCATTER_Y := 201  # per-member scatter y; +member*2


## True iff this tile is an encounter anchor. Public so Group H can enumerate/override anchors.
static func is_anchor(world_seed: int, x: int, y: int) -> bool:
	return Hash.chance(world_seed, x, y, CH_ANCHOR, ANCHOR_DENSITY)


## The pure decision for one anchor: the ordered list of enemies it spawns, each as
## `{scene: PackedScene, ch_x: int, ch_y: int}` (the scatter channels feed ctx.scatter_pos).
## No instancing — the caller realizes the scenes. Empty when the area has no encounters.
static func rolls_at(area: Resource, cell: Vector2i, world_seed: int) -> Array:
	var out: Array = []
	if area == null or area.encounters.is_empty():
		return out

	var tmpl: EncounterTemplate = _pick_template(area.encounters, cell, world_seed)
	if tmpl == null or tmpl.entry_scenes.is_empty():
		return out

	match tmpl.kind:
		EncounterTemplate.Kind.SOLITARY:
			out.append(_member(_pick_entry(tmpl, cell, world_seed, 0), 0))
		EncounterTemplate.Kind.PACK:
			var n := Hash.range_i(world_seed, cell.x, cell.y, CH_COUNT, tmpl.count_min, tmpl.count_max)
			var scene: PackedScene = _pick_entry(tmpl, cell, world_seed, 0)  # ONE entry, N copies
			for i in n:
				out.append(_member(scene, i))
		EncounterTemplate.Kind.MIXED:
			var n := Hash.range_i(world_seed, cell.x, cell.y, CH_COUNT, tmpl.count_min, tmpl.count_max)
			for i in n:
				out.append(_member(_pick_entry(tmpl, cell, world_seed, i), i))  # each independent
	return out


## The EncounterTemplate an anchor rolls (or null when the area has none). Public so tests and
## Group H can introspect an anchor's decision without re-deriving the weighted pick.
static func picked_template(area: Resource, cell: Vector2i, world_seed: int) -> EncounterTemplate:
	if area == null or area.encounters.is_empty():
		return null
	return _pick_template(area.encounters, cell, world_seed)


static func _member(scene: PackedScene, index: int) -> Dictionary:
	return {"scene": scene, "ch_x": CH_SCATTER_X + index * 2, "ch_y": CH_SCATTER_Y + index * 2}


# Weighted template pick keyed on the anchor tile; falls back to uniform when all weights are unset.
static func _pick_template(encs: Array, cell: Vector2i, world_seed: int) -> EncounterTemplate:
	var total := 0.0
	for t in encs:
		total += maxf(t.weight, 0.0)
	var roll := Hash.value(world_seed, cell.x, cell.y, CH_TEMPLATE)
	if total <= 0.0:
		return encs[int(roll * encs.size()) % encs.size()]
	var r := roll * total
	for t in encs:
		r -= maxf(t.weight, 0.0)
		if r < 0.0:
			return t
	return encs[encs.size() - 1]


# Weighted entry pick; `member` gives each MIXED member its own independent channel.
static func _pick_entry(tmpl: EncounterTemplate, cell: Vector2i, world_seed: int, member: int) -> PackedScene:
	var scenes := tmpl.entry_scenes
	var weights := tmpl.entry_weights
	var roll := Hash.value(world_seed, cell.x, cell.y, CH_ENTRY + member)
	if weights.is_empty() or weights.size() != scenes.size():
		return scenes[int(roll * scenes.size()) % scenes.size()]
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return scenes[int(roll * scenes.size()) % scenes.size()]
	var r := roll * total
	for i in weights.size():
		r -= maxf(weights[i], 0.0)
		if r < 0.0:
			return scenes[i]
	return scenes[scenes.size() - 1]
