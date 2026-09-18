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
		fails += _check_boss_phases(id, node)
	# Two frames so deferred FSM entry and make_timer adds actually execute.
	await get_tree().process_frame
	await get_tree().process_frame
	print("enemy scenes: %d instantiated" % checked)
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()

## Every Boss Phase declares a Counter. The whole design rests on a Phase being a beat that has
## to be ANSWERED — a Rotation that ships one with nothing to answer is dead time inside the
## fight, and this is the rule that cannot be allowed to drift silently. It also pins the shape
## of a Rotation (4-5 Phases, 1-4 Reps each) and that a priority Phase is marked `once`, so an
## opener that jumps the queue cannot starve the order it jumps.
func _check_boss_phases(id: String, node: Node) -> int:
	var fight := node.get_node_or_null("BossController")
	if fight == null:
		return 0
	if not (fight is BossController):
		print("  FAIL: %s/BossController does not carry the BossController script" % id)
		return 1
	var fsm: FSM = node.get_node_or_null("FSM")
	var fails := 0
	var phases: Array = fight.phases
	if phases.size() < 4 or phases.size() > 5:
		print("  FAIL: %s runs %d Phases, wanted 4-5" % [id, phases.size()])
		fails += 1
	for name in phases:
		var beat: State = fsm.states.get(name) if fsm else null
		if not (beat is Behaviour):
			print("  FAIL: %s/%s is in the Rotation but is not a behaviour" % [id, name])
			fails += 1
			continue
		if beat.counter_kind == Behaviour.Counter.NONE:
			print("  FAIL: %s/%s is a Phase with no Counter — dead time" % [id, name])
			fails += 1
		if beat.reps < 1 or beat.reps > 4:
			print("  FAIL: %s/%s authors %d Reps, wanted 1-4" % [id, name, beat.reps])
			fails += 1
		if beat.priority > 0 and not beat.once:
			print("  FAIL: %s/%s has priority without `once` — it would starve the Rotation"
				% [id, name])
			fails += 1
	return fails

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
			var property_name: String = prop.name
			var targets: Array = []
			if prop.type == TYPE_STRING and property_name.ends_with("_state"):
				targets = [state.get(property_name)]
			elif prop.type == TYPE_ARRAY and (property_name == "states" or property_name == "phase_states"):
				targets = state.get(property_name)
			for target in targets:
				if target != "" and not fsm.states.has(target):
					print("  FAIL: %s/%s.%s -> unknown state '%s'" % [id, state.name, property_name, target])
					fails += 1
	return fails
