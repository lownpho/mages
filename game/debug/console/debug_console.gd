extends CanvasLayer
## Quake-style debug console, autoloaded in debug builds (self-frees in release exports).
## Toggle with ` (backtick) or F10. Works in any scene — the running game, the combat lab,
## the worldgen debug views. Type `help` for the command list.
##
## The console adapts to the window's content scaling: in the game (320x180 canvas_items
## stretch) it draws in game pixels; in the debug tools (scaling disabled) it scales itself
## up so the pixel font stays readable at native resolution.

const LOG_LINES := 10
const STATE_LABEL_GROUP := "debug_state_label"

var _root: PanelContainer
var _log: Label
var _input: LineEdit
var _lines: PackedStringArray = []
var _history: PackedStringArray = []
var _history_pos := -1
var _god := false
var _show_states := false
var _streamer: WorldStreamer = null


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The F3 damage overlay rides along here rather than being instanced in shipped
	# scenes: debug/* is excluded from exports, and a scene referencing an excluded
	# resource fails to load entirely.
	add_child(preload("res://debug/overlay/debug_overlay.tscn").instantiate())
	GlobalEvent.world_ready.connect(func(s: WorldStreamer) -> void: _streamer = s)
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.theme = load("res://gui/theme.tres")
	add_child(_root)
	var vbox := VBoxContainer.new()
	_root.add_child(vbox)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_log)
	_input = LineEdit.new()
	_input.placeholder_text = "help"
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_gui)
	vbox.add_child(_input)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_QUOTELEFT or key.keycode == KEY_F10:
		_toggle()
		get_viewport().set_input_as_handled()


func _input_event_history(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return false
	if key.keycode == KEY_UP and not _history.is_empty():
		_history_pos = clampi(_history_pos - 1, 0, _history.size() - 1)
		_input.text = _history[_history_pos]
		_input.caret_column = _input.text.length()
		return true
	if key.keycode == KEY_DOWN and _history_pos >= 0:
		_history_pos = mini(_history_pos + 1, _history.size())
		_input.text = _history[_history_pos] if _history_pos < _history.size() else ""
		_input.caret_column = _input.text.length()
		return true
	if key.keycode == KEY_ESCAPE:
		_toggle()
		return true
	return false


func _toggle() -> void:
	visible = not visible
	if visible:
		_fit_to_window()
		_input.grab_focus()
	else:
		_input.release_focus()


func _on_input_gui(event: InputEvent) -> void:
	if _input_event_history(event):
		_input.accept_event()


## Span the viewport in logical pixels — the window's own scaling (the game's 320x180 stretch,
## or a debug scene's content_scale_factor) already sizes those up on screen.
func _fit_to_window() -> void:
	_root.custom_minimum_size = Vector2(get_viewport().get_visible_rect().size.x, 0)


func _on_submitted(text: String) -> void:
	_input.clear()
	var line := text.strip_edges()
	if line == "":
		return
	_history.append(line)
	_history_pos = _history.size()
	_say("> " + line)
	_run(line)


func _say(msg: String) -> void:
	_lines.append(msg)
	while _lines.size() > LOG_LINES:
		_lines.remove_at(0)
	_log.text = "\n".join(_lines)


# --- Command dispatch -----------------------------------------------------------------------

func _run(line: String) -> void:
	var parts := line.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	match cmd:
		"help":
			_say("give/equip <item>  spawn <enemy> [n]  killall  clearenemies")
			_say("tp <x> <y>  pos  god [on|off]  heal  seed [n]  reload  fps  states")
			_say("warp <biome>  kit <biome>   (e.g. `kit glade` then `warp deepwood`)")
		"warp":
			_cmd_warp(args)
		"kit":
			_cmd_kit(args)
		"give":
			_cmd_give(args, false)
		"equip":
			_cmd_give(args, true)
		"spawn":
			_cmd_spawn(args)
		"killall":
			_cmd_killall(true)
		"clearenemies":
			_cmd_killall(false)
		"tp":
			_cmd_tp(args)
		"pos":
			_cmd_pos()
		"god":
			_cmd_god(args)
		"heal":
			_cmd_heal()
		"seed":
			_cmd_seed(args)
		"reload":
			_cmd_reload()
		"fps":
			_say("%d fps" % Engine.get_frames_per_second())
		"states":
			_cmd_states()
		_:
			_say("unknown command '%s' — try help" % cmd)


## The live player: the "player" group member that actually has stats (the worldgen debug
## flycam also sits in that group so streaming follows it, but it has no health).
func _player() -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if "health" in node:
			return node
	return null


func _cmd_give(args: PackedStringArray, equip: bool) -> void:
	if args.is_empty():
		_say("usage: %s <item name>" % ("equip" if equip else "give"))
		return
	var item := DebugContent.find_item(args[0])
	if item == null:
		_say("no unique item matches '%s'" % args[0])
		return
	# equip aims at the live line and ignores the one-tier-per-line rule (that is the
	# player-facing restriction); give takes the first slot anywhere that will have it.
	if equip:
		for i in GlobalInventory.LINE_SIZE:
			var slot := GlobalInventory.active_slot(i)
			if slot.item == null and slot.set_item(item):
				_say("equipped %s" % args[0])
				return
		_say("active line is full")
		return
	if GlobalInventory.slots.add_at_first_empty(item) != null:
		_say("stashed %s" % args[0])
	else:
		var p := _player()
		if p != null:
			GlobalEvent.loot_dropped.emit(item, p.global_position + Vector2(16, 0))
			_say("inventory full — dropped %s at your feet" % args[0])
		else:
			_say("inventory full and no player to drop at")


func _cmd_spawn(args: PackedStringArray) -> void:
	if args.is_empty():
		_say("usage: spawn <enemy id> [count]")
		return
	var scene := DebugContent.enemy_scene(StringName(args[0]))
	if scene == null:
		_say("no enemy scene for '%s'" % args[0])
		return
	var p := _player()
	if p == null:
		_say("no player in scene")
		return
	var count := maxi(1, args[1].to_int()) if args.size() > 1 else 1
	for i in count:
		var e: Node2D = scene.instantiate()
		var ang := TAU * i / count
		e.global_position = p.global_position + Vector2.RIGHT.rotated(ang) * 4.0 \
				* GameConstants.PX_PER_TILE
		p.get_parent().add_child(e)
	_say("spawned %d %s" % [count, args[0]])


func _cmd_killall(kill: bool) -> void:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if kill and e.has_method("die"):
			e.die()
		else:
			e.queue_free()
		n += 1
	_say("%s %d enemies" % ["killed" if kill else "cleared", n])


func _cmd_tp(args: PackedStringArray) -> void:
	if args.size() < 2:
		_say("usage: tp <tile x> <tile y>")
		return
	var p := _player()
	if p == null:
		_say("no player in scene")
		return
	p.global_position = (Vector2(args[0].to_int(), args[1].to_int()) + Vector2(0.5, 0.5)) \
			* GameConstants.PX_PER_TILE
	_say("teleported to tile %s,%s" % [args[0], args[1]])


## Drop the player at another biome's spawn room, so content that sits several biomes in
## can be playtested straight away. Streaming follows the player, so no walking needed.
func _cmd_warp(args: PackedStringArray) -> void:
	var p := _player()
	if args.is_empty() or p == null or _streamer == null:
		_say("usage: warp <biome id> — in a streamed world")
		return
	if _streamer.world_spec.placement_for(StringName(args[0])) == null:
		_say("biome '%s' is not in this world" % args[0])
		return
	p.global_position = _streamer.find_spawn_position(StringName(args[0]))
	p.grant_spawn_grace()
	_say("warped to %s" % args[0])


## Hand over everything a biome's enemies drop — highest tier per spell — so the biome after
## it can be playtested without farming it first. Takes a bestiary page label (the biome id,
## or its family where sub-biomes merge): `kit glade` is the whole glade reward pool.
func _cmd_kit(args: PackedStringArray) -> void:
	if args.is_empty():
		_say("usage: kit <biome or family> — e.g. kit glade")
		return
	var best: Dictionary = {}   # spell family -> the highest tier of it that drops here
	for page in GlobalBestiary.pages():
		if String(page["biome"]) != args[0]:
			continue
		for id in page["ids"]:
			for drop in GlobalBestiary.load_data(id).drops:
				if drop.item == null:
					continue
				var fam := GlobalInventory.spell_family(drop.item)
				var have: ItemResource = best.get(fam)
				if have == null or have.resource_path < drop.item.resource_path:
					best[fam] = drop.item
	if best.is_empty():
		_say("nothing drops in '%s'" % args[0])
		return
	# One tier per spell already, so can_equip has nothing to say.
	var slots: Array = GlobalInventory.slots.slots
	var families := best.keys()
	families.sort()
	var n := 0
	for fam in families:
		for slot in slots:
			if slot.item == null and slot.set_item(best[fam]):
				n += 1
				break
	_say("granted %d/%d %s spells" % [n, families.size(), args[0]])


func _cmd_pos() -> void:
	var p := _player()
	if p == null:
		_say("no player in scene")
		return
	var t: Vector2 = (p.global_position / GameConstants.PX_PER_TILE).floor()
	_say("tile %d,%d   px %.0f,%.0f" % [int(t.x), int(t.y), p.global_position.x, p.global_position.y])


func _cmd_god(args: PackedStringArray) -> void:
	var p := _player()
	if p == null or not p.has_method("grant_spawn_grace"):
		_say("no player in scene")
		return
	_god = args[0] == "on" if not args.is_empty() else not _god
	p.grant_spawn_grace(1e9 if _god else 0.0)
	_say("god %s" % ("on" if _god else "off"))


func _cmd_heal() -> void:
	var p := _player()
	if p == null:
		_say("no player in scene")
		return
	p.health = p.max_health
	GlobalEvent.player_health_changed.emit(p.health)
	_say("healed to %d" % p.health)


func _cmd_seed(args: PackedStringArray) -> void:
	if args.is_empty():
		_say("active seed: %d" % GameState.active_seed)
		return
	GameState.active_seed = args[0].to_int()
	_say("active seed set to %d (applies on next world load)" % GameState.active_seed)


## Live FSM state name floating over every enemy's head. Labels are parented to the
## creature so they follow it and die with it; toggling off frees the ones alive now.
func _cmd_states() -> void:
	_show_states = not _show_states
	if not _show_states:
		for lbl in get_tree().get_nodes_in_group(STATE_LABEL_GROUP):
			lbl.queue_free()
	_say("state labels %s" % ("on" if _show_states else "off"))


func _process(_delta: float) -> void:
	if not _show_states:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if not "fsm" in e or e.fsm == null:
			continue
		var lbl := e.get_node_or_null(STATE_LABEL_GROUP) as Label
		if lbl == null:
			lbl = Label.new()
			lbl.name = STATE_LABEL_GROUP
			lbl.theme = load("res://gui/theme.tres")
			lbl.z_index = 100
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			# ponytail: fixed offset — big creatures wear it low, size it off the sprite if that bites.
			lbl.position = Vector2(-32, -24)
			lbl.custom_minimum_size.x = 64
			lbl.add_to_group(STATE_LABEL_GROUP)
			e.add_child(lbl)
		lbl.text = e.fsm.current_state.name if e.fsm.current_state else "-"


func _cmd_reload() -> void:
	_say("reloaded %d slotted items from disk" % DebugContent.reload_slotted_items())
