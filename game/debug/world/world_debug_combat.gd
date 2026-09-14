class_name WorldDebugCombat
extends ScrollContainer
## The debug panel's Combat tab: god mode and stat overrides on the real player, an enemy palette
## for placing and removing enemies in the actual World, item equip/drop, and Kill all versus
## Clear. Placed enemies are ordinary scenes without generated keys, so they are never recorded as
## Run defeats; generated members killed here are. Nothing here spawns ordinary or Fixed encounters
## and nothing touches Run-save eligibility.

const SECTION := WorldDebugLayer.SECTION
## How close to a click an enemy must be for Remove to pick it.
const REMOVE_RADIUS := 4.0 * GameConstants.PX_PER_TILE
const OTHER_GROUP := &"other"

var host: Node2D
## The enemy id World clicks place, or &"" to teleport instead.
var selected_enemy := &""
var god := false

var _cheat_buff := ItemResource.new()
var _groups: Array = []
var _group_picker: OptionButton
var _enemy_grid: GridContainer
var _enemy_buttons: Dictionary[StringName, Button] = {}
var _selection_label: Label


func configure(world_host: Node2D) -> void:
	host = world_host
	name = "Combat"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	god = bool(DebugState.get_value(SECTION, "god", false))
	_cheat_buff.skill_modifier = int(DebugState.get_value(SECTION, "cheat_skill", 0))
	_cheat_buff.speed_modifier = int(DebugState.get_value(SECTION, "cheat_speed", 0))
	_cheat_buff.defence_modifier = int(DebugState.get_value(SECTION, "cheat_def", 0))
	_build()
	set_god(god)
	_apply_stats()


func set_god(on: bool) -> void:
	god = on
	DebugState.set_value(SECTION, "god", on)
	if host._player != null:
		host._player.grant_spawn_grace(1e9 if on else 0.0)


## Stat overrides ride the player's buff pipeline.
func set_stats(skill: int, speed: int, defence: int) -> void:
	_cheat_buff.skill_modifier = skill
	_cheat_buff.speed_modifier = speed
	_cheat_buff.defence_modifier = defence
	DebugState.set_value(SECTION, "cheat_skill", skill)
	DebugState.set_value(SECTION, "cheat_speed", speed)
	DebugState.set_value(SECTION, "cheat_def", defence)
	_apply_stats()


func select_enemy(id: StringName) -> void:
	selected_enemy = id
	_highlight()


func _highlight() -> void:
	for enemy_id in _enemy_buttons:
		_enemy_buttons[enemy_id].modulate = Color(1.0, 0.9, 0.3) if enemy_id == selected_enemy else Color.WHITE
	_selection_label.text = "click places %s · RMB removes" % selected_enemy if selected_enemy != &"" \
			else "click teleports · RMB removes"


func place_selected(world_position: Vector2) -> Node2D:
	var scene := DebugContent.enemy_scene(selected_enemy) if selected_enemy != &"" else null
	if scene == null:
		return null
	var enemy := scene.instantiate() as Node2D
	enemy.global_position = world_position
	host._entities.add_child(enemy)
	return enemy


func remove_nearest(world_position: Vector2) -> bool:
	var best: Node2D = null
	var best_distance := REMOVE_RADIUS * REMOVE_RADIUS
	for enemy: Node2D in get_tree().get_nodes_in_group("enemies"):
		var distance := enemy.global_position.distance_squared_to(world_position)
		if distance <= best_distance and not enemy.is_queued_for_deletion():
			best_distance = distance
			best = enemy
	if best != null:
		best.queue_free()
	return best != null


## Real deaths: drops, Bestiary counts and Run defeats, as if the player had killed each one.
func kill_all() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("die") and not enemy.is_queued_for_deletion():
			enemy.die()
			count += 1
	return count


## Silent removal: no drops, no Bestiary counts, no defeats. Generated members return when their
## chunk next streams in.
func clear_enemies() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_queued_for_deletion():
			enemy.queue_free()
			count += 1
	return count


func equip(item: ItemResource) -> void:
	GlobalInventory.add_at_first_empty(item)


func drop(item: ItemResource) -> void:
	GlobalEvent.loot_dropped.emit(item, host._player.global_position + Vector2(2 * GameConstants.PX_PER_TILE, 0))


func _apply_stats() -> void:
	if host._player != null:
		host._player.add_buff(_cheat_buff)


func _build() -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	var cheats := HBoxContainer.new()
	box.add_child(cheats)
	var god_check := CheckBox.new()
	god_check.text = "God"
	god_check.button_pressed = god
	god_check.toggled.connect(set_god)
	cheats.add_child(god_check)
	_button(cheats, "Kill all", kill_all)
	_button(cheats, "Clear", clear_enemies)
	var stats := GridContainer.new()
	stats.columns = 4
	box.add_child(stats)
	_stat(stats, "skl", func() -> int: return _cheat_buff.skill_modifier, func(value: int) -> void:
		set_stats(value, _cheat_buff.speed_modifier, _cheat_buff.defence_modifier))
	_stat(stats, "spd", func() -> int: return _cheat_buff.speed_modifier, func(value: int) -> void:
		set_stats(_cheat_buff.skill_modifier, value, _cheat_buff.defence_modifier))
	_stat(stats, "def", func() -> int: return _cheat_buff.defence_modifier, func(value: int) -> void:
		set_stats(_cheat_buff.skill_modifier, _cheat_buff.speed_modifier, value))
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_selection_label)
	_build_enemy_palette(box)
	_build_item_palette(box)
	select_enemy(&"")


## Enemies grouped by the Bestiary's Biome pages, so the palette files them where the World fields
## them; enemies no roster claims close the list.
func _build_enemy_palette(box: VBoxContainer) -> void:
	_groups = GlobalBestiary.pages().map(func(page: Dictionary) -> Dictionary:
		return {"label": page.biome, "ids": page.ids})
	var filed := GlobalBestiary.filed_ids()
	var other: Array[StringName] = []
	for id in DebugContent.scan_enemy_ids():
		if id != &"placeholder" and not filed.has(id):
			other.append(id)
	if not other.is_empty():
		_groups.append({"label": OTHER_GROUP, "ids": other})
	_group_picker = OptionButton.new()
	for group: Dictionary in _groups:
		_group_picker.add_item(String(group.label))
	_group_picker.item_selected.connect(_show_group)
	box.add_child(_group_picker)
	_enemy_grid = GridContainer.new()
	_enemy_grid.columns = 2
	box.add_child(_enemy_grid)
	_show_group(0)


func _show_group(index: int) -> void:
	for child in _enemy_grid.get_children():
		child.queue_free()
	_enemy_buttons.clear()
	if index >= _groups.size():
		return
	for id: StringName in _groups[index].ids:
		# Clicking the selected entry again deselects it, so World clicks teleport again.
		var button := _button(_enemy_grid, String(id), func() -> void:
			select_enemy(&"" if selected_enemy == id else id))
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 80
		_enemy_buttons[id] = button
	_highlight()


## LMB equips into the first free slot; RMB drops a real pickup beside the player.
func _build_item_palette(box: VBoxContainer) -> void:
	var items := DebugContent.scan_items()
	for category in items:
		var header := Label.new()
		header.text = "%s: LMB equip · RMB drop" % category
		header.modulate = Color(0.7, 0.85, 1.0)
		box.add_child(header)
		var grid := GridContainer.new()
		grid.columns = 9
		box.add_child(grid)
		for entry in items[category]:
			var item: ItemResource = entry.item
			var button := TextureButton.new()
			button.texture_normal = item.icon
			button.ignore_texture_size = true
			button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			button.custom_minimum_size = Vector2(16, 16)
			button.tooltip_text = entry.name
			button.pressed.connect(equip.bind(item))
			button.gui_input.connect(func(event: InputEvent) -> void:
				var click := event as InputEventMouseButton
				if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
					drop(item))
			grid.add_child(button)


func _stat(grid: GridContainer, title: String, current: Callable, changed: Callable) -> void:
	var label := Label.new()
	label.text = title
	grid.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -50
	spin.max_value = 200
	spin.value = current.call()
	spin.value_changed.connect(func(value: float) -> void: changed.call(int(value)))
	grid.add_child(spin)


func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
