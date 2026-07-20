extends Node
## Instantiates every enemy scene under characters/enemies/<id>/<id>.tscn and lets a few
## frames run, so broken node paths, caster setup, and FSM wiring fail loudly here instead
## of on first spawn in-game. Run as a scene (autoloads):
##   godot --headless --path game res://tests/test_enemy_scenes.tscn

func _ready() -> void:
	var fails := 0
	var checked := 0
	var dir := DirAccess.open("res://characters/enemies")
	for id in dir.get_directories():
		var path := "res://characters/enemies/%s/%s.tscn" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("  FAIL: %s does not load" % path)
			fails += 1
			continue
		var node: Node = scene.instantiate()
		add_child(node)
		checked += 1
		if node.data == null:
			print("  FAIL: %s carries no CreatureResource" % id)
			fails += 1
		elif node.data.max_health <= 0 or node.data.icon == null:
			print("  FAIL: %s data incomplete (hp/icon)" % id)
			fails += 1
		fails += _check_state_names(id, node)
	# Two frames so deferred FSM entry and make_timer adds actually execute.
	await get_tree().process_frame
	await get_tree().process_frame
	print("enemy scenes: %d instantiated" % checked)
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()

# Every behaviour hand-off is a state NAME, resolved only when that edge is first taken —
# so a typo in a rarely-rolled pattern (a boss's low-HP beat) stays invisible until it
# fires mid-fight and the FSM silently refuses. Walk each behaviour's `*_state` exports and
# its pattern pools up front and check they name a real sibling state.
func _check_state_names(id: String, node: Node) -> int:
	var fsm: FSM = node.get_node_or_null("FSM")
	if fsm == null:
		return 0
	var fails := 0
	for state in fsm.get_children():
		if not (state is Behaviour):
			continue
		for prop in state.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = prop.name
			var targets: Array = []
			if prop.type == TYPE_STRING and name.ends_with("_state"):
				targets = [state.get(name)]
			elif prop.type == TYPE_ARRAY and (name == "states" or name == "phase_states"):
				targets = state.get(name)
			for target in targets:
				if target != "" and not fsm.states.has(target):
					print("  FAIL: %s/%s.%s -> unknown state '%s'" % [id, state.name, name, target])
					fails += 1
	return fails
