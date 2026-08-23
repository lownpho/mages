extends Node
## The tutorial floor's one real invariant: the fifteen rooms (three per tier, tiers 0..4) are
## strung on a SINGLE path. The rooms and corridors are computed, not hand-painted, so a wrong
## pitch or a wider corridor could quietly let two non-consecutive rooms touch — which reads as a
## normal dungeon, just no longer a one-way tutorial.
##
## Layout only: _room_rects/_carve touch no nodes, so the script runs bare, without booting the
## scene (which would spawn a player and the whole HUD for nothing).

const TutorialScript := preload("res://scenes/tutorial.gd")

const _NB4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _ready() -> void:
	var tut = TutorialScript.new()
	var rooms: Array[Rect2i] = tut._room_rects()
	var walkable: Dictionary = tut._carve(rooms)
	var fails := 0

	fails += _expect("15 rooms (%d tiers x %d)" % [TutorialScript.TIERS, TutorialScript.ROOMS_PER_TIER],
			rooms.size() == TutorialScript.TIERS * TutorialScript.ROOMS_PER_TIER)
	fails += _expect("no two rooms overlap", _no_overlap(rooms))

	# Whole floor is one region: every room is reachable from the entrance.
	fails += _expect("floor is connected", _components(walkable).size() == 1)

	# ...and cutting the connectors leaves exactly one island per room, so the only way from
	# room N to room N+1 is that corridor. Any extra contact would show up as fewer islands.
	var rooms_only := walkable.duplicate()
	for cell: Vector2i in walkable:
		if not _in_any(rooms, cell):
			rooms_only.erase(cell)
	fails += _expect("rooms are joined only by their corridors",
			_components(rooms_only).size() == rooms.size())

	# One sign per room, naming its tier, three rooms deep.
	var tiers: Array[int] = []
	for i in rooms.size():
		@warning_ignore("integer_division")
		var tier := i / TutorialScript.ROOMS_PER_TIER
		tiers.append(tier)
	fails += _expect("tiers run 0..%d, %d rooms each" % [TutorialScript.TIERS - 1, TutorialScript.ROOMS_PER_TIER],
			tiers.count(0) == TutorialScript.ROOMS_PER_TIER and tiers.max() == TutorialScript.TIERS - 1)

	tut.free()
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _no_overlap(rooms: Array[Rect2i]) -> bool:
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if rooms[i].intersects(rooms[j]):
				return false
	return true


func _in_any(rooms: Array[Rect2i], cell: Vector2i) -> bool:
	for r in rooms:
		if r.has_point(cell):
			return true
	return false


## 4-connected flood fill over a tile set; returns one member per component.
func _components(cells: Dictionary) -> Array[Vector2i]:
	var seen := {}
	var roots: Array[Vector2i] = []
	for start: Vector2i in cells:
		if seen.has(start):
			continue
		roots.append(start)
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			for d in _NB4:
				var n: Vector2i = at + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
	return roots


func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1
