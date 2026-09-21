extends Node
## Instantiates every enemy scene under characters/enemies/<id>/<id>.tscn and lets a few
## frames run, so broken node paths, caster setup, and FSM wiring fail loudly here instead
## of on first spawn in-game. Run as a scene (autoloads):
##   godot --headless --path game res://tests/test_enemy_scenes.tscn

var _fails := 0

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
		fails += _check_bullet_reach(id, node)
		checked += _check_siblings(id)
	# Two frames so deferred FSM entry and make_timer adds actually execute.
	await get_tree().process_frame
	await get_tree().process_frame
	fails += _fails
	print("enemy scenes: %d instantiated" % checked)
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit()

## The other bodies in an enemy's folder: a splitter's brood, and every body of a multi-body
## Boss fight (rotmaw's two halves, its core and its wardens all live under rotmaw/). They are
## real scenes the player meets, and until this walked them the only thing linted in a
## three-Rotation fight was stage one. They carry no stat sheet of their own — a leaf body
## authors max_health on the scene, and a body that still has to split files its sheet beside
## the boss's — so the data checks above are the boss's alone and these get the wiring ones.
func _check_siblings(id: String) -> int:
	var found := 0
	for file in DirAccess.get_files_at("res://characters/enemies/%s" % id):
		if not file.ends_with(".tscn") or file == "%s.tscn" % id:
			continue
		var scene := load("res://characters/enemies/%s/%s" % [id, file]) as PackedScene
		if scene == null:
			print("  FAIL: %s/%s does not load" % [id, file])
			continue
		var body: Node = scene.instantiate()
		add_child(body)
		found += 1
		var body_id := file.get_basename()
		_fails += _check_state_names(body_id, body)
		_fails += _check_boss_phases(body_id, body)
		_fails += _check_bullet_reach(body_id, body)
	return found

## A shot has to outlast the distance it starts firing from, by 2 tiles: an enemy that opens up
## at 3 tiles with 3-tile bullets never reaches a player who takes one step back. That distance
## is the probe that decides the beat fires — its own attack probe (plus the exit margin), else
## the range probe that makes it eligible, else the attack probe of the pursuit that hands off
## to it. A beat with none of them fires at whatever range it was dispatched at, so it has no
## distance to be held to. Exempt too: a mine (no range or no speed) never flies, and a charge
## carries its shots with the body.
const REACH_MARGIN_TILES := 2

func _check_bullet_reach(id: String, node: Node) -> int:
	var fsm := node.get_node_or_null("FSM")
	if fsm == null:
		return 0
	var arrive := {}
	for state in fsm.get_children():
		if state is Approach and state.attack_probe_path != NodePath():
			arrive[state.attack_state] = _probe_px(state, state.attack_probe_path)
	var fails := 0
	for state in fsm.get_children():
		if not (state is Cast) or not (state.spell is BulletSpellResource) \
				or state.spell is ChargeDashResource:
			continue
		var bullet: BulletResource = state.spell.bullet
		if bullet == null or bullet.range_tiles <= 0 or bullet.speed_tiles <= 0:
			continue
		var from: float = arrive.get(String(state.name), 0.0)
		if state.attack_probe_path != NodePath():
			from = _probe_px(state, state.attack_probe_path) + state.exit_margin
		elif state.range_probe_path != NodePath():
			from = _probe_px(state, state.range_probe_path)
		var need := ceili(from / GameConstants.PX_PER_TILE) + REACH_MARGIN_TILES
		if from > 0.0 and bullet.range_tiles < need:
			print("  FAIL: %s/%s fires from %d tiles but its bullets fly %d, need %d"
				% [id, state.name, ceili(from / GameConstants.PX_PER_TILE), bullet.range_tiles, need])
			fails += 1
	return fails

func _probe_px(from: Node, path: NodePath) -> float:
	var probe := from.get_node_or_null(path) as RayCast2D
	return probe.target_position.length() if probe else 0.0

## Every Boss Phase declares a Counter. The whole design rests on a Phase being a beat that has
## to be ANSWERED — a Rotation that ships one with nothing to answer is dead time inside the
## fight, and this is the rule that cannot be allowed to drift silently. It also pins the shape
## of a Rotation (3-6 Phases, 1-8 Reps each, a Tail of 0.5-2.5s) and that a priority Phase is
## marked `once`, so an opener that jumps the queue cannot starve the order it jumps.
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
	if phases.size() < 3 or phases.size() > 6:
		print("  FAIL: %s runs %d Phases, wanted 3-6" % [id, phases.size()])
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
		if beat.reps < 1 or beat.reps > 8:
			print("  FAIL: %s/%s authors %d Reps, wanted 1-8" % [id, name, beat.reps])
			fails += 1
		# Reps and Tails are the boss's Tempo, and Tempo is authored per Phase rather than
		# templated — but a Tail outside this band is either no window at all or a farm.
		if beat.tail < 0.5 or beat.tail > 2.5:
			print("  FAIL: %s/%s authors a %0.1fs Tail, wanted 0.5-2.5" % [id, name, beat.tail])
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
