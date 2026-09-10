extends Node
## Headless tests for the tip signs (SignLinks). Asserts:
##   - Determinism: the same seed deals the same signs into the same rooms, on the same tiles.
##   - Coverage: every biome listing signs has an empty room per sign, every one of its empty rooms
##     holds a sign, and every listed sign stands at least once; a pointing sign points at a room
##     of its type.
##   - Placement: signs stand only in empty rooms (no enemies, no features, never the spawn), one
##     to a room, alone, on the room's centre tile.
##   - Reveal: a sign naming a room type points at that room on a per-room copy, leaving the
##     authored resource untouched; a type absent from the world points nowhere.
##   - Map: a revealed boss room carries exactly one boss marker — discovering the room doesn't
##     double it, a save round trip keeps it, the room stays fogged — and reading the sign is what
##     reveals it. Every BOSS_TYPES id names a real room type, and discovering a boss room marks it.
##   - Copy: every biome sign fits the screen and uses only glyphs m3x6 has.
## Run: godot --headless --path game res://tests/worldgen/test_signs.tscn

const SEEDS := 20
const SIGN_SCENE := preload("res://worldgen/runtime/under_construction_sign.tscn")
const BOSS_ROOM := &"deepwood_boss_gnarlking"


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")

	var dealt_total := 0
	for i in SEEDS:
		var seed_v := 15_485_863 * i + 7
		var streamer := _streamer(config, seed_v)
		var links := streamer.sign_links()
		if _dealt(streamer) != _dealt(_streamer(config, seed_v)):
			fails.append("signs not deterministic (seed %d)" % seed_v)

		# --- Coverage: every empty room holds a sign, every sign stands somewhere ------------------
		for p in streamer.world_spec.placements:
			var biome := config.biome_by_id(p.id)
			if biome.signs.is_empty():
				continue
			var empty := SignLinks.empty_rooms(streamer.biome_graph(p.id), biome, config)
			if empty.size() < biome.signs.size():
				fails.append("biome %s has %d empty rooms for %d signs (seed %d)"
						% [p.id, empty.size(), biome.signs.size(), seed_v])
			var seen: Dictionary = {}
			for room: RoomSpec in empty:
				var tip := links.sign_at(room.origin_slot)
				if tip == null:
					fails.append("empty room %s in %s holds no sign (seed %d)"
							% [room.origin_slot, p.id, seed_v])
					continue
				seen[tip.message] = true   # by message: a pointing sign is dealt as a copy
				if tip.reveal_room_type != &"":
					var target: RoomSpec = _spec_at(streamer, tip.reveal_slot) \
							if tip.reveal_slot != Vector2i.MAX else null
					if target == null or target.origin_slot != tip.reveal_slot \
							or target.type_id != tip.reveal_room_type:
						fails.append("\"%s\" points at %s, not a %s room (seed %d)"
								% [tip.message.split("\n")[0], tip.reveal_slot,
								tip.reveal_room_type, seed_v])
			for tip in biome.signs:
				if not seen.has(tip.message):
					fails.append("biome %s never shows \"%s\" (seed %d)"
							% [p.id, tip.message.split("\n")[0], seed_v])
			dealt_total += empty.size()

		# --- Placement: empty rooms only, one sign each, alone, on the centre --------------------
		for slot in links.slots():
			var spec := _spec_at(streamer, slot)
			var rt := config.room_type_by_id(spec.type_id)
			if not SignLinks.is_empty_room(rt) \
					or spec.type_id == config.biome_by_id(spec.biome_id).spawn_room_type:
				fails.append("sign in non-empty room %s (seed %d)" % [spec.type_id, seed_v])
			var out := streamer.get_room_output(spec)
			var tiles: Array[Vector2i] = []
			for sp in out.spawns:
				if sp.get("feature_data") is SignDef:
					tiles.append(sp["tile"])
				else:
					fails.append("sign room %s also holds %s (seed %d)"
							% [slot, sp.get("enemy_id", sp.get("feature")), seed_v])
			var centre := Population.feature_tile(out)
			if tiles.size() != 1 or tiles[0] != centre:
				fails.append("room %s has signs at %s, want one on its centre %s (seed %d)"
						% [slot, tiles, centre, seed_v])

	# --- Reveal resolution ---------------------------------------------------------------------
	const SEED_R := 7
	var world := _streamer(config, SEED_R)
	var boss := _room_of_type(world, BOSS_ROOM)
	if boss == null:
		fails.append("no %s room in seed %d" % [BOSS_ROOM, SEED_R])
	else:
		var deepwood := config.biome_by_id(&"deepwood")
		var authored := deepwood.signs
		var pointer := SignDef.new()
		pointer.message = "pointer"
		pointer.reveal_room_type = BOSS_ROOM
		var nowhere := SignDef.new()
		nowhere.message = "nowhere"
		nowhere.reveal_room_type = &"no_such_room"
		var with_pointers: Array[SignDef] = authored.duplicate()
		with_pointers.append(pointer)
		with_pointers.append(nowhere)
		deepwood.signs = with_pointers
		var links := SignLinks.build(world.world_spec, config, SEED_R, RoomGraph.new())
		deepwood.signs = authored
		var pointed := 0
		for slot in links.slots():
			for tip: SignDef in [links.sign_at(slot)]:
				if tip.message == "pointer":
					pointed += 1
					if tip == pointer:
						fails.append("reveal stamped the authored sign instead of a copy")
					if tip.reveal_slot != boss.origin_slot:
						fails.append("pointing sign reveals %s, boss room is %s"
								% [tip.reveal_slot, boss.origin_slot])
				elif tip.message == "nowhere" and tip.reveal_slot != Vector2i.MAX:
					fails.append("sign naming a missing room type reveals %s" % tip.reveal_slot)
		if pointed == 0:
			fails.append("the pointing sign was never dealt")
		if pointer.reveal_slot != Vector2i.MAX:
			fails.append("authored pointing sign was stamped with %s" % pointer.reveal_slot)

		# --- Map markers -------------------------------------------------------------------------
		var centre := _centre_tile(world, boss)
		var map := _map(world)
		if not map.reveal_boss(boss.origin_slot):
			fails.append("reveal_boss added no marker")
		if map.reveal_boss(boss.origin_slot):
			fails.append("a second reveal of the same room added another marker")
		if _boss_markers(map) != [centre]:
			fails.append("revealed boss markers %s, want [%s]" % [_boss_markers(map), centre])
		map.discover_at(centre)
		if _boss_markers(map) != [centre]:
			fails.append("discovering a revealed boss room left markers %s" % [_boss_markers(map)])
		var reloaded := _map(world)
		reloaded.restore(map.to_dict())
		if _boss_markers(reloaded) != [centre]:
			fails.append("save round trip left boss markers %s" % [_boss_markers(reloaded)])
		var unseen := _map(world)
		unseen.restore({"revealed": [boss.origin_slot]})
		if _boss_markers(unseen) != [centre] or unseen.is_tile_discovered(centre):
			fails.append("a restored reveal must be marked and still fogged")

		var live := _map(world)
		GlobalMap.active = live
		var post: UnderConstructionSign = SIGN_SCENE.instantiate()
		var tip := SignDef.new()
		tip.message = "A boss lives nearby."
		tip.reveal_slot = boss.origin_slot
		post.setup(tip)
		add_child(post)
		post._on_body_entered(null)
		if _boss_markers(live) != [centre]:
			fails.append("reading a pointing sign left boss markers %s" % [_boss_markers(live)])
		GlobalMap.active = null
		post.queue_free()

	var found := _map(world)
	var bosses := 0
	for p in world.world_spec.placements:
		for u in world.biome_graph(p.id).rooms:
			if u.type_id in MapState.BOSS_TYPES:
				bosses += 1
				found.discover_at(_centre_tile(world, u))
	if bosses == 0 or _boss_markers(found).size() != bosses:
		fails.append("discovered %d boss rooms, got %d boss markers"
				% [bosses, _boss_markers(found).size()])
	var dungeon: GenConfig = load("res://world_content/mycelium_gen_config.tres")
	for id in MapState.BOSS_TYPES:
		var known := config.room_type_by_id(id) != null or dungeon.room_type_by_id(id) != null
		for f in dungeon.floor_configs:
			known = known or f.room_type_by_id(id) != null
		if not known:
			fails.append("BOSS_TYPES names unknown room type %s" % id)

	fails.append_array(await _copy_fits(config))

	print("== signs ==")
	print("  %d seeds, %d signs dealt" % [SEEDS, dealt_total])
	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


## The sign label does not wrap, so every hand-broken line has to fit the 320x180 screen, and the
## box has to fit above the sign (see test_tutorial's _signs_fit for where those numbers come from).
## m3x6 lacks some glyphs, which render blank at the right width — only the font can catch those.
func _copy_fits(config: GenConfig) -> Array[String]:
	const VIEW_W := 320.0
	const MAX_LABEL_HEIGHT := 60.0
	var fails: Array[String] = []
	var seen: Dictionary = {}
	for biome in config.biomes:
		for tip in biome.signs:
			if seen.has(tip):
				continue
			seen[tip] = true
			var post: UnderConstructionSign = SIGN_SCENE.instantiate()
			post.setup(tip)
			add_child(post)
			await get_tree().process_frame
			var label: Label = post.get_node("Label")
			var box := label.get_minimum_size()
			var first: String = tip.message.split("\n")[0]
			if box.x > VIEW_W or box.y > MAX_LABEL_HEIGHT:
				fails.append("sign doesn't fit the screen (%.0fx%.0f): %s" % [box.x, box.y, first])
			var font := label.get_theme_font("font")
			for c in tip.message.length():
				var ch := tip.message.unicode_at(c)
				if ch != 10 and not font.has_char(ch):
					fails.append("m3x6 has no glyph for '%s' (U+%04X) in: %s" % [char(ch), ch, first])
			post.queue_free()
	return fails


func _streamer(config: GenConfig, seed_v: int) -> WorldStreamer:
	var s := WorldStreamer.new()
	s.config = config
	s.build_world(seed_v)
	return s


func _map(world: WorldStreamer) -> MapState:
	var m := MapState.new()
	m.setup(world, MapState.ZOOM_TILES_PER_PX)
	return m


## Plain slot -> [[message, tile], ...] Dictionary, so two worlds compare with ==.
func _dealt(streamer: WorldStreamer) -> Dictionary:
	var out := {}
	var links := streamer.sign_links()
	for slot in links.slots():
		var entries: Array = []
		for sp in streamer.get_room_output(_spec_at(streamer, slot)).spawns:
			if sp.get("feature_data") is SignDef:
				entries.append([sp["feature_data"].message, sp["tile"]])
		out[slot] = entries
	return out


func _spec_at(streamer: WorldStreamer, slot: Vector2i) -> RoomSpec:
	var ss := streamer.config.room_slot_tiles
	return streamer.room_spec_at_tile(slot.x * ss, slot.y * ss)


func _room_of_type(world: WorldStreamer, type_id: StringName) -> RoomSpec:
	for p in world.world_spec.placements:
		for u in world.biome_graph(p.id).rooms:
			if u.type_id == type_id:
				return u
	return null


## The tile MapState marks a boss room on: its centre, the same one a discovery marker uses.
func _centre_tile(world: WorldStreamer, spec: RoomSpec) -> Vector2i:
	var ss := world.config.room_slot_tiles
	var size := spec.size_slots * ss
	return spec.origin_slot * ss + Vector2i(size.x >> 1, size.y >> 1)


func _boss_markers(map: MapState) -> Array:
	var out: Array = []
	for m in map.markers:
		if m["kind"] == MapState.MARKER_BOSS:
			out.append(m["tile"])
	return out
