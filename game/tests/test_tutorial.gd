extends Node
## The tutorial floor's one real invariant: the rooms are strung on a SINGLE path, in
## PROGRESSION's order. The rooms and corridors are computed, not hand-painted, so a wrong pitch
## or a wider corridor could quietly let two non-consecutive rooms touch — which reads as a normal
## dungeon, just no longer a one-way tutorial.
##
## Checked at the shipped table length AND at lengths that leave a short final row, since
## PROGRESSION is the knob meant to be edited and a partial row is the case a serpentine can get
## wrong.
##
## Layout only: _room_rects/_carve touch no nodes, so the script runs bare, without booting the
## scene (which would spawn a player and the whole HUD for nothing).

const TutorialScript := preload("res://scenes/tutorial.gd")

const _NB4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _ready() -> void:
	var tut = TutorialScript.new()
	var fails := 0

	var shipped: Array[String] = TutorialScript.PROGRESSION
	# The entrance's message is INTRO_SIGN, standing at the spawn. Its PROGRESSION entry must
	# stay empty or the room gets a second sign stacked in the middle of it.
	fails += _expect("entrance carries no centre sign", shipped[0].is_empty())

	# The shipped length, plus the two that leave a short final row.
	for count in [shipped.size(), shipped.size() - 1, shipped.size() - 2]:
		fails += _single_path(tut._room_rects().slice(0, count), tut, count)

	# A tutorial entered from the title never calls GameState.new_game(), so the loadout arrives
	# empty and the starter kit on the floor is the ONLY way to arm the player. Drop it or move
	# it past the first fight and the sproutling becomes unkillable — which looks like a stuck
	# player, not a broken constant.
	fails += _expect("the starter kit is dropped", not TutorialScript.STARTER_SPELLS.is_empty())
	fails += _expect("spells are handed over before the first fight",
			TutorialScript.STARTER_ROOM < TutorialScript.FIRST_FIGHT_ROOM)

	fails += await _signs_fit(shipped)
	fails += await _writes_nothing()

	tut.free()
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## The tutorial is reachable from the title with a real run already saved, and it can be left
## three ways: its exit door, death (game_over), and the HUD's quit button. None of them may
## touch the save, its cloud mirror, or the bestiary.
##
## This has to use the player's ACTUAL save files to mean anything, so it snapshots both and puts
## them back exactly — including "did not exist", which has to go back to not existing. Nothing
## between the snapshot and the restore may early-return.
func _writes_nothing() -> int:
	var save_before := _snapshot(GameState.SAVE_PATH)
	var bestiary_before := _snapshot(GlobalBestiary.SAVE_PATH)
	var fails := 0

	# A run worth protecting: a save Continue would offer.
	var planted := ConfigFile.new()
	planted.set_value("world", "version", GameState.SAVE_VERSION)
	planted.set_value("world", "seed", 4242)
	planted.save(GameState.SAVE_PATH)
	var planted_bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	fails += _expect("planted save is Continue-able", GameState.has_save())

	var foe: CreatureResource = load("res://characters/enemies/sproutling/sproutling_data.tres")
	var kills_before := GlobalBestiary.kill_count(&"sproutling")

	var tut: Node = load("res://scenes/tutorial.tscn").instantiate()
	add_child(tut)
	await get_tree().process_frame
	fails += _expect("the tutorial raises the sandbox", GameState.sandbox)

	# The HUD quit button's write, and death's wipe.
	GameState.persist()
	fails += _expect("quit-to-title writes no save",
			FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == planted_bytes)
	GameState.clear_save()
	fails += _expect("death does not wipe the save", GameState.has_save()
			and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == planted_bytes)

	GlobalEvent.creature_died.emit(foe, Vector2.ZERO)
	fails += _expect("a tutorial kill files no bestiary entry",
			GlobalBestiary.kill_count(&"sproutling") == kills_before)

	tut.free()
	await get_tree().process_frame
	fails += _expect("leaving the tutorial lowers the sandbox", not GameState.sandbox)

	# ...and the guard is actually load-bearing: the same kill outside the sandbox does count.
	GlobalEvent.creature_died.emit(foe, Vector2.ZERO)
	fails += _expect("the same kill counts outside the sandbox",
			GlobalBestiary.kill_count(&"sproutling") == kills_before + 1)

	_restore(GameState.SAVE_PATH, save_before)
	_restore(GlobalBestiary.SAVE_PATH, bestiary_before)
	return fails


## {exists, bytes} — an absent file is not the same as an empty one, and has to be restored as
## absent or the next launch reads a corrupt save.
func _snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "bytes": PackedByteArray()}
	return {"exists": true, "bytes": FileAccess.get_file_as_bytes(path)}


func _restore(path: String, snap: Dictionary) -> void:
	if not snap["exists"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(snap["bytes"])
	f.close()


## Sign copy is what PROGRESSION exists to be edited for, and text that overruns doesn't fail —
## it just renders off the 320x180 screen. The sign's label does not wrap, so every hand-broken
## line has to fit on its own.
##
## Width is simply the viewport. Height is what's left above the sign: the label's bottom sits
## 15px above it (authored in under_construction_sign.tscn), the player can stand ~15px below it
## and still be inside its trigger radius, and the camera shows 90px above the player.
func _signs_fit(shipped: Array[String]) -> int:
	const VIEW := Vector2(320, 180)
	const MAX_LABEL_HEIGHT := 60.0
	var messages := shipped.duplicate()
	messages.append(TutorialScript.INTRO_SIGN)
	var fails := 0
	for message in messages:
		if message.is_empty():
			continue
		var marker: UnderConstructionSign = TutorialScript.SIGN_SCENE.instantiate()
		marker.message = message
		add_child(marker)
		await get_tree().process_frame
		var label: Label = marker.get_node("Label")
		var box: Vector2 = label.get_minimum_size()
		var first: String = message.split("\n")[0]
		fails += _expect("sign fits the screen (%.0fx%.0f): %s..." % [box.x, box.y, first.substr(0, 24)],
				box.x <= VIEW.x and box.y <= MAX_LABEL_HEIGHT)
		# m3x6 is a small pixel font with no em dash, no curly quotes and no ellipsis. A glyph it
		# lacks renders as a blank or a box at the right width, so the fit check above sails past
		# it — the only way to catch it is to ask the font.
		var font: Font = label.get_theme_font("font")
		for i in message.length():
			var ch: int = message.unicode_at(i)
			if ch == 10:
				continue
			fails += _expect("m3x6 has a glyph for '%s' (U+%04X) in: %s..." % [
					char(ch), ch, first.substr(0, 24)], font.has_char(ch))
		marker.queue_free()
	return fails


## Rooms are laid out from PROGRESSION's order, so a prefix of the rects is exactly the floor a
## shorter table would build — the one path from entrance to exit, and no other way across.
func _single_path(rooms: Array[Rect2i], tut, count: int) -> int:
	var walkable: Dictionary = tut._carve(rooms)
	var fails := 0
	fails += _expect("%d rooms: none overlap" % count, _no_overlap(rooms))
	# Whole floor is one region: every room is reachable from the entrance.
	fails += _expect("%d rooms: floor is connected" % count, _components(walkable).size() == 1)
	# ...and cutting the connectors leaves exactly one island per room, so the only way from
	# room N to room N+1 is that corridor. Any extra contact would show up as fewer islands.
	var rooms_only := walkable.duplicate()
	for cell: Vector2i in walkable:
		if not _in_any(rooms, cell):
			rooms_only.erase(cell)
	fails += _expect("%d rooms: joined only by their corridors" % count,
			_components(rooms_only).size() == rooms.size())
	return fails


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
