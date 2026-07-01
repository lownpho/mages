extends Node2D
## A trail signpost placed by the specials pass (H5): one per graph-neighbour, sitting on the trail
## a few tiles out from the biome centre toward that neighbour. It has no interaction — it's pure
## wayfinding: it draws an arrow from itself toward the target biome's centre and labels that biome's
## id, so a player reading it knows which way (and to what) the trail leads. Direction is geometry
## only (target tile minus own position); no discovery/unlock state.

var _target_tile: Vector2i
var _target_id: StringName


## The streamer's contract: hand the sign its `&"sign"` payload ({target_id, target_tile}). Called
## after the node is positioned at its tile centre, so global_position is already the sign's world pos.
func setup(payload: Dictionary) -> void:
	_target_tile = payload.get("target_tile", Vector2i.ZERO)
	_target_id = payload.get("target_id", &"")
	var label := $Label as Label
	if label:
		label.text = String(_target_id)
	queue_redraw()


func _draw() -> void:
	var half := GameConstants.PX_PER_TILE / 2.0
	var target_world := Vector2(_target_tile * GameConstants.PX_PER_TILE) + Vector2.ONE * half
	var dir := (target_world - global_position)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	# Arrow: a shaft from the sign plus a filled arrowhead, in local space (origin = the sign tile).
	var length := 10.0
	var tip := dir * length
	draw_line(Vector2.ZERO, tip, Color.WHITE, 1.0)
	var perp := dir.orthogonal()
	var head := 3.0
	draw_colored_polygon(
		PackedVector2Array([tip, tip - dir * head + perp * head * 0.6, tip - dir * head - perp * head * 0.6]),
		Color.WHITE)
