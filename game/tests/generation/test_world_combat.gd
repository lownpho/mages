extends Node
## The integrated panel's Combat tab in the development World: paused clicks teleport without a
## palette entry and place with one, right clicks remove, closed-panel clicks are left to casting,
## fly is ignored by placed enemies, item equip/drop, god mode and stat overrides, and Kill all
## (real deaths with drops, Bestiary counts and Run defeats) versus Clear (silent). None of it
## touches Run-save eligibility. Run:
##   godot --headless --path game res://tests/generation/test_world_combat.tscn

const COMBAT_TAB := 2

var _fails: Array[String] = []


func _ready() -> void:
	var debug_state := {"world_debug": _snapshot_state("world_debug"), "combat_lab": _snapshot_state("combat_lab")}
	var real_bestiary := GlobalBestiary.to_dict()
	GlobalBestiary.restore({})
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	# Entering the World saves the Run; keep that off the player's save.
	GameState.save_path = "user://test_world_combat_save.cfg"
	var world: Node2D = load("res://generation/dev/walk_world.tscn").instantiate()
	world.world_seed = 7
	add_child(world)
	await get_tree().process_frame
	var layer: WorldDebugLayer = world._debug_layer
	_check(layer != null and layer._combat != null, "the debug layer has a Combat tab")
	if layer != null and layer._combat != null:
		await _test_clicks(world, layer)
		_test_items_and_cheats(world, layer._combat)
		await _test_kill_and_clear(world, layer._combat)
		_check(GameState.run_save_eligible, "Combat actions disabled Run saving")
		layer.set_panel_open(false)
	world.queue_free()
	await get_tree().process_frame
	GlobalInventory.reset()
	for section in debug_state:
		_restore_state(section, debug_state[section])
	GlobalBestiary.restore(real_bestiary)
	GlobalBestiary._save()
	DirAccess.remove_absolute(GameState.save_path)
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


func _click(layer: WorldDebugLayer, button: MouseButton, at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = true
	click.position = at
	layer._input(click)


func _world_tile(layer: WorldDebugLayer, at: Vector2) -> Vector2i:
	var point := layer.get_viewport().get_canvas_transform().affine_inverse() * at
	return Vector2i((point / GameConstants.PX_PER_TILE).floor())


func _placed(world: Node2D) -> Array[Node]:
	return world._entities.get_children().filter(func(node: Node) -> bool:
		return node.is_in_group("enemies") and not node.has_meta("generated_key") and not node.is_queued_for_deletion())


func _test_clicks(world: Node2D, layer: WorldDebugLayer) -> void:
	var combat := layer._combat
	var at := Vector2(layer._panel.size.x + 60, 90)
	# Closed, the panel leaves clicks to the player's casting.
	var start: Vector2 = world._player.global_position
	_click(layer, MOUSE_BUTTON_LEFT, at)
	_check(world._player.global_position == start and _placed(world).is_empty(),
			"a click with the panel closed was taken from casting")
	layer.set_panel_open(true)
	layer._tabs.current_tab = COMBAT_TAB
	combat.select_enemy(&"")
	var target_tile := _world_tile(layer, at)
	_click(layer, MOUSE_BUTTON_LEFT, at)
	var tile := Vector2i((world._player.global_position / GameConstants.PX_PER_TILE).floor())
	_check(tile == world._nearest_floor(target_tile), "a paused click without a palette entry didn't teleport")
	_check(_placed(world).is_empty(), "a teleport click placed an enemy")

	var enemy_id: StringName = GlobalBestiary.pages()[0]["ids"][0]
	combat.select_enemy(enemy_id)
	var player_at: Vector2 = world._player.global_position
	at += Vector2(20, 10)
	_click(layer, MOUSE_BUTTON_LEFT, at)
	var placed := _placed(world)
	_check(placed.size() == 1 and placed[0].scene_file_path.get_file() == "%s.tscn" % enemy_id,
			"a paused click with %s selected didn't place it" % enemy_id)
	_check(world._player.global_position == player_at, "a placing click also teleported")

	# Fly leaves the player out of every enemy's targets.
	if placed.size() == 1:
		layer._set_fly(true)
		_check(placed[0].get_target() == null, "a placed enemy targets the flying player")
		layer._set_fly(false)
		_check(placed[0].get_target() == world._player, "a placed enemy ignores the walking player")
	_click(layer, MOUSE_BUTTON_RIGHT, at)
	_check(_placed(world).is_empty(), "a right click didn't remove the placed enemy")
	combat.select_enemy(&"")


func _test_items_and_cheats(world: Node2D, combat: WorldDebugCombat) -> void:
	var item: ItemResource = DebugContent.scan_items().values()[0][0].item
	GlobalInventory.reset()
	combat.equip(item)
	_check(GlobalInventory.all_slots().any(func(slot: GlobalInventory.Slot) -> bool: return slot.item == item),
			"equip didn't slot the item")
	var dropped: Array[ItemResource] = []
	var on_drop := func(drop: ItemResource, _at: Vector2) -> void: dropped.append(drop)
	GlobalEvent.loot_dropped.connect(on_drop)
	combat.drop(item)
	GlobalEvent.loot_dropped.disconnect(on_drop)
	_check(dropped == [item], "drop didn't drop the item")

	var player: Node2D = world._player
	var previous_god := combat.god
	combat.set_god(true)
	var health: int = player.health
	player._on_hurt(3, null)
	_check(player.health == health, "god mode let damage through")
	combat.set_god(previous_god)
	var skill: int = player.skill
	var previous := [combat._cheat_buff.skill_modifier, combat._cheat_buff.speed_modifier, combat._cheat_buff.defence_modifier]
	combat.set_stats(previous[0] + 5, previous[1], previous[2])
	_check(player.skill == skill + 5, "the skill override didn't change the player's skill")
	combat.set_stats(previous[0], previous[1], previous[2])


func _test_kill_and_clear(world: Node2D, combat: WorldDebugCombat) -> void:
	var spawner: EncounterSpawner = world._encounter_spawner
	var live := spawner.live_members()
	_check(not live.is_empty(), "streamed generated enemies are live near the spawn")
	if live.is_empty():
		return
	var deaths: Array[CreatureResource] = []
	var on_death := func(data: CreatureResource, _at: Vector2) -> void: deaths.append(data)
	var drops: Array[ItemResource] = []
	var on_drop := func(drop: ItemResource, _at: Vector2) -> void: drops.append(drop)
	GlobalEvent.creature_died.connect(on_death)
	GlobalEvent.loot_dropped.connect(on_drop)

	# Clear first: nothing dies, drops or is recorded, and cleared members return with their chunks.
	var cleared_keys := spawner.live_member_keys()
	var cleared := combat.clear_enemies()
	await get_tree().process_frame
	_check(cleared >= cleared_keys.size() and spawner.live_members().is_empty(), "Clear left generated enemies")
	_check(deaths.is_empty() and drops.is_empty(), "Clear ran deaths or drops")
	_check(spawner.defeats.deaths.is_empty() and spawner.defeats.defeated.is_empty(), "Clear recorded defeats")
	spawner.build_world(world._encounters)
	await get_tree().process_frame
	_check(spawner.live_member_keys() == cleared_keys, "cleared members didn't return")

	# Kill all: real deaths. A forced drop proves the loot path runs.
	var forced := LootDrop.new()
	forced.item = DebugContent.scan_items().values()[0][0].item
	forced.chance = 1.0
	var plain: Array[Node2D] = []
	for enemy in spawner.live_members():
		if enemy.death_state == "":
			plain.append(enemy)
	_check(not plain.is_empty(), "a plain generated enemy is live")
	if plain.is_empty():
		return
	var forced_drops: Array[LootDrop] = [forced]
	plain[0].drops = forced_drops
	var plain_keys: Array[String] = []
	var expected_kills := {}
	for enemy in plain:
		plain_keys.append(enemy.get_meta("generated_key"))
		var id: StringName = GlobalBestiary._id_for(enemy.data)
		expected_kills[id] = expected_kills.get(id, 0) + 1
	var killed := combat.kill_all()
	await get_tree().process_frame
	_check(killed >= plain.size(), "Kill all didn't kill every enemy")
	_check(deaths.size() >= plain.size(), "Kill all didn't run real deaths")
	_check(drops.has(forced.item), "Kill all didn't run drops")
	for id in expected_kills:
		_check(GlobalBestiary.kill_count(id) >= expected_kills[id], "Kill all didn't count %s in the Bestiary" % id)
	for enemy_key in plain_keys:
		_check(spawner.defeats.deaths.has(enemy_key) or spawner.defeats.defeated.has(enemy_key),
				"Kill all didn't record %s's defeat" % enemy_key)
	GlobalEvent.creature_died.disconnect(on_death)
	GlobalEvent.loot_dropped.disconnect(on_drop)


func _snapshot_state(section: String) -> Dictionary:
	var out := {}
	for key in DebugState.keys(section):
		out[key] = DebugState.get_value(section, key)
	return out


func _restore_state(section: String, values: Dictionary) -> void:
	for key in DebugState.keys(section):
		if not values.has(key):
			DebugState.erase(section, key)
	for key in values:
		DebugState.set_value(section, key, values[key])
