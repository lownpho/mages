extends Node
## Functional smoke for the streamlined behaviour library: drives real enemies against a
## live target and asserts the loops that only exist at runtime —
##   - a chaser re-fires (Attack -> Recover -> Attack), so Hold's readiness gate doesn't
##     deadlock the fire-then-wait cycle;
##   - a boss's PatternPicker keeps handing off (many state changes, >1 distinct attack),
##     so the sibling-scan pool and can_run eligibility don't stall the dispatcher.
## Run: godot --headless --path game res://tests/test_behaviours.tscn

const CASES := {
	"wasp": {"scene": "res://characters/enemies/wasp/wasp.tscn", "min_bullets": 2, "min_changes": 3},
	"mandraker": {"scene": "res://characters/enemies/mandraker/mandraker.tscn", "min_bullets": 1, "min_changes": 4},
	"fae": {"scene": "res://characters/enemies/fae/fae.tscn", "min_bullets": 1, "min_changes": 6},
	"thornmess": {"scene": "res://characters/enemies/thornmess/thornmess.tscn", "min_bullets": 1, "min_changes": 6},
}

var _bullets := 0
var _states: Array[String] = []

func _ready() -> void:
	var fails := 0
	for id in CASES:
		fails += await _run(id, CASES[id])
	fails += await _phase_swap()
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _run(id: String, spec: Dictionary) -> int:
	_bullets = 0
	_states = []
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = Vector2(24, 0)
	add_child(target)

	var counter := func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
			_bullets += 1
	get_tree().root.child_entered_tree.connect(counter)

	var enemy: Creature = load(spec["scene"]).instantiate()
	enemy.position = Vector2.ZERO
	add_child(enemy)
	await get_tree().physics_frame
	# Headless never renders, so the off-screen sleeper would freeze the AI — strip it.
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.fsm.state_changed.connect(func(_prev: State, cur: State) -> void:
		_states.append(cur.name))

	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline \
			and (_bullets < spec["min_bullets"] or _states.size() < spec["min_changes"]):
		await get_tree().physics_frame

	var distinct := {}
	for s in _states:
		distinct[s] = true
	var fails := 0
	if _bullets < spec["min_bullets"]:
		print("  FAIL: %s fired %d bullets, wanted >= %d" % [id, _bullets, spec["min_bullets"]])
		fails += 1
	if _states.size() < spec["min_changes"]:
		print("  FAIL: %s made %d state changes (deadlock?), wanted >= %d — saw %s"
			% [id, _states.size(), spec["min_changes"], distinct.keys()])
		fails += 1
	if fails == 0:
		print("  ok: %s — %d bullets, %d state changes, states %s"
			% [id, _bullets, _states.size(), distinct.keys()])

	get_tree().root.child_entered_tree.disconnect(counter)
	enemy.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The health-window replacement for the old phase_states: which beats a boss's dispatcher
# will consider is exactly Behaviour.can_run, so assert it directly at two health levels
# rather than waiting on lucky rolls. Below 25% the desperation moves (Spores, and Summon it
# chains to) must be eligible and the healthy-phase beats (Bloom, Uproot) must drop out;
# above it, the reverse.
func _phase_swap() -> int:
	var enemy: Creature = load(CASES["thornmess"]["scene"]).instantiate()
	add_child(enemy)
	await get_tree().physics_frame  # let behaviour _ready resolve creature/caster refs

	var beats := enemy.fsm.states
	var fails := 0

	enemy.health = enemy.max_health  # healthy phase
	fails += _expect("Bloom eligible when healthy", beats["Bloom"].can_run())
	fails += _expect("Uproot eligible when healthy", beats["Uproot"].can_run())
	fails += _expect("Spores NOT eligible when healthy", not beats["Spores"].can_run())

	enemy.health = int(enemy.max_health * 0.2)  # desperation phase
	fails += _expect("Spores eligible below 25%", beats["Spores"].can_run())
	fails += _expect("Missiles eligible below 25%", beats["Missiles"].can_run())
	fails += _expect("Bloom dropped below 25%", not beats["Bloom"].can_run())
	fails += _expect("Uproot dropped below 25%", not beats["Uproot"].can_run())

	if fails == 0:
		print("  ok: thornmess phase swap — health windows gate the roll pool both ways")
	enemy.queue_free()
	await get_tree().physics_frame
	return fails

func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1
