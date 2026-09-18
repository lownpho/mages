extends Node
## Functional smoke for the streamlined behaviour library: drives real enemies against a
## live target and asserts the loops that only exist at runtime —
##   - a chaser re-fires (Attack -> Recover -> Attack), so Hold's readiness gate doesn't
##     deadlock the fire-then-wait cycle;
##   - a boss's PatternPicker keeps handing off (many state changes, >1 distinct attack),
##     so the sibling-scan pool and can_run eligibility don't stall the dispatcher;
##   - a boss or rare left alone heals to full and goes home, while a common stays hurt.
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
	# The Mycelium. The sporespitter is the roster's first Gate on something that isn't a boss,
	# and the first beat gated purely by RANGE: the harness parks its target in close, so a
	# spitter that never reaches Blam has lost its range gate, and one that never reaches Lob
	# has lost the ladder's fallthrough.
	"sporespitter": {"scene": "res://characters/enemies/sporespitter/sporespitter.tscn",
		"min_bullets": 2, "min_changes": 5, "wants_states": ["Blam", "Lob"]},
	# The same spitter with the target stood off past its close probe: the range gate has to
	# shut the cone entirely and leave the lob carrying the fight. Standing in its face and
	# standing across the room are the two answers it has, so both are worth a case.
	"sporespitter (far)": {"scene": "res://characters/enemies/sporespitter/sporespitter.tscn",
		"min_bullets": 1, "min_changes": 3, "target_at": Vector2(60, 0),
		"wants_states": ["Lob"], "denies_states": ["Blam"]},
}

const BWOOM_SCRIPT := preload("res://characters/player/spells/bwoom/bwoom.gd")

var _bullets := 0
var _states: Array[String] = []
# Tail observations the Rotation pump makes (see _pump): frames spent inside an open Tail, and
# frames that found one open while a beat was still live.
var _tail_opens := 0
var _tail_breaks := 0

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
	fails += await _rotation()
	fails += await _counters()
	fails += await _intensity()
	fails += await _timing()
	fails += await _desperation()
	fails += await _free_beat()
	fails += await _combat_reset()
	fails += await _torn_down()
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
	target.position = spec.get("target_at", Vector2(24, 0))
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
	# Optional: beats the run must actually have reached. The counts above only prove the
	# creature isn't stuck; this pins WHICH beats, for a ladder whose rungs are gated on
	# something the harness sets up (the spitter's target stands in close).
	for beat: String in spec.get("wants_states", []):
		if not distinct.has(beat):
			print("  FAIL: %s never reached %s — saw %s" % [id, beat, distinct.keys()])
			fails += 1
	for beat: String in spec.get("denies_states", []):
		if distinct.has(beat):
			print("  FAIL: %s ran %s from %s" % [id, beat, spec.get("target_at", "close")])
			fails += 1
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
	# Bullets outlive their caster: a case that left a hundred of Fae's rings in the air would
	# have them land on the next case's minions.
	for node in get_tree().get_nodes_in_group("bullets"):
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

# The out-of-combat reset: a boss or rare left alone for COMBAT_RESET_SECONDS heals to full
# and goes home, a common never does. The clock is wall-time, so the case ages the creature's
# last-hit stamp rather than sitting here for a minute.
func _combat_reset() -> int:
	var target := CharacterBody2D.new()
	target.add_to_group("player")
	target.position = Vector2(48, 0)
	add_child(target)

	var fails := 0
	# fae is a BOSS, razorback a RARE, wasp a COMMON — one case each, because "rares behave
	# like bosses" is a rule about rarity and nothing else.
	for spec in [["fae", true], ["razorback", true], ["wasp", false]]:
		var id: String = spec[0]
		var resets: bool = spec[1]
		var enemy: Creature = load("res://characters/enemies/%s/%s.tscn" % [id, id]).instantiate()
		enemy.position = Vector2.ZERO
		add_child(enemy)
		await get_tree().physics_frame
		for child in enemy.get_children():   # headless never renders (see _run)
			if child is VisibleOnScreenEnabler2D:
				child.queue_free()
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
		for _frame in 120:
			await get_tree().physics_frame
		enemy._on_hurt(1, null)
		var hurt_health := enemy.health
		# A Boss's Intensity rides the same leash: a fight the player walked away from is
		# rewound all the way, not left half-escalated for whoever comes back.
		var fight := enemy.get_node_or_null("BossController")
		if fight is BossController:
			fight.intensity = 1.8
		# Shoved off its spawn tile on purpose: a boss that holds its ground (the fae hovers
		# in place) would otherwise pass the walk-home check by never having left.
		enemy.global_position += Vector2(64, 0)
		# Age the fight past the window: the reset is checked against the wall clock every
		# physics frame, so this is the whole minute without waiting one.
		enemy._last_hurt_ms -= int(Creature.COMBAT_RESET_SECONDS * 1000.0) + 1
		for _frame in 4:
			await get_tree().physics_frame

		fails += _expect("%s took the test hit (%d/%d)" % [id, hurt_health, enemy.max_health],
			hurt_health < enemy.max_health)
		if resets:
			fails += _expect("%s healed to full after the window (%d/%d)"
				% [id, enemy.health, enemy.max_health], enemy.health == enemy.max_health)
			fails += _expect("%s went home (%.1f px away)"
				% [id, enemy.global_position.length()], enemy.global_position.length() < 1.0)
			if fight is BossController:
				fails += _expect("%s rewound its Intensity too (%0.2f)" % [id, fight.intensity],
					fight.intensity == BossController.MIN_INTENSITY)
			print("  ok: %s reset out of combat — %d/%d hp, back at spawn"
				% [id, enemy.health, enemy.max_health])
		else:
			fails += _expect("%s stayed hurt (%d/%d)" % [id, enemy.health, enemy.max_health],
				enemy.health == hurt_health)
			print("  ok: %s (common) never resets — %d/%d hp" % [id, enemy.health, enemy.max_health])

		for node in get_tree().get_nodes_in_group("enemies"):
			node.queue_free()
		await get_tree().physics_frame
		await get_tree().process_frame
	target.queue_free()
	await get_tree().physics_frame
	return fails


# A run ends by swapping scenes, and change_scene_to_packed pulls the old scene off the root
# a frame BEFORE it frees it — so a dispatcher's deferred hand-off still runs, on a live
# creature with no tree under it. That used to reach get_tree() inside get_target(), which
# is why dying to a boss's own blam printed an error on the way to the title.
func _torn_down() -> int:
	var fails := 0
	for path: String in ["res://characters/enemies/sporespitter/sporespitter.tscn",
			"res://characters/enemies/gnarlking/gnarlking.tscn",
			"res://characters/enemies/fae/fae.tscn"]:
		var id := path.get_file().get_basename()
		var enemy: Creature = load(path).instantiate()
		add_child(enemy)
		await get_tree().physics_frame
		var dispatchers: Array[Node] = []
		for state: State in enemy.fsm.states.values():
			if state is PatternPicker or state is Gate or state is Cycle:
				dispatchers.append(state)
		fails += _expect("%s has a dispatcher to test" % id, not dispatchers.is_empty())
		# Exactly the queued hand-off enter() makes, left pending across the detach.
		for dispatcher in dispatchers:
			dispatcher.call_deferred("_dispatch")
		remove_child(enemy)
		await get_tree().process_frame  # the deferred queue flushes here, out of tree
		fails += _expect("%s targets nothing once detached" % id, enemy.get_target() == null)
		enemy.queue_free()
		await get_tree().physics_frame
	if fails == 0:
		print("  ok: dispatch after teardown — hand-offs and targeting no-op out of tree")
	return fails


func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1


# --- the Boss skeleton (BossController + Cycle) -------------------------------------------------

# A live Boss with a live target it can see, and the target's own hurtbox so a case can say
# "the player was hit" by firing the signal a real player fires. The off-screen sleeper comes
# off, because headless never renders and would freeze the AI on its first frame.
func _boss_arena(scene: String, hand_driven: bool = false) -> Dictionary:
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	add_child(target)
	var box: Area2D = load("res://components/hurtbox.tscn").instantiate()
	box.name = "Hurtbox"
	target.add_child(box)
	target.position = Vector2(24, 0)

	var enemy: Creature = load(scene).instantiate()
	enemy.position = Vector2.ZERO
	add_child(enemy)
	await get_tree().physics_frame
	for child in enemy.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	# The out-of-combat leash is wall-clock: a case that damages a boss and then sits in a frame
	# loop would watch the fight rewind under it. Stamp the clock at spawn so the leash is a
	# minute away, exactly as it is in play when a hit lands.
	enemy._last_hurt_ms = Time.get_ticks_msec()
	if hand_driven:
		# This case drives the FSM's state machine by hand (begin_phase, jump_to, signal
		# emissions), so switch the FSM off rather than let it dispatch over the top.
		enemy.fsm.set_process(false)
		enemy.fsm.set_physics_process(false)
	return {"enemy": enemy, "target": target, "box": box}

func _close_arena(arena: Dictionary) -> void:
	arena["target"].queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

# Drive a Boss's Rotation by hand: stand in for each Phase beat's own hand-off (the FSM
# transition the beat makes when its burst ends) and burn whatever pause the Cycle is running.
# Fae's ring burst is eight seconds long on its own, so waiting out a lap of this Rotation is
# minutes of wall clock — what these cases pin is ORDER, Reps and the dials, not her tuning.
func _pump(arena: Dictionary, until: Callable) -> Array[String]:
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var cycle: Cycle = enemy.fsm.states["Cycle"]
	var seen: Array[String] = []
	var track := func(_prev: State, cur: State) -> void:
		var beat := cur as Behaviour
		if beat and beat.counter_kind != Behaviour.Counter.NONE:
			seen.append(beat.name)
	enemy.fsm.state_changed.connect(track)
	_tail_opens = 0
	_tail_breaks = 0
	var guard := 0
	while not until.call(seen) and guard < 6000:
		guard += 1
		# An ADDS Phase is gated on its escort: clearing the brood every frame is the player
		# killing them, which is what keeps a lap moving.
		for node in get_tree().get_nodes_in_group("pack_wisp"):
			node.get_parent().queue_free()
		var cur: State = enemy.fsm.current_state
		if cur and String(cur.name) in boss.phases:
			# The Tail is the promise a Phase makes: shut while its beat is live, open only
			# once its last Rep is in. Watched here so every case that drives a Rotation gets
			# it checked for free.
			if boss.tail_open:
				_tail_breaks += 1
			enemy.fsm.transition_to("Cycle")
		elif cur and String(cur.name) == "Cycle":
			if boss.tail_open:
				_tail_opens += 1
			cycle.physics_update(0.5)
		else:
			enemy.fsm.transition_to("Cycle")  # the engage edge
		await get_tree().physics_frame
	enemy.fsm.state_changed.disconnect(track)
	if guard >= 6000:
		print("  FAIL: pumping the Rotation never reached what the case waited for (saw %s)" % [seen])
	return seen

# The ordered Rotation: each Phase plays its authored Reps, then the next Phase in the authored
# list takes over, and after the last one the Rotation wraps back onto the first. Order is the
# whole point of the skeleton — a boss that rolls is what this feature exists to delete.
func _rotation() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"])
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var phases: Array[String] = boss.phases
	var fails := 0

	fails += _expect("the Rotation is 4-5 Phases (%d)" % phases.size(),
		phases.size() >= 4 and phases.size() <= 5)
	for name in phases:
		var beat: Behaviour = enemy.fsm.states.get(name)
		fails += _expect("%s is a real FSM state in the Rotation" % name, beat != null)
		if beat:
			fails += _expect("%s authors 1-4 Reps (%d)" % [name, beat.reps],
				beat.reps >= 1 and beat.reps <= 4)

	# A healthy lap: the desperation Phase is last and gated on a quarter health, so it is
	# skipped and the wrap lands straight back on the first Phase.
	var expected: Array[String] = []
	for name in phases:
		if name == "RingStorm":
			continue
		var beat: Behaviour = enemy.fsm.states[name]
		for _rep in beat.reps:
			expected.append(name)
	expected.append(phases[0])
	expected.append(phases[0])

	var seen: Array[String] = await _pump(arena, func(list: Array) -> bool:
		return list.size() >= expected.size())
	fails += _expect("the Rotation runs its Phases in order, for their Reps, and wraps (%s)"
		% [seen], seen == expected)
	fails += _expect("the HP-gated desperation Phase stays out of a healthy lap",
		not seen.has("RingStorm"))
	fails += _expect("the wrap leaves Intensity at or above its opening value (%0.2f)" % boss.intensity,
		boss.intensity >= BossController.MIN_INTENSITY)
	fails += _expect("a Phase's Tail is shut while its beat is live (%d frames)" % _tail_breaks,
		_tail_breaks == 0)
	fails += _expect("the Tail opens after a Phase's last Rep (%d frames)" % _tail_opens,
		_tail_opens > 0)
	if fails == 0:
		print("  ok: fae rotation — %s" % [seen])
	await _close_arena(arena)
	return fails

# Each Counter kind credits on the event it names, does NOT credit on an event it did not ask
# for, and can only ever credit once per Phase (the latch that stops one Phase undoing two
# steps of M). WALL is asserted on Fae's own Charge beat with the declaration flipped, because
# no Fae Phase is answered by a wall slam — she is the positional/timing/interrupt proof.
func _counters() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"], true)
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var beats := enemy.fsm.states
	var boss_box: Area2D = enemy.get_node("Hurtbox")
	var player_box: Area2D = arena["box"]
	var fails := 0
	var step := BossController.STEP

	# PUNISH — damage landing inside the Tail, and nowhere else.
	boss.reset()
	boss.intensity = 1.5
	boss.begin_phase(beats["Shotgun"])
	boss_box.hurt.emit(1, null)
	fails += _expect("a hit outside the Tail is not a punish", is_equal_approx(boss.intensity, 1.5))
	boss.open_tail()
	boss_box.hurt.emit(1, null)
	fails += _expect("a hit inside the Tail credits PUNISH",
		is_equal_approx(boss.intensity, 1.5 - step))
	boss_box.hurt.emit(1, null)
	fails += _expect("PUNISH credits once per Phase", is_equal_approx(boss.intensity, 1.5 - step))
	boss.end_phase()

	# UNTOUCHED — a Phase the player came through clean, and one they did not.
	boss.intensity = 1.5
	boss.reps = 1
	boss.begin_phase(beats["Rings"])
	player_box.hurt.emit(1, null)
	boss.finish_phase()
	fails += _expect("a hit the player took breaks UNTOUCHED", is_equal_approx(boss.intensity, 1.5))
	boss.end_phase()
	boss.intensity = 1.5
	boss.begin_phase(beats["Rings"])
	boss.finish_phase()
	fails += _expect("a Phase run clean credits UNTOUCHED",
		is_equal_approx(boss.intensity, 1.5 - step))
	boss.finish_phase()
	fails += _expect("UNTOUCHED credits once per Phase", is_equal_approx(boss.intensity, 1.5 - step))
	boss.end_phase()

	# ADDS — the escort's membership is the Counter, and it is also what armours the boss. The
	# summon wind-up runs on an EMPTY floor, so an escort that has not been seen standing yet
	# must not credit: the Counter is the adds coming down, not their absence.
	boss.intensity = 1.5
	boss.begin_phase(beats["Wisps"])
	await get_tree().physics_frame
	fails += _expect("a Phase with no escort yet has not credited (the summon wind-up)",
		is_equal_approx(boss.intensity, 1.5))
	var add: Creature = load("res://characters/enemies/wasp/wasp.tscn").instantiate()
	add.global_position = Vector2(32, 0)
	add.add_to_group("pack_wisp")
	add_child(add)
	await get_tree().physics_frame
	fails += _expect("an ADDS Phase is armoured while its escort stands",
		is_equal_approx(enemy.incoming_damage_scale, boss.escort_armour))
	fails += _expect("a standing escort has not credited", is_equal_approx(boss.intensity, 1.5))
	add.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame
	fails += _expect("an ADDS Phase credits once the escort clears",
		is_equal_approx(boss.intensity, 1.5 - step))
	fails += _expect("the escort's armour comes off with it",
		is_equal_approx(enemy.incoming_damage_scale, 1.0))
	boss.end_phase()

	# WALL — the slam seam, on Fae's rush beat.
	var flit: Behaviour = beats["Flit"]
	var authored: int = flit.counter_kind
	boss.intensity = 1.5
	flit.counter_kind = Behaviour.Counter.WALL
	boss.begin_phase(flit)
	enemy.dash_blocked.emit()
	fails += _expect("a head-on wall slam credits WALL",
		is_equal_approx(boss.intensity, 1.5 - step))
	enemy.dash_blocked.emit()
	fails += _expect("WALL credits once per Phase", is_equal_approx(boss.intensity, 1.5 - step))
	boss.end_phase()
	flit.counter_kind = authored
	boss.intensity = 1.5
	boss.begin_phase(beats["Rings"])
	enemy.dash_blocked.emit()
	fails += _expect("a slam on a Phase that did not ask for it is not a Counter",
		is_equal_approx(boss.intensity, 1.5))
	boss.end_phase()

	if fails == 0:
		print("  ok: counters — punish, wall, adds and untouched each credit once")
	await _close_arena(arena)
	return fails

# Intensity is the design's only escalation axis, so its arithmetic is the highest-value thing
# here: one step up per Phase advance, one step back per clean Counter, clamped at both ends,
# and carried across the Rotation wrap rather than reset by it.
func _intensity() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"], true)
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var fails := 0
	var step := BossController.STEP

	boss.reset()
	fails += _expect("a fight opens at x1.0", boss.intensity == BossController.MIN_INTENSITY)
	boss.jump_to(boss.phases[1])
	fails += _expect("a Phase advance steps Intensity up (%0.2f)" % boss.intensity,
		is_equal_approx(boss.intensity, BossController.MIN_INTENSITY + step))

	# A clean Counter is the brake, and it can't brake past the opening value.
	boss.intensity = 1.5
	boss.reps = 1
	boss.begin_phase(enemy.fsm.states["Rings"])
	boss.finish_phase()
	fails += _expect("a clean Counter steps Intensity back (%0.2f)" % boss.intensity,
		is_equal_approx(boss.intensity, 1.5 - step))
	boss.end_phase()
	boss.intensity = 1.04
	boss.begin_phase(enemy.fsm.states["Rings"])
	boss.finish_phase()
	fails += _expect("Intensity never falls below x1.0", boss.intensity == BossController.MIN_INTENSITY)
	boss.end_phase()

	# It caps, and a lap that wraps ends HIGHER than it began.
	boss.reset()
	boss.intensity = BossController.MAX_INTENSITY
	boss.jump_to(boss.phases[0])
	fails += _expect("Intensity never passes x2.0", boss.intensity == BossController.MAX_INTENSITY)
	boss.reset()
	for i in boss.phases.size() - 1:
		boss.jump_to(boss.phases[i + 1])
	var before := boss.intensity
	boss.jump_to(boss.phases[0])  # the wrap
	fails += _expect("the wrap steps Intensity up (%0.2f -> %0.2f) instead of resetting it"
		% [before, boss.intensity], is_equal_approx(boss.intensity, before + step))
	if fails == 0:
		print("  ok: intensity — one step per Phase, one back per Counter, capped and carried")
	await _close_arena(arena)
	return fails

# The dials Intensity turns, and the floors under them. A hard version of a Boss has to stay a
# readable one: the player's answer to a Phase is positional or timing, so a telegraph, a Tail
# or a rep gap has a length it can never shrink past.
func _timing() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"], true)
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var cycle: Cycle = enemy.fsm.states["Cycle"]
	var fails := 0

	boss.reset()
	fails += _expect("at x1.0 an authored dial is played as authored",
		is_equal_approx(boss.scale_telegraph(0.6), 0.6) \
		and is_equal_approx(boss.scale_tail(1.0), 1.0) \
		and is_equal_approx(boss.scale_gap(0.8), 0.8))

	boss.intensity = BossController.MAX_INTENSITY
	fails += _expect("an escalated Boss telegraphs faster (%0.2f)" % boss.scale_telegraph(0.6),
		boss.scale_telegraph(0.6) < 0.6)
	fails += _expect("a telegraph never shrinks past the readable floor",
		is_equal_approx(boss.scale_telegraph(0.6), BossController.TELEGRAPH_FLOOR))
	fails += _expect("an escalated Boss's Tail is shorter (%0.2f)" % boss.scale_tail(1.0),
		boss.scale_tail(1.0) < 1.0)
	fails += _expect("a Tail never shrinks past its floor",
		is_equal_approx(boss.scale_tail(0.6), BossController.TAIL_FLOOR))
	fails += _expect("an escalated Boss's rep gap is shorter (%0.2f)" % boss.scale_gap(0.8),
		boss.scale_gap(0.8) < 0.8)
	fails += _expect("a rep gap never shrinks past its floor",
		is_equal_approx(boss.scale_gap(0.5), BossController.REP_GAP_FLOOR))
	fails += _expect("an escalated Boss closes faster (%0.0f px/s)" % boss.scale_speed(28.0),
		boss.scale_speed(28.0) > 28.0)
	fails += _expect("an escalated Boss never outruns the player",
		boss.scale_speed(60.0) <= BossController.SPEED_CAP)
	fails += _expect("the Free beat is authored within its cap (%0.1fs)" % cycle.free_beat,
		cycle.free_beat <= BossController.FREE_BEAT_CAP)
	if fails == 0:
		print("  ok: timing dials — shorter with Intensity, never past their floors")
	await _close_arena(arena)
	return fails

# The HP overlay: one Phase per boss may be gated on a quarter health, last in the Rotation and
# marked priority + once, so it fires the instant the window opens and never again. HP never
# drives the Rotation — Intensity does — so this is the one authored cliff on top of it.
func _desperation() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"])
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var beat: Behaviour = enemy.fsm.states["RingStorm"]
	var fails := 0

	fails += _expect("the desperation Phase is last in the Rotation",
		boss.phases[boss.phases.size() - 1] == "RingStorm")
	fails += _expect("it is gated on a quarter-health window (%0.2f)" % beat.health_max,
		beat.health_max > 0.0 and beat.health_max <= 0.25)
	fails += _expect("it is priority and once, so it jumps the queue exactly once",
		beat.priority > 0 and beat.once)
	fails += _expect("it is ineligible while the fight is healthy", not beat.can_run())

	# Through the real damage path, so the leash clock is stamped the way a hit stamps it.
	enemy._on_hurt(enemy.max_health - maxi(int(enemy.max_health * 0.2), 1), null)
	fails += _expect("it opens below a quarter health (%d/%d)" % [enemy.health, enemy.max_health],
		beat.can_run())
	var seen: Array[String] = await _pump(arena, func(list: Array) -> bool:
		return list.has("RingStorm"))
	fails += _expect("the Rotation is taken to it the moment the window opens (%s)" % [seen],
		seen.size() >= 3 and seen[2] == "RingStorm")
	fails += _expect("...and never plays again", not beat.can_run())
	if fails == 0:
		print("  ok: desperation overlay — %s" % [seen])
	await _close_arena(arena)
	return fails

# The Free beat between Phases: pacing, never a window. It is authored in one place on the
# Cycle rather than as a step of the Rotation (a Phase with no Counter is what the static check
# fails), capped, and non-counterable — the Phase it follows is already closed while it runs.
func _free_beat() -> int:
	var arena := await _boss_arena(CASES["fae"]["scene"])
	var enemy: Creature = arena["enemy"]
	var boss: BossController = enemy.get_node("BossController")
	var cycle: Cycle = enemy.fsm.states["Cycle"]
	var fails := 0

	fails += _expect("the Free beat is capped at %0.1fs (%0.1fs)"
		% [BossController.FREE_BEAT_CAP, cycle.free_beat],
		cycle.free_beat <= BossController.FREE_BEAT_CAP)
	fails += _expect("the Free beat is not a Phase of the Rotation", not boss.phases.has("Free"))

	# The pump stops the moment the Rotation is between Phases — the Phase before the Free beat
	# is already closed — leaving the breather still running to be poked at.
	await _pump(arena, func(_list: Array) -> bool:
		return boss.live_phase() == null and String(enemy.fsm.current_state.name) == "Cycle")
	fails += _expect("the Rotation reaches a Free beat at all", boss.live_phase() == null)
	var m := boss.intensity
	# Everything a Counter could ask for, all at once, during the breather.
	enemy.get_node("Hurtbox").hurt.emit(1, null)
	arena["box"].hurt.emit(1, null)
	enemy.dash_blocked.emit()
	await get_tree().physics_frame
	fails += _expect("nothing counters during the Free beat",
		is_equal_approx(boss.intensity, m) and boss.live_phase() == null)
	if fails == 0:
		print("  ok: free beat — non-counterable, capped, one authoring")
	await _close_arena(arena)
	return fails
