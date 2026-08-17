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
##
## Then the splitters, whose whole point is what stands up after they fall — a seam that fails
## just as quietly, since a body that spawns nothing on death is only a body that died:
##   - a bloatcap leaves its brood, inside the spread it authored.
##   - a clustercap leaves clusterlings that are alive and lobbing, not props, and that cannot
##     split again.
##   - a brood body dies loudly (a ring of pods, wider off coated floor) and then is GONE.
## Run: godot --headless --path game res://tests/test_mycelium.tscn

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")
const SPIRALCAP := preload("res://characters/enemies/spiralcap/spiralcap.tscn")
const GOLEM := preload("res://characters/enemies/mould_golem/mould_golem.tscn")
const SPITTER := preload("res://characters/enemies/sporespitter/sporespitter.tscn")
const BLOATCAP := preload("res://characters/enemies/bloatcap/bloatcap.tscn")
const CLUSTERCAP := preload("res://characters/enemies/clustercap/clustercap.tscn")
const MYCELING := preload("res://characters/enemies/bloatcap/myceling.tscn")
const CLUSTERLING := preload("res://characters/enemies/clustercap/clusterling.tscn")
# The whole built roster, printers included — the lint's claim is about which beats did NOT
# get an empowered twin, so leaving the pure printers out would leave it unproven.
const ROSTER := {
	"spiralcap": SPIRALCAP,
	"mould_golem": GOLEM,
	"sporespitter": SPITTER,
	"puffcap": preload("res://characters/enemies/puffcap/puffcap.tscn"),
	"sporefly": preload("res://characters/enemies/sporefly/sporefly.tscn"),
	"bloatcap": BLOATCAP,
	"clustercap": CLUSTERCAP,
	# The broods are not roster entries — no stat sheet, no kill count — but they cast, so the
	# same two rules have to hold for them or the rules aren't rules.
	"myceling": MYCELING,
	"clusterling": CLUSTERLING,
}

func _ready() -> void:
	var fails := 0
	fails += await _ladder_swaps("spiralcap", SPIRALCAP, "TwinSweep", "Sweep", false)
	fails += await _ladder_swaps("mould_golem", GOLEM, "WideRing", "Ring", true)
	fails += await _ladder_swaps("sporespitter", SPITTER, "WideBlam", "Blam", true)
	fails += _printers_never_empower()
	fails += _ladders_are_ladders()
	fails += await _bloatcap_leaves_a_brood()
	fails += await _clustercap_comes_apart()
	fails += await _swells_under_damage("bloatcap", BLOATCAP, "Waddle", 40)
	fails += await _swells_under_damage("clustercap", CLUSTERCAP, "Walk", 60)
	fails += await _brood_pops("myceling", MYCELING)
	fails += await _brood_pops("clusterling", CLUSTERLING)
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

# Kill a splitter and collect what stood up, holding it to both promises its stat sheet makes:
# how many, and inside what radius. A spread that doesn't hold is three bodies stacked on one
# pixel, which is one body as far as the player can tell. Reads the authored numbers rather
# than restating them, so retuning a split retunes the test with it. What the brood then DOES
# is the caller's business.
func _brood_of(id: String, scene: PackedScene, at: Vector2) -> Dictionary:
	var body := await _spawn(scene, at)
	var split: DeathSpawn = body.data.death_spawns[0]
	body.die()
	var brood := await _await_spawns(split.scene, split.count)
	var fails := _expect("a dead %s left %d bodies, expected %d"
		% [id, brood.size(), split.count], brood.size() == split.count)
	# Measured off where the corpse stood, not off wherever the last frame of the throe
	# pushed it.
	var reach := split.spread_tiles * GameConstants.PX_PER_TILE
	for spawn in brood:
		fails += _expect("a %s spawn landed %.0fpx out, past the %.0fpx spread"
			% [id, spawn.global_position.distance_to(at), reach],
			spawn.global_position.distance_to(at) <= reach + 0.01)
	return {"brood": brood, "fails": fails, "count": split.count}

func _bloatcap_leaves_a_brood() -> int:
	var got := await _brood_of("bloatcap", BLOATCAP, Vector2(400, 0))
	for spawn in got.brood:
		spawn.queue_free()
	_clear()
	await get_tree().physics_frame
	if got.fails == 0:
		print("  ok: bloatcap — bursts into %d mycelings inside its spread" % got.count)
	return got.fails

# The turrets a clustercap leaves have to be turrets: killing it multiplies the room's fire,
# so "three clusterlings exist" is not the claim — three of them shooting is. And the split
# stops here: a brood that could split again is a room that never ends, which is why the
# clusterling carries no stat sheet at all — no `data` is no `death_spawns`, structurally.
func _clustercap_comes_apart() -> int:
	var target := _target(Vector2(830, 0))
	var got := await _brood_of("clustercap", CLUSTERCAP, Vector2(800, 0))
	var brood: Array = got.brood
	var fails: int = got.fails
	for spawn in brood:
		_wake(spawn)
	for spawn in brood:
		var beat := await _await_beat(spawn, ["Lob"], 8000)
		fails += _expect("a clusterling settled in %s instead of lobbing" % beat, beat == "Lob")
		fails += _expect("a clusterling came up dead", spawn.health > 0)
		fails += _expect("a clusterling can split again", spawn.data == null)
	for spawn in brood:
		spawn.queue_free()
	target.queue_free()
	_clear()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: clustercap — comes apart into %d lobbing clusterlings that can't split"
			% got.count)
	return fails

# The splitters inflate as you shoot them, which is the read the player fights off: a fat one
# is a nearly-dead one. It's a health window on a second walk behind the same Gate, and it
# breaks silently in two directions — the window never opening, or the Gate never being asked
# again mid-chase, which is what a walk with no clock on it does. Both look like a body that
# simply never swells, so this drives a real body from full health to half and watches.
func _swells_under_damage(id: String, scene: PackedScene, plain: String, reach: float) -> int:
	var target := _target(Vector2(1600 + reach, 0))
	var body := await _spawn(scene, Vector2(1600, 0))
	var beats := ["Swell", plain]
	var got := await _await_beat(body, beats)
	var fails := _expect("%s at full health walks as %s, not %s" % [id, got, plain],
		got == plain)
	body.hurtbox.hurt.emit(body.max_health / 2 + 1, null)
	got = await _await_beat(body, ["Swell"], 8000)
	fails += _expect("%s under half health settled in %s instead of swelling" % [id, got],
		got == "Swell")
	fails += _expect("%s swelled without the swollen art (playing %s)"
		% [id, body.sprite.animation], body.sprite.animation == &"swell")
	body.queue_free()
	target.queue_free()
	_clear()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: %s — walks flat, swells under half health" % id)
	return fails

# A brood body dies loudly: it throws a ring of pods, a wider one off coated floor, and then
# it is GONE. The last clause is the one that bit — a throe hands off through the same
# eligibility every other hand-off asks, so an overkilled corpse (health below zero, outside
# every health window) or one waiting on a cooldown simply lies there on its last frame,
# playing dead in the literal sense. Checked on both floors, since the empowered rung is the
# one a player standing in the dungeon's own spores actually meets.
func _brood_pops(id: String, scene: PackedScene) -> int:
	var fails := 0
	for coated in [false, true]:
		var at := Vector2(2400, 0)
		if coated:
			_coat(at)
		_clear_bullets()
		var body := await _spawn(scene, at)
		# Overkill on purpose: this is what a real killing blow does, and what used to strand
		# the corpse. Straight through the hurtbox so it's the same path a bullet takes.
		body.hurtbox.hurt.emit(body.max_health * 3, null)
		var watched := await _watch_throe(body)
		var want := "WideRing" if coated else "Ring"
		var floor_name := "in a field" if coated else "on clean floor"
		fails += _expect("%s %s burst as %s, expected %s"
			% [id, floor_name, watched.beat, want], watched.beat == want)
		fails += _expect("%s %s left no pods behind" % [id, floor_name], watched.pods > 0)
		fails += _expect("%s %s never cleared its corpse" % [id, floor_name], watched.freed)
		_clear()
		_clear_bullets()
		await get_tree().physics_frame
	if fails == 0:
		print("  ok: %s — rings on death, a wider one in a field, and the body goes" % id)
	return fails

# A throe is three things happening across a handful of frames — the rung it picks, the pods
# it throws, the corpse going away — and they don't line up in a fixed order, so one loop
# watches all three at once rather than sampling each at a moment that might be too early.
func _watch_throe(body: Creature, ms: int = 8000) -> Dictionary:
	var out := {"beat": "nothing", "pods": 0, "freed": false}
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(body):
			if out.beat == "nothing" and _state(body) in ["WideRing", "Ring"]:
				out.beat = _state(body)
		else:
			out.freed = true
		out.pods = maxi(out.pods, _bullets())
		if out.freed and out.pods > 0:
			break
		await get_tree().physics_frame
	return out

func _bullets() -> int:
	return get_tree().get_nodes_in_group("bullets").size()

func _clear_bullets() -> void:
	for bullet in get_tree().get_nodes_in_group("bullets"):
		bullet.free()

# Everything a death throe leaves lands deferred, a frame or more after the body is gone.
func _await_spawns(scene: PackedScene, want: int, ms: int = 8000) -> Array[Creature]:
	var deadline := Time.get_ticks_msec() + ms
	var found: Array[Creature] = []
	while Time.get_ticks_msec() < deadline and found.size() < want:
		await get_tree().physics_frame
		found.clear()
		for child in get_children():
			if child is Creature and child.scene_file_path == scene.resource_path:
				found.append(child)
	return found

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
