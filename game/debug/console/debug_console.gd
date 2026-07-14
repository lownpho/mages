extends CanvasLayer
## Quake-style debug console, autoloaded in debug builds (self-frees in release exports).
## Toggle with ` (backtick) or F10. Works in any scene — the running game, the combat lab,
## the worldgen debug views. Type `help` for the command list.
##
## The console adapts to the window's content scaling: in the game (320x180 canvas_items
## stretch) it draws in game pixels; in the debug tools (scaling disabled) it scales itself
## up so the pixel font stays readable at native resolution.

const LOG_LINES := 10

var _root: PanelContainer
var _log: Label
var _input: LineEdit
var _lines: PackedStringArray = []
var _history: PackedStringArray = []
var _history_pos := -1
var _god := false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
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


## Size + scale the panel for the current window: game pixels when the window stretches
## canvas items, an integer upscale when content scaling is disabled (debug tools).
func _fit_to_window() -> void:
	var win := get_window()
	var s := 1.0
	var logical := Vector2(win.size)
	if win.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		s = maxf(1.0, floorf(win.size.x / 480.0))
		logical = Vector2(win.size) / s
	else:
		logical = Vector2(win.content_scale_size)
	transform = Transform2D().scaled(Vector2(s, s))
	_root.position = Vector2.ZERO
	_root.custom_minimum_size = Vector2(logical.x, 0)


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
			_say("tp <x> <y>  pos  god [on|off]  heal  seed [n]  reload  fps")
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
	if equip:
		var slot := GlobalInventory.get_equipment_slot_for_item(item)
		if slot != null and slot.set_item(item):
			_say("equipped %s" % args[0])
		else:
			_say("cannot equip %s" % args[0])
		return
	if GlobalInventory.bag_slots.add_at_first_empty(item) != null:
		_say("bagged %s" % args[0])
	else:
		var p := _player()
		if p != null:
			GlobalEvent.loot_dropped.emit(item, p.global_position + Vector2(16, 0))
			_say("bag full — dropped %s at your feet" % args[0])
		else:
			_say("bag full and no player to drop at")


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


func _cmd_reload() -> void:
	_say("reloaded %d slotted items from disk" % DebugContent.reload_slotted_items())
