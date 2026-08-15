extends Node
## The engine seams the shared deepwood pool added, which no glade content exercises:
##   - BounceBehaviour: a wall hit reflects the bullet instead of expiring it, restarts its
##     flight leg, and grows its damage — so Zoing is a ricochet, not a shot that dies on
##     the first wall. Needs real terrain, so it's here rather than in test_bullet_spell.
##   - Creature.damage_absorber: a creature casting Nope on itself soaks damage into the
##     bubble's pool instead of its health, and the channel still releases — the moss golem
##     would otherwise sit shielded forever with a caster that refuses every later cast.
##   - The snake's cornered volley, which only fires with a wall at its back.
##   - Halp's minion, whose FSM was ported from the retired behaviour library to
##     Tether/Approach/Cast — nothing else loads that scene, so a mis-wired hand-off would
##     ship as a squad that stands still.
##   - Pack aggro (the grimlings): both triggers (a hit, and a plain sighting), the relay, the
##     lost_grace window a called member needs to reach a fight it can't see yet, and the one
##     group the three grimling variants share. None of it exists with fewer than several
##     creatures at once.
## The animal sub-biome adds three more, all of which are silent no-ops rather than crashes
## when they break — the worst kind to ship:
##   - ChargeDash driving a Creature. The dash lives in the spell, not the behaviour, so a
##     thornback whose start_dash never fires still telegraphs, still sheds its flank bullets
##     and still cycles states; it just never goes anywhere.
##   - The razorback's wall slam, which needs real terrain to hit head-on.
##   - Creature.death_state: a parting shot fired by a creature that is already dead, and the
##     freeing that has to happen anyway once that beat hands off.
##   - Behaviour.damage_scale at zero — the mole underground is untouchable, not merely
##     armoured, and takes damage again the moment it surfaces.
## The mimic sub-biome adds two more of the same kind:
##   - Blink, the one effect that MOVES its caster. A shade carries no movement behaviour at
##     all, so any position change is the hop — and a blink hemmed in by walls has to refuse
##     rather than post the shade through one.
##   - Oop, the burst that takes its caster with it. A cinderstone that fires and survives is a
##     mine that re-arms forever — and the player's side of the same spell, a summoned mine
##     that has to arm, trigger on an enemy, and go up with the blast it was handed.
## Run: godot --headless --path game res://tests/test_deepwood.tscn

const SNAKE := preload("res://characters/enemies/snake/snake.tscn")
const SHADE := preload("res://characters/enemies/shade/shade.tscn")
const CINDERSTONE := preload("res://characters/enemies/cinderstone/cinderstone.tscn")
const SPROUTLING := preload("res://characters/enemies/sproutling/sproutling.tscn")
const OOP := preload("res://characters/player/spells/oop/oop2.tres")
const BLINK := preload("res://characters/player/spells/blink/blink2.tres")
const GOLEM := preload("res://characters/enemies/moss_golem/moss_golem.tscn")
const GRIMLING := preload("res://characters/enemies/grimling/grimling.tscn")
const THORNBACK := preload("res://characters/enemies/thornback/thornback.tscn")
const RAZORBACK := preload("res://characters/enemies/razorback/razorback.tscn")
const GRIMLORD := preload("res://characters/enemies/grimlord/grimlord.tscn")
const MOLE := preload("res://characters/enemies/mole/mole.tscn")
const SHARD := preload("res://characters/enemies/shard_grimling/shard_grimling.tscn")
const WISP := preload("res://characters/enemies/wisp_grimling/wisp_grimling.tscn")
const ZOING := preload("res://characters/player/spells/zoing/zoing2.tres")
const HALP := preload("res://characters/player/spells/halp/halp2.tres")
const BULLET := preload("res://items/bullets/base_bullet.tscn")
# Terrain is physics layer 1 and has no GameConstants entry — the enemy scenes spell it
# out the same way (collision_mask = 33 is terrain + enemies).
const LAYER_TERRAIN := 1

# A lambda captures locals by value, so the bullet tally has to live on the node.
var _shots := 0
var _mine_damage := 0

func _ready() -> void:
	var fails := 0
	fails += await _bounce_reflects()
	fails += await _bounce_is_finite()
	fails += await _creature_shield()
	fails += await _snake_corners()
	fails += await _halp_minion_fights()
	fails += await _pack_relays()
	fails += await _pack_hears_detection()
	fails += await _mixed_knot()
	fails += await _charge_dash_drives_its_caster()
	fails += await _razorback_slams_a_wall()
	fails += await _grimlord_fires_a_parting_ring()
	fails += await _burrowed_mole_is_untouchable()
	fails += await _shade_blinks()
	fails += await _cinderstone_takes_itself_with_it()
	fails += await _oop_mine_arms_and_blows()
	fails += await _player_blink_hops_along_aim()
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

# Fire a Zoing bullet straight at a wall: it must survive the hit, come away travelling
# in a different direction, and hit harder on the new leg.
func _bounce_reflects() -> int:
	var wall := _wall(Vector2(40, 0), Vector2(8, 80))
	var b := _fire_zoing(Vector2.ZERO, Vector2.RIGHT)
	var before := b.computed_damage()
	var deadline := Time.get_ticks_msec() + 4000
	while is_instance_valid(b) and b.velocity.x > 0.0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := 0
	if not is_instance_valid(b):
		print("  FAIL: bounce bullet expired on the wall instead of reflecting")
		fails += 1
	else:
		fails += _expect("reflected bullet travels back off the wall", b.velocity.x < 0.0)
		fails += _expect("reflected bullet keeps its speed",
			absf(b.velocity.length() - b.speed_px()) < 1.0)
		fails += _expect("bounce grew the shot's damage (%d -> %d)"
			% [before, b.computed_damage()], b.computed_damage() > before)
		b.queue_free()
	wall.queue_free()
	await get_tree().physics_frame
	return fails

# The bounce budget must run out: a bullet trapped in a box eventually expires rather than
# ricocheting forever. Zoing authors 3 bounces, so leg 4 ends it.
func _bounce_is_finite() -> int:
	var walls := [
		_wall(Vector2(30, 0), Vector2(8, 60)), _wall(Vector2(-30, 0), Vector2(8, 60)),
		_wall(Vector2(0, 30), Vector2(60, 8)), _wall(Vector2(0, -30), Vector2(60, 8)),
	]
	var b := _fire_zoing(Vector2.ZERO, Vector2.RIGHT)
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(b) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("a boxed-in ricochet eventually expires", not is_instance_valid(b))
	if is_instance_valid(b):
		b.queue_free()
	for w in walls:
		w.queue_free()
	await get_tree().physics_frame
	return fails

# Damage while the golem holds its own Nope: the pool eats it, health is untouched, and the
# channel still ends so the golem goes on to its ring.
func _creature_shield() -> int:
	var target := _target(Vector2(30, 0))
	var golem: Creature = GOLEM.instantiate()
	add_child(golem)
	await get_tree().physics_frame
	_wake(golem)

	# Wait for the Shell beat to actually put the bubble up.
	var deadline := Time.get_ticks_msec() + 8000
	while golem.damage_absorber == null and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("golem's Nope registered itself as its damage absorber",
		golem.damage_absorber != null)
	if golem.damage_absorber != null:
		var hp := golem.health
		golem.hurtbox.hurt.emit(20, self)
		fails += _expect("shielded damage did not reach health", golem.health == hp)
		# Overwhelm the pool (90) — past it the bubble breaks and damage lands again.
		golem.hurtbox.hurt.emit(200, self)
		fails += _expect("damage past the absorb pool reaches health", golem.health < hp)
	# The channel must release on its own (the cast_time cap), or the caster stays busy
	# forever and the golem never fires again.
	deadline = Time.get_ticks_msec() + 8000
	while golem.damage_absorber != null and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("golem's channel released the bubble", golem.damage_absorber == null)

	golem.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# Back the snake against a wall so its flee corners and the twin ricochet actually goes off.
func _snake_corners() -> int:
	var walls := [
		_wall(Vector2(22, 0), Vector2(8, 80)), _wall(Vector2(-22, 0), Vector2(8, 80)),
		_wall(Vector2(0, 22), Vector2(80, 8)), _wall(Vector2(0, -22), Vector2(80, 8)),
	]
	_shots = 0
	var counter := func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
			_shots += 1
	get_tree().root.child_entered_tree.connect(counter)

	var target := _target(Vector2(14, 0))
	var snake: Creature = SNAKE.instantiate()
	add_child(snake)
	await get_tree().physics_frame
	_wake(snake)

	var deadline := Time.get_ticks_msec() + 12000
	while _shots < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	# A ParallelPattern of 2 means one cast is already two bullets.
	var fails := _expect("cornered snake fired its twin ricochet (%d shots)" % _shots, _shots >= 2)

	get_tree().root.child_entered_tree.disconnect(counter)
	snake.queue_free()
	target.queue_free()
	for w in walls:
		w.queue_free()
	await get_tree().physics_frame
	return fails

# Stand a Halp minion up the way the spawner does — inject the tier's spell, give it a
# hostile — and assert the ported FSM walks it into range and fires on the player's layer.
func _halp_minion_fights() -> int:
	_shots = 0
	var counter := func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_PLAYER_BULLETS:
			_shots += 1
	get_tree().root.child_entered_tree.connect(counter)

	var minion: Creature = HALP.minion_scenes[0].instantiate()
	minion.max_health = HALP.minion_health
	for state in minion.get_node("FSM").get_children():
		if state is Cast:
			state.spell = HALP.minion_spell
	add_child(minion)
	await get_tree().physics_frame
	_wake(minion)

	# A hostile on the enemy physics layer and in the enemies group, so the minion's probes
	# both collide with it and recognise it as a target.
	var foe := CharacterBody2D.new()
	foe.collision_layer = 32
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	foe.add_child(shape)
	foe.add_to_group("enemies")
	foe.position = Vector2(30, 0)
	add_child(foe)

	var deadline := Time.get_ticks_msec() + 10000
	while _shots == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("Halp minion closed and fired a player-layer bullet", _shots > 0)

	get_tree().root.child_entered_tree.disconnect(counter)
	minion.queue_free()
	foe.queue_free()
	await get_tree().physics_frame
	return fails

# Detection is the other half of the trigger: a grimling that merely SEES the target has to
# call the pack, with nobody hurt. Only the near one is inside its own detect probe, so the
# far one can hear about the target exclusively through the call.
func _pack_hears_detection() -> int:
	var target := _target(Vector2.ZERO)
	var deaf := _grimling(Vector2(116, 0))  # target sits outside its own 10-tile detect probe
	await get_tree().physics_frame
	await get_tree().physics_frame
	_wake(deaf)

	# Control: alone, it must NOT engage — otherwise the wake below proves nothing.
	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	var fails := _expect("a lone grimling can't see a target 14 tiles off", _calm(deaf))

	# Now a packmate close enough to see it, and close enough to be heard.
	var spotter := _grimling(Vector2(60, 0))
	await get_tree().physics_frame
	_wake(spotter)
	var deadline := Time.get_ticks_msec() + 1000
	while _calm(deaf) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("a sighting alone (nobody hurt) calls the pack", not _calm(deaf))

	if fails == 0:
		print("  ok: grimling pack — a sighting rallies a packmate that saw nothing")
	spotter.queue_free()
	deaf.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# Hurting one grimling has to pull in the others, and the pull has to relay: the far one
# sits outside the radius of the grimling actually hit, so it can only wake if the middle one
# passed the call on. The target is parked way out of everyone's detect probe, so a pack call
# is the ONLY thing that can wake them — which also means the woken pair have no line of
# sight to it, making this the check that Chase's lost_grace holds them long enough to close
# instead of bouncing them back to Idle on the first frame.
func _pack_relays() -> int:
	var hit := _grimling(Vector2.ZERO)
	var middle := _grimling(Vector2(56, 0))   # inside hit's 8-tile radius
	var far := _grimling(Vector2(112, 0))     # outside it, inside middle's
	var target := _target(Vector2(400, 0))
	# Two frames: fsm.start() and Pack's hookup are both deferred, and current_state stays
	# null until that queue flushes.
	await get_tree().physics_frame
	await get_tree().physics_frame
	for g in [hit, middle, far]:
		_wake(g)

	var fails := 0
	fails += _expect("pack starts calm (nothing engaged on its own)",
		_calm(hit) and _calm(middle) and _calm(far))

	# call_group is immediate, so the whole cascade resolves inside this emit.
	hit.hurtbox.hurt.emit(1, self)
	fails += _expect("the grimling that was hit engages", _state(hit) == "Chase")
	fails += _expect("a packmate in radius answers the call", _state(middle) == "Chase")
	fails += _expect("the relay reaches a packmate out of the hit one's radius",
		_state(far) == "Chase")

	# Still closing a second later with the target far out of probe range: without
	# lost_grace the LOS gate drops the pursuit the frame it starts.
	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	fails += _expect("lost_grace keeps a called member closing without line of sight",
		_state(far) == "Chase")

	if fails == 0:
		print("  ok: grimling pack — hit relays through the pack, called members keep closing")
	for g in [hit, middle, far]:
		g.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The knot is mixed: the three grimlings are one pack group, so a wisp — the variant built
# to find you first, seeing 18 tiles out and calling from 14 — wakes a shard grimling that
# has neither the sight nor the radius to have joined on its own. A typo in either scene's
# group would leave the variants hunting alone and nothing else would notice.
func _mixed_knot() -> int:
	var target := _target(Vector2.ZERO)
	var shard := _grimling(Vector2(160, 0), SHARD)  # target is past its 12-tile detect probe
	await get_tree().physics_frame
	await get_tree().physics_frame
	_wake(shard)

	var until := Time.get_ticks_msec() + 1000
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	var fails := _expect("a lone shard grimling can't see a target 20 tiles off", _calm(shard))

	var wisp := _grimling(Vector2(100, 0), WISP)
	await get_tree().physics_frame
	_wake(wisp)
	var deadline := Time.get_ticks_msec() + 1000
	while _calm(shard) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("a wisp's sighting calls the shard grimling into the fight",
		not _calm(shard))

	if fails == 0:
		print("  ok: grimling pack — the variants share one knot")
	wisp.queue_free()
	shard.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The dash lives in ChargeDash's effect, which calls start_dash on whoever cast it — so the
# only proof it reached the creature is the creature moving. A thornback that never dashes
# looks identical from the outside: same wind-up, same flank bullets, same state cycle.
func _charge_dash_drives_its_caster() -> int:
	var target := _target(Vector2(40, 0))
	var boar: Creature = await _spawn(THORNBACK, Vector2.ZERO)

	var dashed := false
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline and not dashed:
		await get_tree().physics_frame
		dashed = boar.is_dashing()
	# It must move under the dash, not merely be flagged as dashing.
	var launched := boar.global_position
	deadline = Time.get_ticks_msec() + 4000
	while boar.is_dashing() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	# The clock lapsing and the drive standing down are one physics frame apart.
	await get_tree().physics_frame

	var fails := _expect("thornback's ChargeDash actually started a dash", dashed)
	fails += _expect("the dash moved the thornback (%.0f px)"
		% launched.distance_to(boar.global_position),
		launched.distance_to(boar.global_position) > 24.0)
	fails += _expect("the caster can act again once the dash ends", boar.can_act)

	if fails == 0:
		print("  ok: charge dash — the spell drives its caster, then hands control back")
	boar.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# Boxed in tight so every charge ends against a wall head-on: the razorback has no recovery
# beat, so the wall stun is its ONLY punish window and the whole point of the variant.
func _razorback_slams_a_wall() -> int:
	var walls := [
		_wall(Vector2(40, 0), Vector2(8, 120)), _wall(Vector2(-40, 0), Vector2(8, 120)),
		_wall(Vector2(0, 40), Vector2(120, 8)), _wall(Vector2(0, -40), Vector2(120, 8)),
	]
	var target := _target(Vector2(20, 0))
	var boar: Creature = await _spawn(RAZORBACK, Vector2(-20, 0))

	var deadline := Time.get_ticks_msec() + 15000
	while _state(boar) != "Stun" and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("a head-on wall hit stunned the razorback (state %s)"
		% _state(boar), _state(boar) == "Stun")

	if fails == 0:
		print("  ok: razorback — the dash slams into a wall and opens the punish window")
	boar.queue_free()
	target.queue_free()
	for w in walls:
		w.queue_free()
	await get_tree().physics_frame
	return fails

# Killing the grimlord must not free it outright: death_state hands the FSM one last beat,
# the ring goes off from a creature already at zero health, and only then is it gone.
func _grimlord_fires_a_parting_ring() -> int:
	_shots = 0
	var counter := func(n: Node) -> void:
		if n is BaseBullet and n.collision_layer == GameConstants.LAYER_ENEMY_BULLETS:
			_shots += 1
	get_tree().root.child_entered_tree.connect(counter)

	var target := _target(Vector2(400, 0))  # far out of its probes: no ordinary shot can fire
	var alpha: Creature = await _spawn(GRIMLORD, Vector2.ZERO)
	await get_tree().physics_frame
	var fails := _expect("nothing fired before the grimlord died", _shots == 0)

	alpha.hurtbox.hurt.emit(alpha.max_health * 2, self)
	fails += _expect("the grimlord entered its death beat instead of vanishing",
		is_instance_valid(alpha) and _state(alpha) == "DeathBurst")

	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(alpha) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("the parting ring fired (%d bullets)" % _shots, _shots >= 8)
	fails += _expect("the grimlord is freed once the death beat hands off",
		not is_instance_valid(alpha))

	if fails == 0:
		print("  ok: grimlord — death_state buys one last ring, then the creature goes")
	get_tree().root.child_entered_tree.disconnect(counter)
	if is_instance_valid(alpha):
		alpha.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# damage_scale = 0 has to mean immune, not "1 damage a hit": the mole spends most of the
# fight underground, and a 1-per-hit floor would let a fast spell kill it down there.
func _burrowed_mole_is_untouchable() -> int:
	var target := _target(Vector2(80, 0))
	var mole: Creature = await _spawn(MOLE, Vector2.ZERO)

	var deadline := Time.get_ticks_msec() + 10000
	while _state(mole) != "Burrow" and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("the mole went under", _state(mole) == "Burrow")

	var hp := mole.health
	for _i in 20:
		mole.hurtbox.hurt.emit(5, self)
	fails += _expect("nothing lands on a submerged mole", mole.health == hp)

	# Surfacing has to give the armour back — the punish window is the whole fight.
	deadline = Time.get_ticks_msec() + 10000
	while _state(mole) != "Surface" and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("the mole surfaced", _state(mole) == "Surface")
	mole.hurtbox.hurt.emit(5, self)
	fails += _expect("a surfaced mole takes damage again", mole.health < hp)

	if fails == 0:
		print("  ok: mole — the burrow is untouchable, the surface beat is not")
	mole.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

func _spawn(scene: PackedScene, at: Vector2) -> Creature:
	var c: Creature = scene.instantiate()
	c.position = at
	add_child(c)
	await get_tree().physics_frame
	_wake(c)
	return c

func _grimling(at: Vector2, scene: PackedScene = GRIMLING) -> Creature:
	var c: Creature = scene.instantiate()
	c.position = at
	add_child(c)
	return c

func _state(c: Creature) -> String:
	return String(c.fsm.current_state.name) if c.fsm.current_state else ""

func _calm(c: Creature) -> bool:
	return _state(c) in ["Idle", "Wander"]

func _fire_zoing(from: Vector2, dir: Vector2) -> BaseBullet:
	var b: BaseBullet = BULLET.instantiate()
	b.data = ZOING.bullet
	b.damage = ZOING.damage
	b.base_direction = dir
	b.global_position = from
	b.collision_layer = GameConstants.LAYER_PLAYER_BULLETS
	add_child(b)
	return b

# The shade never walks — Idle, Volley and Blink all plant it — so the only thing that can
# move it is the blink effect. Boxed in, the same blink has to leave it exactly where it is:
# every candidate landing spot is through a wall, and refusing beats teleporting into rock.
func _shade_blinks() -> int:
	var target := _target(Vector2(40, 0))
	var shade: Creature = SHADE.instantiate()
	add_child(shade)
	await get_tree().physics_frame
	_wake(shade)
	var origin := shade.global_position
	var deadline := Time.get_ticks_msec() + 8000
	while shade.global_position == origin and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("the shade blinked off its spot", shade.global_position != origin)
	shade.queue_free()

	var walls := [
		_wall(Vector2(16, 0), Vector2(8, 80)), _wall(Vector2(-16, 0), Vector2(8, 80)),
		_wall(Vector2(0, 16), Vector2(80, 8)), _wall(Vector2(0, -16), Vector2(80, 8)),
	]
	target.position = Vector2(8, 0)
	var boxed: Creature = SHADE.instantiate()
	add_child(boxed)
	await get_tree().physics_frame
	_wake(boxed)
	var penned := boxed.global_position
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("a walled-in blink refused rather than teleporting through",
		boxed.global_position == penned)

	if fails == 0:
		print("  ok: shade — the blink moves its caster, and refuses through walls")
	boxed.queue_free()
	target.queue_free()
	for w in walls:
		w.queue_free()
	await get_tree().physics_frame
	return fails

# Oop is the only spell that kills the caster that cast it: step into a cinderstone's trigger
# and it fuses, blows, and is gone. Surviving its own blast would leave the trap re-arming.
func _cinderstone_takes_itself_with_it() -> int:
	var target := _target(Vector2(12, 0))
	var wood: Creature = CINDERSTONE.instantiate()
	add_child(wood)
	await get_tree().physics_frame
	_wake(wood)
	var deadline := Time.get_ticks_msec() + 8000
	while is_instance_valid(wood) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var fails := _expect("the cinderstone went up with its own blast", not is_instance_valid(wood))
	if fails == 0:
		print("  ok: cinderstone — the Oop burst takes its caster with it")
	if is_instance_valid(wood):
		wood.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	return fails

# The player's half of Oop: the cast drops a mine a tile ahead of the aim, it arms on its own
# clock, and then it is a contact trap — the first thing it hunts to TOUCH it sets it off.
# It has no AI, no health and no hurtbox, so it can't chase, be drawn away, or be shot down;
# every one of those is a line away from turning a hazard back into a target.
func _oop_mine_arms_and_blows() -> int:
	_mine_damage = 0
	# Well clear of the origin: the cinderstone beat above leaves a live blast there.
	const AWAY := Vector2(300, 300)
	var caster := Node2D.new()
	caster.set_script(preload("res://tests/support/stub_caster.gd"))
	caster.position = AWAY
	add_child(caster)
	var spell_caster := SpellCaster.new()
	caster.add_child(spell_caster)
	var foe := _foe(AWAY + Vector2(60, 0))   # well outside the trigger to start with
	await get_tree().physics_frame

	var fails := _expect("the cast went off", spell_caster.cast(OOP))
	var mine: Node2D = null
	var spawned := Time.get_ticks_msec() + 3000
	while mine == null and Time.get_ticks_msec() < spawned:
		await get_tree().physics_frame
		mine = get_tree().root.find_child("Mine", false, false) as Node2D
	fails += _expect("the cast dropped a mine", mine != null)
	if mine == null:
		caster.queue_free()
		foe.queue_free()
		await get_tree().physics_frame
		return fails
	# stub_caster aims RIGHT, so the drop lands one tile east of the caster.
	var drop := AWAY + Vector2(GameConstants.PX_PER_TILE, 0)
	fails += _expect("the mine landed a tile along the aim", mine.global_position == drop)

	# Armed, with the enemy across the room: a mine waits, it does not hunt.
	var settle := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < settle:
		await get_tree().physics_frame
	fails += _expect("an armed mine leaves a distant enemy alone",
		is_instance_valid(mine) and _mine_damage == 0)
	fails += _expect("the mine stayed put", is_instance_valid(mine)
		and mine.global_position == drop)
	# Nothing to disarm: an enemy blast right on top of it changes nothing.
	_blast_at(drop, GameConstants.LAYER_ENEMY_BULLETS)
	await get_tree().physics_frame
	await get_tree().physics_frame
	fails += _expect("an enemy blast over the mine leaves it armed", is_instance_valid(mine))

	# Contact: walk the enemy onto it.
	foe.global_position = drop
	var deadline := Time.get_ticks_msec() + 3000
	while _mine_damage == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	fails += _expect("touching the mine set it off on the enemy", _mine_damage > 0)
	# Its own blast is the one thing that takes it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	fails += _expect("the mine went up with its blast", not is_instance_valid(mine))

	if fails == 0:
		print("  ok: oop — the mine drops a tile ahead, waits, and goes off on contact")
	foe.queue_free()
	caster.queue_free()
	await get_tree().physics_frame
	return fails

# The player's Blink is the same effect the shade casts with one dial moved: it lands along
# the caster's AIM instead of on a random bearing. A flipped default reads as a mobility
# spell that throws you somewhere you didn't choose.
func _player_blink_hops_along_aim() -> int:
	var caster := Node2D.new()
	caster.set_script(preload("res://tests/support/stub_caster.gd"))
	caster.position = Vector2(-300, -300)   # open ground, clear of the beats above
	add_child(caster)
	var spell_caster := SpellCaster.new()
	caster.add_child(spell_caster)
	await get_tree().physics_frame

	var from := caster.global_position
	spell_caster.cast(BLINK)   # stub_caster aims RIGHT
	await get_tree().physics_frame
	var moved := caster.global_position - from
	var fails := _expect("blink hopped the spell's distance along the aim (%s)" % moved,
		is_equal_approx(moved.x, BLINK.distance_tiles * GameConstants.PX_PER_TILE)
			and is_zero_approx(moved.y))

	# The effect outlives the hop it resolved: it stays behind as the afterimage, then
	# clears itself when the poof ends. Freeing on the spot would leak nothing but leave
	# the departure unmarked; never freeing would leak one node per cast.
	var poof := get_tree().root.find_child("Blink", false, false) as Node2D
	fails += _expect("the hop left an afterimage where the caster was",
		poof != null and poof.global_position == from and poof.get_node("Poof").is_playing())
	await get_tree().create_timer(0.5).timeout
	fails += _expect("the afterimage cleared itself once it played out",
		get_tree().root.find_child("Blink", false, false) == null)

	if fails == 0:
		print("  ok: blink — the tier lands along the aim, leaving an afterimage behind")
	caster.queue_free()
	await get_tree().physics_frame
	return fails

# A one-shot damage area of the given faction, the shape a bullet's on-expire blast takes.
func _blast_at(at: Vector2, layer: int) -> void:
	var zone := DamageZone.new()
	zone.damage = 999
	zone.collision_layer = layer
	zone.collision_mask = 0
	zone.monitoring = false
	zone.position = at
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	zone.add_child(shape)
	add_child(zone)
	get_tree().create_timer(0.2).timeout.connect(zone.queue_free)

# An inert hostile: on the enemy layer and in the enemies group so probes and targeting
# find it, with a hurtbox so what hits it can be counted, and no AI of its own.
func _foe(at: Vector2) -> CharacterBody2D:
	var foe := CharacterBody2D.new()
	foe.collision_layer = 32
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	foe.add_child(shape)
	var hurtbox: Area2D = preload("res://components/hurtbox.tscn").instantiate()
	hurtbox.collision_mask = 256
	hurtbox.hurt.connect(func(damage: int, _source: Node) -> void: _mine_damage += damage)
	foe.add_child(hurtbox)
	foe.add_to_group("enemies")
	foe.position = at
	add_child(foe)
	return foe

func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = LAYER_TERRAIN
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body

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

# Headless never renders, so the creature's off-screen sleeper would freeze its AI.
func _wake(creature: Creature) -> void:
	for child in creature.get_children():
		if child is VisibleOnScreenEnabler2D:
			child.queue_free()
	creature.process_mode = Node.PROCESS_MODE_INHERIT

func _expect(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  FAIL: %s" % what)
	return 1
