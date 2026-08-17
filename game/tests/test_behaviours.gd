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
	# The shared deepwood pool. Each one leans on a loop the glade roster never exercises:
	# the moth's clocked retreat (poke -> flee -> re-close), the stalker's disguise->reveal
	# edge, the snake's cornered volley, and the moss golem's two-spell Nope->Ring chain
	# through a single caster — the last of which deadlocks outright if a creature's channel
	# never releases, so a low state-change count here is the regression that matters.
	"moth": {"scene": "res://characters/enemies/moth/moth.tscn", "min_bullets": 2, "min_changes": 5},
	"stalker": {"scene": "res://characters/enemies/stalker/stalker.tscn", "min_bullets": 1, "min_changes": 4},
	"grimling": {"scene": "res://characters/enemies/grimling/grimling.tscn", "min_bullets": 2, "min_changes": 4},
	"moss_golem": {"scene": "res://characters/enemies/moss_golem/moss_golem.tscn", "min_bullets": 8, "min_changes": 5},
	# No bullets expected: like the viper, the snake only fires once cornered, and this
	# harness is open space with nothing to back into. Its volley is covered against real
	# walls in test_deepwood; here we only assert the flee loop keeps handing off.
	"snake": {"scene": "res://characters/enemies/snake/snake.tscn", "min_bullets": 0, "min_changes": 3},
	# The animal deepwood. Each of these rides a seam the shared pool never touches: the
	# chargers' spell-driven dash (a beat whose movement lives in the cast, so a stalled
	# start_dash reads here as a creature that never leaves its wind-up), the owls' channel
	# loop (charge -> rest -> re-perch, hanging off a channel SpellCaster has to cap and
	# release on its own — one that never caps parks the owl mid-telegraph forever, and a
	# refused cast that isn't passed on stutters the loop), the mole's submerged approach,
	# and the grimlord's parting ring — which only goes off if the death beat runs at all.
	"thornback": {"scene": "res://characters/enemies/thornback/thornback.tscn", "min_bullets": 4, "min_changes": 4},
	"owl": {"scene": "res://characters/enemies/owl/owl.tscn", "min_bullets": 2, "min_changes": 5},
	"mole": {"scene": "res://characters/enemies/mole/mole.tscn", "min_bullets": 8, "min_changes": 5},
	"grimlord": {"scene": "res://characters/enemies/grimlord/grimlord.tscn", "min_bullets": 3, "min_changes": 4},
	"razorback": {"scene": "res://characters/enemies/razorback/razorback.tscn", "min_bullets": 4, "min_changes": 4},
	"great_owl": {"scene": "res://characters/enemies/great_owl/great_owl.tscn", "min_bullets": 2, "min_changes": 5},
	"gnarlking": {"scene": "res://characters/enemies/gnarlking/gnarlking.tscn", "min_bullets": 1, "min_changes": 6},
}

const BWOOM_SCRIPT := preload("res://characters/player/spells/bwoom/bwoom.gd")

var _bullets := 0
var _states: Array[String] = []

func _ready() -> void:
	var fails := 0
	for id in CASES:
		fails += await _run(id, CASES[id])
	fails += await _phase_swap()
	fails += await _halp_queue()
	fails += await _brood_gate()
	fails += await _enrage_lap()
	fails += await _telegraph()
	fails += await _puffcap_chain()
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
		# Bwoom is a shot without being a BaseBullet — a charged ball that pierces rather
		# than despawning on a hurtbox — so an owl's whole output would read as zero here.
		# Counted when the ball appears (channel start); that it then launches with damage
		# on the right layer is test_any_caster's job.
		if n.get_script() == BWOOM_SCRIPT:
			_bullets += 1
		elif n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
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

	# Generous: a case exits the moment it meets both minimums, so this only bounds the
	# failure path. A boss with long telegraphs (the gnarlking calls a brood, then rears for
	# a slam, before anything resembling a bullet appears) sat right on a 20s wire and
	# failed intermittently.
	var deadline := Time.get_ticks_msec() + 35000
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
	target.queue_free()
	# Minions outlive the boss that called them, and every case spawns on the same spot —
	# leave none standing or the next creature fights the previous one's adds (which is
	# exactly what a brood-gated boss reads as "the pack is still up").
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	return fails

# Tether's queue mode: halp's retinue must string out single-file BEHIND a walking anchor,
# one place per unit, rather than stacking on one slot (a stack shares a hurtbox) or
# orbiting like bzzz. Nothing else drives it — a wrong rank reads in-game as three minions
# fused into one sprite.
func _halp_queue() -> int:
	var anchor := CharacterBody2D.new()
	anchor.add_to_group("player")
	add_child(anchor)

	var minions: Array[Creature] = []
	for i in 3:
		var m: Creature = load("res://characters/player/spells/halp/halp_minion.tscn").instantiate()
		m.position = Vector2(0, 8 * i)
		add_child(m)
		minions.append(m)
	await get_tree().physics_frame
	for m in minions:  # headless never renders: the off-screen sleeper would freeze them
		for child in m.get_children():
			if child is VisibleOnScreenEnabler2D:
				child.queue_free()
		m.process_mode = Node.PROCESS_MODE_INHERIT

	# Walk the anchor right for a while: the line forms against its heading, and only a
	# moving anchor tells the behaviour which way "behind" is.
	for _frame in 180:
		anchor.velocity = Vector2(60, 0)
		anchor.move_and_slide()
		await get_tree().physics_frame
	# Marching at a fixed speed, the line keeps its places while the anchor walks — a
	# speed that eases off near the slot shows up here as a trail stretching out behind.
	var walking: Array[float] = []
	for m in minions:
		walking.append(m.global_position.x - anchor.global_position.x)
	for _frame in 60:
		anchor.velocity = Vector2.ZERO
		await get_tree().physics_frame

	var spacing: float = minions[0].fsm.states["Follow"].queue_spacing
	var settled: Array[float] = []
	var fails := 0
	for i in minions.size():
		settled.append(minions[i].global_position.x - anchor.global_position.x)
		# Half a spacing of slack: it is a chase toward the slot, not a snap onto it. A
		# place held to within that is also, necessarily, behind the anchor.
		fails += _expect("halp #%d holds place %d in line (x offset %.1f)"
			% [i, i + 1, settled[i]], absf(settled[i] + spacing * (i + 1)) < spacing * 0.5)
		fails += _expect("halp #%d keeps its place while walking (x offset %.1f)"
			% [i, walking[i]], absf(walking[i] + spacing * (i + 1)) < spacing * 0.5)

	if fails == 0:
		print("  ok: halp queue — line at %s behind the anchor, %s while walking"
			% [settled, walking])
	anchor.queue_free()
	for m in minions:
		m.queue_free()
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

# The gnarlking is the one boss whose next beat is decided by the arena rather than by a
# roll: its charge sits behind Behaviour.clear_group, so the brood standing between you and
# it is what keeps the fight in its armoured hunt phase. Assert the clause directly, both
# that a live packmate closes the gate and that DISTANCE reopens it — streaming keeps other
# rooms' packs in the tree, and a global count would pin the fight on a grimling three rooms
# away.
func _brood_gate() -> int:
	# The smoke case above left its own brood standing at the origin — minions outlive the
	# boss that called them — and this check is about exactly that group.
	await _clear_pack()

	var enemy: Creature = load(CASES["gnarlking"]["scene"]).instantiate()
	add_child(enemy)
	var add: Creature = load("res://characters/enemies/grimling/grimling.tscn").instantiate()
	add_child(add)
	# Its melee kit is range-gated, so the ladder only answers meaningfully with a target
	# somewhere — the distance to it is half of what decides the next beat.
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	add_child(target)
	target.global_position = Vector2(30, 0)  # inside the slam's own reach
	await get_tree().physics_frame

	var beats := enemy.fsm.states
	var fails := 0

	add.global_position = Vector2(40, 0)
	fails += _expect("charge gated while the brood stands", not beats["Charge"].can_run())
	fails += _expect("in reach, the ladder falls to the slam while the brood stands",
		beats["Hunt"]._first_ready() == "Slam")

	# Out past both weapons: a close-range fighter's answer to distance is to walk it down,
	# never to rear into a slam that lands on nothing.
	target.global_position = Vector2(300, 0)
	await get_tree().physics_frame
	fails += _expect("slam drops out of the ladder out of reach", not beats["Slam"].can_run())
	fails += _expect("volley drops out of the ladder out of reach", not beats["Volley"].can_run())
	fails += _expect("out of reach, the ladder closes the distance",
		beats["Hunt"]._first_ready() == "Close")
	target.global_position = Vector2(30, 0)
	await get_tree().physics_frame

	add.global_position = Vector2(400, 0)  # past clear_radius_tiles
	fails += _expect("a distant pack doesn't gate the charge", beats["Charge"].can_run())

	await _clear_pack()
	fails += _expect("charge opens once the brood is dead", beats["Charge"].can_run())
	fails += _expect("the ladder leads with the charge once clear",
		beats["Hunt"]._first_ready() == "Charge")

	target.queue_free()
	if fails == 0:
		print("  ok: gnarlking brood gate — pack and range decide the next beat")
	enemy.queue_free()
	await get_tree().physics_frame
	return fails

# The enrage half of that fight never runs in the smoke case above, because nothing there
# kills the brood — so drive the lap the player's own clear produces and assert the whole
# chain hands off. Everything past the charge is a sequence with no dispatcher to fall back
# on (Charge -> Stalk -> Charge2 -> Breathe -> Winded -> Summon), which is exactly where a
# mis-wired done_state parks the boss forever.
func _enrage_lap() -> int:
	_states = []
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = Vector2(24, 0)
	add_child(target)

	var enemy: Creature = load(CASES["gnarlking"]["scene"]).instantiate()
	add_child(enemy)
	await get_tree().physics_frame
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.fsm.state_changed.connect(func(_prev: State, cur: State) -> void:
		_states.append(cur.name))

	# Stand in for a player who clears the adds the instant they land and then stays in
	# melee — the charge overshoots by design, so gluing the target to the boss is what
	# drives Stalk into the second charge rather than out to Winded. Both branches are
	# authored; this is the one whose wiring can strand the boss.
	var seen := {}
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline and not seen.has("Summon2"):
		target.global_position = enemy.global_position + Vector2(20, 0)
		for node in get_tree().get_nodes_in_group("pack_grimling"):
			node.get_parent().queue_free()
		for s in _states:
			seen[s] = true
		# A second Summon means the lap closed rather than merely started.
		if seen.has("Charge") and _states.count("Summon") > 1:
			seen["Summon2"] = true
		await get_tree().physics_frame

	var fails := 0
	fails += _expect("enrage opens once the adds are cleared", seen.has("Charge"))
	fails += _expect("the charge hands off into the stalk", seen.has("Stalk"))
	fails += _expect("a target still in reach chains the second charge", seen.has("Charge2"))
	fails += _expect("the lap closes back onto the brood call", seen.has("Summon2"))
	if fails == 0:
		print("  ok: gnarlking enrage lap — %s" % [seen.keys()])
	else:
		print("  saw: %s" % [_states])
	enemy.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The wind-up telegraph. Asserted against a live enemy rather than by reading the scene,
# because the strobe rides a looping tween on the creature's own process: bind it to the
# wrong node, or let the off-screen sleeper hold it, and the flash silently never fires
# while every static check still passes. The shard grimling carries the longest wind-up in
# the shared pool (0.45s), so its telegraph is the one with frames to spare.
func _telegraph() -> int:
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = Vector2(24, 0)
	add_child(target)

	var enemy: Creature = load(
		"res://characters/enemies/shard_grimling/shard_grimling.tscn").instantiate()
	enemy.position = Vector2.ZERO
	add_child(enemy)
	await get_tree().physics_frame
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT

	# Both halves of the square wave, and that the beat puts the sprite back to normal.
	# The flash is authored on the scene, so the colour is asserted too — a telegraph that
	# fires in the wrong hue tells the player the wrong thing.
	# A pulse, not a strobe and not a hold: the flash must land, then let go on its own
	# well inside the wind-up. `lit` is the guard against a repeating blink creeping back
	# in — a looping tween would keep re-lighting the sprite far past this bound.
	var pulse_cap := int(ceil(Creature.TELEGRAPH_FLASH * Engine.physics_ticks_per_second)) + 4
	var flashed := false      # flat material on, in the authored accent
	var cleared := false      # ...and off again on its own
	var lit := 0
	var deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < deadline and not cleared:
		var mat := enemy.sprite.material as ShaderMaterial
		if mat:
			lit += 1
			flashed = flashed or mat.get_shader_parameter("flat_color").is_equal_approx(
				Color(Palette.LIME.r, Palette.LIME.g, Palette.LIME.b, 1.0))
		elif flashed:
			cleared = true
		await get_tree().physics_frame

	var fails := 0
	fails += _expect("the wind-up flashes the authored accent", flashed)
	fails += _expect("the sprite goes back to normal on its own", cleared)
	fails += _expect("the flash is one pulse, not a strobe (%d frames)" % lit, lit <= pulse_cap)
	if fails == 0:
		print("  ok: shard grimling telegraph — one lime pulse over %d frames" % lit)
	enemy.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The puffcap field: one drawing breath calls its neighbours into theirs, so stepping on the
# near cap lights caps the player never went near. The far one is deliberately parked outside
# its own trigger probe and inside the pack radius, so only the relay can wake it — the whole
# encounter (light the chain, or pick them off from range) hangs off that edge.
func _puffcap_chain() -> int:
	var target := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	add_child(target)

	var caps: Array[Creature] = []
	for i in 2:
		var cap: Creature = load("res://characters/enemies/puffcap/puffcap.tscn").instantiate()
		cap.position = Vector2(i * 22, 0)
		add_child(cap)
		caps.append(cap)
	await get_tree().physics_frame
	for cap in caps:
		for child in cap.get_children():
			if child is VisibleOnScreenEnabler2D:
				child.queue_free()
		cap.process_mode = Node.PROCESS_MODE_INHERIT
	target.global_position = caps[0].global_position - Vector2(8, 0)

	var far_states := {}
	caps[1].fsm.state_changed.connect(func(_prev: State, cur: State) -> void:
		far_states[String(cur.name)] = true)

	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and is_instance_valid(caps[1]):
		await get_tree().physics_frame

	var clouds := get_tree().get_nodes_in_group(SporeCloud.GROUP).size()
	var fails := 0
	fails += _expect("the stepped-on cap pops", not is_instance_valid(caps[0]))
	fails += _expect("a pop calls the cap beside it into its inhale", far_states.has("Inhale"))
	fails += _expect("both caps left spores behind (%d)" % clouds, clouds >= 2)
	if fails == 0:
		print("  ok: puffcap chain — one pop, two patches of floor")
	for cloud in get_tree().get_nodes_in_group(SporeCloud.GROUP):
		cloud.free()
	for cap in caps:
		if is_instance_valid(cap):
			cap.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

func _clear_pack() -> void:
	for node in get_tree().get_nodes_in_group("pack_grimling"):
		node.get_parent().queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1
