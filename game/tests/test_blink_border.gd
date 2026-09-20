extends Node
## Blink crosses tree lines, not Biome borders: a hop whose landing belongs to another Biome is
## refused, and a cast aimed across a border either lands back inside the Biome or doesn't happen.
## The way into a Biome is its Passage, or the Professor's portal for a sealed one. Run:
##   godot --headless --path game res://tests/test_blink_border.tscn

const BLINK := "res://characters/player/spells/blink/blink2.tres"

var _fails: Array[String] = []


func _ready() -> void:
	var spell: BlinkResource = load(BLINK)
	var hop := int(spell.distance_tiles)
	var graph := WorldFixture.small().graph(1)
	var restore := GlobalMap.active
	GlobalMap.active = MapState.new()
	GlobalMap.active.setup(graph, WorldFixture.interiors(graph))

	var pair := _border_pair(graph, hop)
	_check(not pair.is_empty(), "no Biome border %d tiles wide in the small World" % hop)
	if not pair.is_empty():
		var caster: Node2D = load("res://tests/support/stub_caster.gd").new()  # aims RIGHT
		add_child(caster)
		caster.global_position = _point(pair[0])
		var effect: Node2D = spell.effect_scene.instantiate()
		effect.setup(spell, caster)
		_check(not effect._clear(_point(pair[1])), "a landing in the next Biome was let through")
		_check(effect._clear(_point(pair[0])), "a landing where the caster stands was refused")

		# The whole cast: the retries fan out, so it may find an in-Biome spot or none at all —
		# either way the caster stays in the Biome it cast from.
		var before := graph.owner_at(pair[0]).plan.biome
		add_child(effect)
		await get_tree().process_frame
		var after := graph.owner_at(Vector2i((caster.global_position / GameConstants.PX_PER_TILE).floor()))
		_check(after != null and after.plan.biome == before,
				"the cast left %s for %s" % [before, after.plan.biome if after else &"nowhere"])
		caster.queue_free()

	GlobalMap.active = restore
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


func _point(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE


## The first tile owned by one Biome with a tile of another exactly a hop to its right; empty when
## the World holds no such pair.
func _border_pair(graph: WorldGraph, hop: int) -> Array[Vector2i]:
	var tiles := graph.plan.size * WorldPlan.CELL
	for y in tiles.y:
		for x in tiles.x - hop:
			var here := graph.owner_at(Vector2i(x, y))
			if here == null:
				continue
			var there := graph.owner_at(Vector2i(x + hop, y))
			if there != null and there.plan.biome != here.plan.biome:
				return [Vector2i(x, y), Vector2i(x + hop, y)]
	return []
