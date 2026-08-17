extends Node
## The Mycelium's empowerment seam: a beat gated on `needs_cloud` is only eligible while its
## caster stands in spores, and the body reaches it through a Gate whose fallback is the plain
## version — so the same creature fights a tier above its stat block on coated floor and
## exactly at it on clean floor, with no "powered" mode anywhere.
##
## Every claim here is a silent no-op when it breaks, which is why it needs a test at all: a
## needs_cloud beat that never becomes eligible looks like a creature that simply has one
## attack, and an empowered .tres copied off the plain one looks like it worked.
##   - the ladder actually swaps: the same body takes the strong rung in a field and the plain
##     rung on clean floor.
##   - the printer rule: the cast that LAYS clouds never gains an empowered twin. Read off the
##     scenes rather than asserted about the three built ladders, so a future body wired the
##     wrong way round fails the moment it ships.
##   - the empowered rung fronts a DIFFERENT, harder spell, and nothing is stranded: an
##     empowered beat no Gate lists is a beat the creature can never reach.
## Run: godot --headless --path game res://tests/test_mycelium.tscn

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")
const SPIRALCAP := preload("res://characters/enemies/spiralcap/spiralcap.tscn")
const GOLEM := preload("res://characters/enemies/mould_golem/mould_golem.tscn")
const SPITTER := preload("res://characters/enemies/sporespitter/sporespitter.tscn")
# The whole built roster, printers included — the lint's claim is about which beats did NOT
# get an empowered twin, so leaving the pure printers out would leave it unproven.
const ROSTER := {
	"spiralcap": SPIRALCAP,
	"mould_golem": GOLEM,
	"sporespitter": SPITTER,
	"puffcap": preload("res://characters/enemies/puffcap/puffcap.tscn"),
	"sporefly": preload("res://characters/enemies/sporefly/sporefly.tscn"),
}

func _ready() -> void:
	var fails := 0
	fails += await _ladder_swaps("spiralcap", SPIRALCAP, "TwinSweep", "Sweep", false)
	fails += await _ladder_swaps("mould_golem", GOLEM, "WideRing", "Ring", true)
	fails += await _ladder_swaps("sporespitter", SPITTER, "WideBlam", "Blam", true)
	fails += _printers_never_empower()
	fails += _ladders_are_ladders()
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

# One body, twice: clean floor has to give the plain rung and a coated one the strong rung.
# Both halves matter — a needs_cloud check that never passes and one that always passes are
# both a creature with one attack.
func _ladder_swaps(id: String, scene: PackedScene, fed: String, plain: String,
		wants_target: bool) -> int:
	var beats := [fed, plain]
	var target: Node2D = _target(Vector2(12, 0)) if wants_target else null

	var body := await _spawn(scene, Vector2.ZERO)
	var got := await _await_beat(body, beats)
	var fails := _expect("%s on clean floor took %s, expected %s" % [id, got, plain],
		got == plain)
	body.queue_free()
	await get_tree().physics_frame

	_coat(Vector2.ZERO)
	body = await _spawn(scene, Vector2.ZERO)
	got = await _await_beat(body, beats)
	fails += _expect("%s standing in spores took %s, expected %s" % [id, got, fed], got == fed)
	body.queue_free()
	if target:
		target.queue_free()
	_clear()
	await get_tree().physics_frame

	if fails == 0:
		print("  ok: %s — %s in a field, %s on clean floor" % [id, fed, plain])
	return fails

# Nothing gets paid for the floor it made itself: whatever lays spores is flat wherever it
# stands, which is the one thing stopping a room of printers spiralling.
func _printers_never_empower() -> int:
	var fails := 0
	for id in ROSTER:
		var body: Creature = ROSTER[id].instantiate()
		for beat in body.get_node("FSM").get_children():
			if not (beat is Cast) or beat.spell == null or not _prints(beat.spell):
				continue
			fails += _expect("%s/%s lays spores, so it must never be the empowered beat"
				% [id, beat.name], not beat.needs_cloud)
		body.free()
	if fails == 0:
		print("  ok: printers — every cloud-laying beat is flat")
	return fails

# A Gate rung gated on spores has to front a different, harder spell than the plain rung
# behind it, sit ahead of it in the ladder, and be listed by a Gate at all — an empowered beat
# nothing dispatches is content the player can never meet.
func _ladders_are_ladders() -> int:
	var fails := 0
	for id in ROSTER:
		var body: Creature = ROSTER[id].instantiate()
		var fsm: Node = body.get_node("FSM")
		var listed: Array[String] = []
		for gate in fsm.get_children():
			if not (gate is Gate):
				continue
			listed.append_array(gate.beats)
			var fed: Cast = null
			for beat_name in gate.beats:
				var beat := fsm.get_node_or_null(String(beat_name)) as Cast
				if beat == null or beat.spell == null:
					continue
				if beat.needs_cloud:
					fed = beat
					fails += _expect("%s/%s: the empowered rung must lead the ladder %s"
						% [id, beat.name, gate.beats], gate.beats[0] == beat.name)
					continue
				if fed == null:
					continue
				# The first plain casting rung behind it is the one it replaces.
				fails += _expect("%s/%s reuses %s's own spell instead of its own numbers"
					% [id, fed.name, beat.name], fed.spell != beat.spell)
				fails += _expect("%s/%s (%d) is no stronger than %s (%d)"
					% [id, fed.name, _power(fed.spell), beat.name, _power(beat.spell)],
					_power(fed.spell) > _power(beat.spell))
				fed = null
		for beat in fsm.get_children():
			if beat is Behaviour and beat.needs_cloud:
				fails += _expect("%s/%s is gated on spores but no Gate lists it"
					% [id, beat.name], beat.name in listed)
		body.free()
	if fails == 0:
		print("  ok: ladders — every empowered rung leads a Gate with a plain fallback")
	return fails

# A cast lays floor if it IS the field (Whumf) or if its shot leaves one where it stops.
func _prints(spell: SpellResource) -> bool:
	if spell is WhumfResource:
		return true
	if not (spell is BulletSpellResource) or spell.bullet == null:
		return false
	for behaviour in spell.bullet.behaviours:
		if behaviour is SporePayload:
			return true
	return false

func _power(spell: SpellResource) -> int:
	var amount: ScalingProfile = spell.get("damage")
	return amount.compute(0) if amount else 0

# A coated room, laid the way a lob leaves it: enemy-side patches on a grid one cloud wide, so
# wherever the body parks inside it, it is standing in spores.
func _coat(center: Vector2, reach: int = 3) -> void:
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			var cloud: SporeCloud = CLOUD.instantiate()
			cloud.position = center + Vector2(x, y) * SporeCloud.RADIUS
			cloud.foe = true
			cloud.target_groups = ["player"]
			cloud.lifetime = 60.0
			add_child(cloud)

# The first of `beats` the body enters. Returns whatever it settled on when nothing does, so
# the failure names the state it got stuck in.
func _await_beat(body: Creature, beats: Array, ms: int = 20000) -> String:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if _state(body) in beats:
			return _state(body)
	return _state(body)

func _spawn(scene: PackedScene, at: Vector2) -> Creature:
	var body: Creature = scene.instantiate()
	body.position = at
	add_child(body)
	await get_tree().physics_frame
	_wake(body)
	return body

func _state(body: Creature) -> String:
	return String(body.fsm.current_state.name) if body.fsm.current_state else ""

func _target(at: Vector2) -> CharacterBody2D:
	var target := CharacterBody2D.new()
	target.collision_layer = 16
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	target.add_child(shape)
	target.add_to_group("player")
	target.position = at
	add_child(target)
	return target

func _clear() -> void:
	for cloud in get_tree().get_nodes_in_group(SporeCloud.GROUP):
		cloud.free()

# Headless never renders, so the creature's off-screen sleeper would freeze its AI.
func _wake(body: Creature) -> void:
	for child in body.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	body.process_mode = Node.PROCESS_MODE_INHERIT

func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1
