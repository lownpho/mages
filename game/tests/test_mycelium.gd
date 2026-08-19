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
##   - the two consumers whose empowerment is a SHAPE rather than a number: the shellcap's
##     volley has to actually open into a fan, and the gapcap's fed lunge has to reach further
##     and hand back a shorter root. Both are dials no lint above reads, so a fed rung that
##     merely hit harder would pass everything else and feel identical.
##
## Then the splitters, whose whole point is what stands up after they fall — a seam that fails
## just as quietly, since a body that spawns nothing on death is only a body that died:
##   - a bloatcap leaves its brood, inside the spread it authored.
##   - a clustercap leaves clusterlings that are alive and lobbing, not props, and that cannot
##     split again.
##   - a brood body dies loudly (a ring of pods, wider off coated floor) and then is GONE.
##   - the rollcap, whose empowerment is the floor and nothing else: it rolls a heading it never
##     re-aims, fires only while it is standing in spores, reflects off
##     walls, and comes apart into two smaller balls that CANNOT come apart again. One
##     generation is the difference between a room and a screensaver, and nothing in the split
##     seam counts generations — it's the child's missing stat sheet that ends it, so the test
##     kills a child and watches for a third wave that must never arrive.
##
## Then the payout, which is the same kind of silent claim — a side tier is its own tier with
## one integer changed, so a drop wired back to the plain file looks correct in the bag and
## simply never doubles:
##   - the weakness itself: an insect-targeted hit lands for double on an insect and flat on
##     everything else, whatever spawned it (a bullet, a blast, a contact zone).
##   - every basic spell the roster pays out is the insect side tier, never the plain one.
## Run: godot --headless --path game res://tests/test_mycelium.tscn

const CLOUD := preload("res://characters/player/spells/whumf/spore_cloud.tscn")
const SPIRALCAP := preload("res://characters/enemies/spiralcap/spiralcap.tscn")
const GOLEM := preload("res://characters/enemies/mould_golem/mould_golem.tscn")
const SPITTER := preload("res://characters/enemies/sporespitter/sporespitter.tscn")
const BLOATCAP := preload("res://characters/enemies/bloatcap/bloatcap.tscn")
const CLUSTERCAP := preload("res://characters/enemies/clustercap/clustercap.tscn")
const MYCELING := preload("res://characters/enemies/bloatcap/myceling.tscn")
const CLUSTERLING := preload("res://characters/enemies/clustercap/clusterling.tscn")
const ROLLCAP := preload("res://characters/enemies/rollcap/rollcap.tscn")
const ROLLCAP_SMALL := preload("res://characters/enemies/rollcap/rollcap_small.tscn")
const SHELLCAP := preload("res://characters/enemies/shellcap/shellcap.tscn")
const GAPCAP := preload("res://characters/enemies/gapcap/gapcap.tscn")
const RINGCAP := preload("res://characters/enemies/ringcap/ringcap.tscn")
const NORMIECAP := preload("res://characters/enemies/normiecap/normiecap.tscn")
const BURROWER := preload("res://characters/enemies/burrower/burrower.tscn")
const DEATHCAP := preload("res://characters/enemies/deathcap/deathcap.tscn")
const MAULCAP := preload("res://characters/enemies/maulcap/maulcap.tscn")
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
	"rollcap": ROLLCAP,
	"rollcap_small": ROLLCAP_SMALL,
	"shellcap": SHELLCAP,
	"gapcap": GAPCAP,
	"ringcap": RINGCAP,
	"normiecap": NORMIECAP,
	"burrower": BURROWER,
	"deathcap": DEATHCAP,
	"maulcap": MAULCAP,
	# The broods are not roster entries — no stat sheet, no kill count — but they cast, so the
	# same two rules have to hold for them or the rules aren't rules.
	"myceling": MYCELING,
	"clusterling": CLUSTERLING,
}
# The only insect the game ships, and so the only thing an insect side tier can be proven on.
const WASP := preload("res://characters/enemies/wasp/wasp.tscn")
# The player's half of the set: two planted turrets that read the floor from the other side.
const POOT := preload("res://characters/player/spells/poot/poot3.tres")
const BLOPS := preload("res://characters/player/spells/blops/blops3.tres")
const STUB_CASTER := preload("res://tests/support/stub_caster.gd")
# Spells the Mycelium pays out as side tiers. A body that drops one of these drops the
# badged copy — the plain tier is the drop it would have gotten anywhere else.
const SIDE_TIERED := ["pew", "blam", "ring", "snipe"]

func _ready() -> void:
	var fails := 0
	fails += await _ladder_swaps("spiralcap", SPIRALCAP, "TwinSweep", "Sweep", false)
	fails += await _ladder_swaps("mould_golem", GOLEM, "WideRing", "Ring", true)
	fails += await _ladder_swaps("sporespitter", SPITTER, "WideBlam", "Blam", true)
	fails += await _ladder_swaps("shellcap", SHELLCAP, "Fan", "Volley", true)
	fails += await _ladder_swaps("gapcap", GAPCAP, "DoubleCone", "Cone", true)
	fails += await _shellcap_fans_out()
	fails += await _gapcap_roots_shorter()
	fails += await _ladder_swaps("ringcap", RINGCAP, "HardRing", "Ring", false)
	fails += await _ladder_swaps("normiecap", NORMIECAP, "HardPew", "Pew", true)
	fails += await _normiecap_closes_and_backs_off()
	# The three rares. The burrower spends its whole loop moving, so its field has to reach
	# past the crossing — see _burrower_crosses_unseen.
	fails += await _ladder_swaps("burrower", BURROWER, "Ring", "Spray", true, 8)
	fails += await _burrower_crosses_unseen()
	fails += await _ladder_swaps("deathcap", DEATHCAP, "Fan", "Volley", true)
	fails += await _ladder_swaps("maulcap", MAULCAP, "DoubleCone", "Cone", true)
	fails += await _fed_at_the_edge()
	fails += _printers_never_empower()
	fails += _ladders_are_ladders()
	fails += await _bloatcap_leaves_a_brood()
	fails += await _clustercap_comes_apart()
	fails += await _swells_under_damage("bloatcap", BLOATCAP, "Waddle", 40)
	fails += await _swells_under_damage("clustercap", CLUSTERCAP, "Walk", 60)
	fails += await _brood_pops("myceling", MYCELING)
	fails += await _brood_pops("clusterling", CLUSTERLING)
	fails += await _rollcap_rolls_on()
	fails += await _rollcap_only_shoots_in_spores()
	fails += await _rollcap_bounces()
	fails += await _rollcap_rides_the_floor()
	fails += await _rollcap_splits_once()
	fails += await _weakness_doubles()
	fails += _pays_the_badged_tier()
	fails += await _turret_reads_the_floor("poot", POOT, "FedShot", "Shot")
	fails += await _turret_reads_the_floor("blops", BLOPS, "HardRing", "Ring")
	print("ALL PASS" if fails == 0 else "FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

# One body, three floors: bare, standing in the PLAYER's Whumf, and standing in the dungeon's
# own field. Only the last one pays. All three halves matter — a needs_cloud check that never
# passes and one that always passes are both a creature with one attack, and one that reads the
# floor without reading whose it is hands the player's own ammunition to the thing it was aimed
# at. Sides are the same rule detonation already follows: a body is fed by exactly the clouds it
# could have laid itself.
func _ladder_swaps(id: String, scene: PackedScene, fed: String, plain: String,
		wants_target: bool, reach: int = 3) -> int:
	var beats := [fed, plain]
	var target: Node2D = _target(Vector2(12, 0)) if wants_target else null
	var fails := 0

	for leg in [["clean floor", -1, plain], ["the player's spores", 0, plain],
			["a field of its own", 1, fed]]:
		if leg[1] >= 0:
			_coat(Vector2.ZERO, reach, leg[1] == 1)
		var body := await _spawn(scene, Vector2.ZERO)
		var got := await _await_beat(body, beats)
		fails += _expect("%s on %s took %s, expected %s" % [id, leg[0], got, leg[2]],
			got == leg[2])
		body.queue_free()
		_clear()
		await get_tree().physics_frame

	if target:
		target.queue_free()
	await get_tree().physics_frame

	if fails == 0:
		print("  ok: %s — %s in its own field, %s on clean floor and in the player's"
			% [id, fed, plain])
	return fails

# "The volley opens into a three-shot fan" is a claim about the SHAPE of the burst, and the
# ladder lint only weighs its damage — a fed rung firing the same single dart for more would
# pass every other check in this file and leave the far end of the room exactly as crossable.
# So count what is actually in the air, on both floors.
func _shellcap_fans_out() -> int:
	var fails := _shellcap_reaches()
	var clean := await _volley_width(false)
	var fed := await _volley_width(true)
	fails += _expect("a shellcap put %d darts up in a field vs %d on clean floor"
		% [fed, clean], clean > 0 and fed >= clean * 2)
	if fails == 0:
		print("  ok: shellcap — %d darts on clean floor open into %d in its own field"
			% [clean, fed])
	return fails

# The normiecap is three library beats in a ring and nothing else, which is exactly why it is
# worth driving once: the loop only closes if every hand-off in it names a state that will have
# it, and a chase wired to a beat that won't run is a creature jogging on the spot. So walk the
# whole circuit — spot, close, fire, and then give up when the target leaves — rather than
# asserting about the wiring, since the wiring is all there is to get wrong here.
func _normiecap_closes_and_backs_off() -> int:
	var at := Vector2(8400, 0)
	# Out past the 2-tile shoot ring but well inside detection, so closing is a real leg.
	var target := _target(at + Vector2(72, 0))
	var body := await _spawn(NORMIECAP, at)
	var fails := 0

	var got := await _await_beat(body, ["Chase"])
	fails += _expect("a normiecap that spotted a target settled in %s, not Chase" % got,
		got == "Chase")
	var from := body.global_position
	# Clean floor here, so the plain rung is the one the circuit has to arrive at — which also
	# pins the hand-off through the Gate rather than straight at a Cast.
	got = await _await_beat(body, ["HardPew", "Pew"])
	fails += _expect("a normiecap closing settled in %s, never reaching its shot" % got,
		got == "Pew")
	fails += _expect("a normiecap fired without closing any distance",
		body.global_position.distance_to(target.global_position) < from.distance_to(target.global_position))
	# The probe stops at the target's SURFACE, so the honest comparison adds its radius —
	# centre-to-centre against a raycast length would fail by exactly the body it hit.
	var reach: float = (body.get_node("ShootProbe") as RayCast2D).target_position.x
	var skin: float = (target.get_child(0) as CollisionShape2D).shape.radius
	var gap := body.global_position.distance_to(target.global_position)
	fails += _expect("a normiecap opened up %.0fpx out, past its own %.0fpx shooting range"
		% [gap - skin, reach], gap - skin <= reach + 1.0)

	# Walk the target off and the whole thing has to unwind back to Idle — the half that fails
	# silently, since a creature stuck in Chase forever looks exactly like one that is hunting.
	target.global_position = at + Vector2(4000, 0)
	got = await _await_beat(body, ["Idle"])
	fails += _expect("a normiecap left alone settled in %s instead of idling back" % got,
		got == "Idle")

	body.queue_free()
	target.queue_free()
	_clear_bullets()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: normiecap — closes, fires inside %.0fpx, and idles back when you leave" % reach)
	return fails

# Standing in spores has to mean what it LOOKS like, or the whole mechanic is a lie the player
# can see through: they read two sprites touching, the code read one pixel against one centre,
# and the two disagreed for the whole 8..12px band where a body is visibly in the field. Every
# check above coats a dense grid centred on the body, which is the one arrangement that can
# never expose it — so this parks a single patch off to the side, exactly the way a lob leaves
# one beside a turret it was never aimed at, and asks the body what floor it thinks it is on.
# Rooted bodies lived in that band: nothing drops dust on a turret's own pixel.
func _fed_at_the_edge() -> int:
	var at := Vector2(7600, 0)
	var body := await _spawn(SHELLCAP, at)
	var fails := 0
	# Along the axis the sprites stop overlapping at 12px; the diagonal is the corner case,
	# where the patch's art runs out sooner than its own bounding box suggests.
	for leg in [[Vector2(10, 0), true], [Vector2(7, 7), true], [Vector2(24, 0), false]]:
		var offset: Vector2 = leg[0]
		var cloud: SporeCloud = CLOUD.instantiate()
		cloud.position = at + offset
		cloud.foe = true
		cloud.target_groups = ["player"]
		cloud.lifetime = 60.0
		add_child(cloud)
		await get_tree().physics_frame
		var want: bool = leg[1]
		fails += _expect("a body %.0fpx off a patch centre reads as %s floor"
			% [offset.length(), "clean" if want else "coated"],
			SporeCloud.feeds(body) == want)
		_clear()
		await get_tree().physics_frame
	body.queue_free()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: spores — a body overlapping a patch is fed; one a field away is not")
	return fails

# "You cannot out-range it" is two numbers agreeing that live in different files: the probe the
# dispatcher commits on, and how far the dart it commits to actually flies. Retune either alone
# and the sniper still fires, still animates, still looks correct — it just drops its volley in
# the dirt short of a player it can plainly see, or refuses to open up on one well inside its
# lethal range. Both rungs, since the fan is a separate .tres that can drift on its own.
func _shellcap_reaches() -> int:
	var body: Creature = SHELLCAP.instantiate()
	var lane: float = (body.get_node("RoomProbe") as RayCast2D).target_position.x
	var fails := 0
	for beat_name in ["Fan", "Volley"]:
		var beat: Cast = body.get_node("FSM").get_node(beat_name)
		var reach: float = beat.spell.bullet.range_tiles * GameConstants.PX_PER_TILE
		fails += _expect("shellcap/%s commits at %.0fpx but its dart dies at %.0fpx"
			% [beat_name, lane, reach], reach >= lane)
	body.free()
	if fails == 0:
		print("  ok: shellcap — both rungs carry the %.0fpx lane it commits on" % lane)
	return fails

# Most darts alive at once, which is the fan: the volley trickles one per shot however long
# you watch, the fan puts three up per shot. The target stands down the lane at three quarters
# of the shellcap's OWN probe rather than at a distance written here — a lane length is the
# first thing anyone retunes on a sniper, and a test holding its own opinion about it stops
# measuring the fan and starts measuring whether the turret can see that far.
func _volley_width(coated: bool) -> int:
	var at := Vector2(6000, 0)
	_clear_bullets()
	if coated:
		_coat(at)
	var body := await _spawn(SHELLCAP, at)
	var lane: float = (body.get_node("RoomProbe") as RayCast2D).target_position.x
	var target := _target(at + Vector2(lane * 0.75, 0))
	var most := 0
	for _i in 180:
		await get_tree().physics_frame
		most = maxi(most, _bullets())
	body.queue_free()
	target.queue_free()
	_clear()
	_clear_bullets()
	await get_tree().physics_frame
	return most

# The other half of gapcap's empowerment is not a spell at all — a longer lunge into a shorter
# root, so the free window the whole enemy is built around closes. Both live in behaviour dials
# no ladder lint reads: a fed rung wired to the same reach and the same recovery would swap
# correctly, out-damage its fallback, and change nothing the player can feel. Checked twice —
# the authored dials say the fed pair is bigger and briefer, and a real body driven through the
# empowered cone actually lands in the shorter one.
func _gapcap_roots_shorter() -> int:
	var body: Creature = GAPCAP.instantiate()
	var fsm: Node = body.get_node("FSM")
	var fed: Approach = fsm.get_node("FedLunge")
	var plain: Approach = fsm.get_node("Lunge")
	var brief: Hold = fsm.get_node("ShortRoot")
	var full: Hold = fsm.get_node("Root")
	# Read every dial out before the tree goes; the rest of this runs without a gapcap in hand.
	var fed_reach := fed.speed * fed.duration
	var plain_reach := plain.speed * plain.duration
	var brief_root := brief.max_time
	var full_root := full.min_time
	body.free()
	var fails := _expect("gapcap's fed lunge crosses %.0fpx, no further than its plain %.0fpx"
		% [fed_reach, plain_reach], fed_reach > plain_reach)
	# Against min_time, not max: the two windows must not OVERLAP, or a fed lunge can roll a
	# longer recovery than a plain one and hand the player back the window it just took.
	# Touching at the boundary is fine — that is still every fed root at most as long as every
	# plain one, which is the claim.
	fails += _expect("gapcap's fed root (up to %.1fs) can outlast its plain one (from %.1fs)"
		% [brief_root, full_root], brief_root <= full_root)
	await get_tree().physics_frame

	for leg in [["clean floor", -1, "Root"], ["a field of its own", 1, "ShortRoot"]]:
		var at := Vector2(6800, 0)
		if leg[1] >= 0:
			_coat(at, 4)
		var target := _target(at + Vector2(16, 0))
		var live := await _spawn(GAPCAP, at)
		var got := await _await_beat(live, ["ShortRoot", "Root"])
		fails += _expect("a gapcap recovering on %s settled in %s, expected %s"
			% [leg[0], got, leg[2]], got == leg[2])
		live.queue_free()
		target.queue_free()
		_clear()
		_clear_bullets()
		await get_tree().physics_frame

	if fails == 0:
		print("  ok: gapcap — a %.0fpx lunge into a %.1fs root in a field, %.0fpx into %.1fs without"
			% [fed_reach, brief_root, plain_reach, full_root])
	return fails

# The burrower IS its crossing, and every part of one fails silently: a wander that never moves
# is a creature standing still, an armour dial left at 1.0 is a "submerged" body you can shoot,
# and a loop that never comes back up is an enemy that left the fight. So drive the whole
# circuit — under, across, up, spray, print — rather than asserting about the wiring.
#
# The order at the end is the load-bearing bit. It shoots BEFORE it prints, which is the only
# reason its spray is ever the plain rung: print first and it would be standing in its own fresh
# field every single time, and the empowered ring would stop being a punish for surfacing into
# the field it left last time and just become what it does.
func _burrower_crosses_unseen() -> int:
	var at := Vector2(9200, 0)
	var target := _target(at + Vector2(12, 0))
	var body := await _spawn(BURROWER, at)
	var fails := 0

	var got := await _await_beat(body, ["Burrow"])
	fails += _expect("a burrower that spotted a target settled in %s, never diving" % got,
		got == "Burrow")
	var from := body.global_position
	fails += _expect("a burrowed burrower takes damage at scale %.1f, expected 0"
		% body.incoming_damage_scale, body.incoming_damage_scale == 0.0)

	got = await _await_beat(body, ["Spray", "Ring"])
	fails += _expect("a surfaced burrower settled in %s instead of its spray" % got,
		got == "Spray")
	var crossed := body.global_position.distance_to(from)
	# Measured against its own shortest crossing rather than a number written here, so retuning
	# the dive retunes the test with it.
	var dig: Wander = body.fsm.states["Burrow"]
	fails += _expect("a burrower crossed %.0fpx underground, nowhere near its own %.0fpx"
		% [crossed, dig.speed * dig.min_time], crossed >= dig.speed * dig.min_time * 0.5)
	fails += _expect("a surfaced burrower is still armoured at %.1f"
		% body.incoming_damage_scale, body.incoming_damage_scale == 1.0)

	got = await _await_beat(body, ["Spores"])
	fails += _expect("a burrower that fired settled in %s, never laying its cloud" % got,
		got == "Spores")

	body.queue_free()
	target.queue_free()
	_clear()
	_clear_bullets()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: burrower — dives untouchable, crosses %.0fpx, sprays, then prints" % crossed)
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

# The rollcap is the roster's one hazard: no caster, no probe, no target — a heading and a
# health bar. "Never steers toward you" is the whole design, and it fails silently the moment
# anyone gives it a chase beat, so the claim is checked with the target standing right there:
# the heading it left with is the heading it keeps.
func _rollcap_rolls_on() -> int:
	var target := _target(Vector2(3200, 64))
	var body := await _spawn(ROLLCAP, Vector2(3200, 0))
	var beat: Node = body.fsm.states["Roll"]
	beat.heading = Vector2.RIGHT
	var fails := 0
	var from := body.global_position
	for _i in 30:
		await get_tree().physics_frame
	var moved := body.global_position - from
	fails += _expect("a rollcap sat still", moved.length() > 1.0)
	fails += _expect("a rollcap steered off its heading (drifted %s toward the target)" % moved,
		moved.normalized().dot(Vector2.RIGHT) > 0.999)
	body.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: rollcap — rolls its heading straight past a target it only ever aims at")
	return fails

# Its cast is the empowerment, so the floor is the whole trigger: clean floor has to be
# silent. The gate lives inside the roll rather than behind a Gate rung, which is exactly the
# arrangement that would fail quietly — a ball that shoots everywhere looks like a ball that
# shoots, and only the clean-floor half of this catches it.
func _rollcap_only_shoots_in_spores() -> int:
	var fails := 0
	for leg in [["on clean floor", -1], ["in the player's spores", 0], ["in a field of its own", 1]]:
		var at := Vector2(5200, 0)
		_clear_bullets()
		if leg[1] >= 0:
			# Wide enough that the ball is still standing in it when its cooldown lapses —
			# it is rolling away from where it was coated the whole time.
			_coat(at, 8, leg[1] == 1)
		var target := _target(at + Vector2(40, 0))
		var body := await _spawn(ROLLCAP, at)
		body.fsm.states["Roll"].heading = Vector2.UP
		var shots := 0
		for _i in 120:
			await get_tree().physics_frame
			shots = maxi(shots, _bullets())
		var wants: bool = leg[1] == 1
		fails += _expect("a rollcap %s fired %d shots" % [leg[0], shots],
			shots > 0 if wants else shots == 0)
		body.queue_free()
		target.queue_free()
		_clear()
		_clear_bullets()
		await get_tree().physics_frame
	if fails == 0:
		print("  ok: rollcap — silent on clean floor and in the player's, shoots in its own")
	return fails

# The only thing that ever changes its mind for it. A ball that slid along the wall instead of
# reflecting would still be moving, still look alive, and quietly stop being a hazard that
# crosses the room.
func _rollcap_bounces() -> int:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8, 96)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(4064, 0)
	add_child(wall)
	var body := await _spawn(ROLLCAP, Vector2(4000, 0))
	var beat: Node = body.fsm.states["Roll"]
	beat.heading = Vector2.RIGHT
	var squashed := false
	for _i in 240:
		await get_tree().physics_frame
		squashed = squashed or body.sprite.animation == &"bounce"
		if beat.heading.x < 0.0:
			break
	var fails := _expect("a rollcap ran into a wall and kept its heading (%s)" % beat.heading,
		beat.heading.x < 0.0)
	fails += _expect("a rollcap bounced without the squash frame", squashed)
	body.queue_free()
	wall.queue_free()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: rollcap — reflects off a wall and squashes on the way")
	return fails

# Its whole empowerment, and the one shape it can take on a body with no spell: coated floor
# just moves it faster. Measured rather than asserted about, since a speed dial that reads the
# floor and a speed dial that doesn't look identical standing still.
func _rollcap_rides_the_floor() -> int:
	var clean := await _rolled(Vector2(4400, 0), -1)
	var ours := await _rolled(Vector2(4400, 0), 0)
	var theirs := await _rolled(Vector2(4400, 0), 1)
	var fails := _expect("a rollcap covered %.1fpx in its own spores vs %.1fpx on clean floor"
		% [theirs, clean], theirs > clean * 1.1)
	fails += _expect("a rollcap sped up in the PLAYER's spores (%.1fpx vs %.1fpx clean)"
		% [ours, clean], is_equal_approx(ours, clean))
	if fails == 0:
		print("  ok: rollcap — rolls %.0f%% further through its own spores, and not the player's"
			% ((theirs / clean - 1.0) * 100.0))
	return fails

func _rolled(at: Vector2, side: int) -> float:
	if side >= 0:
		_coat(at, 3, side == 1)
	var body := await _spawn(ROLLCAP, at)
	body.fsm.states["Roll"].heading = Vector2.RIGHT
	var from := body.global_position
	for _i in 30:
		await get_tree().physics_frame
	var travelled := body.global_position.distance_to(from)
	body.queue_free()
	_clear()
	await get_tree().physics_frame
	return travelled

# Two stages, and the second one is the last. Nothing counts generations — the child simply
# carries no stat sheet, so it has no death_spawns to fire — which means the rule holds only as
# long as nobody hands the small one a CreatureResource "so it can drop something too". Killing
# a child and watching for a third wave is what would catch that.
func _rollcap_splits_once() -> int:
	var got := await _brood_of("rollcap", ROLLCAP, Vector2(4800, 0))
	var brood: Array = got.brood
	var fails: int = got.fails
	for spawn in brood:
		_wake(spawn)
		fails += _expect("a small rollcap came up dead", spawn.health > 0)
		fails += _expect("a small rollcap carries a stat sheet, so it can split again",
			spawn.data == null)
		fails += _expect("a small rollcap settled in %s instead of rolling" % _state(spawn),
			_state(spawn) == "Roll")
	if not brood.is_empty():
		brood.pop_back().die()
		# Wants one more than could possibly be alive, so it never short-circuits: the loop
		# runs its full window and reports whatever is standing at the end of it.
		var left := await _await_spawns(ROLLCAP_SMALL, brood.size() + 2, 1500)
		fails += _expect("killing a small rollcap left %d bodies, expected the %d untouched"
			% [left.size(), brood.size()], left.size() == brood.size())
	for spawn in brood:
		spawn.queue_free()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: rollcap — splits into %d smaller balls, and they are the end of it"
			% got.count)
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

# What a whole beat is worth, not what one pellet is: a burst's output is its damage times how
# many shots it owes times how wide each shot is, and an empowered rung is free to buy its
# strength from any of the three. The gapcap's double cone is the case that proved it — same
# per-pellet number as the plain one, twice the shots — and reading only `base_damage` called
# that a ladder going nowhere.
func _power(spell: SpellResource) -> int:
	var amount: ScalingProfile = spell.get("damage")
	if amount == null:
		return 0
	var per_shot := amount.compute(0)
	if not (spell is BulletSpellResource):
		return per_shot
	# Ask the pattern rather than reading num_pellets/num_bullets off each shape by name.
	var width := 1
	if spell.fire_pattern:
		width = spell.fire_pattern.get_directions(Vector2.RIGHT).size()
	return per_shot * maxi(spell.max_shots, 1) * width

# A coated room, laid the way a lob leaves it: patches on a grid one cloud wide, so wherever
# the body parks inside it, it is standing in spores. `foe` picks whose floor it is — the
# dungeon's own by default, the player's Whumf when false.
func _coat(center: Vector2, reach: int = 3, foe: bool = true) -> void:
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			var cloud: SporeCloud = CLOUD.instantiate()
			cloud.position = center + Vector2(x, y) * SporeCloud.RADIUS
			cloud.foe = foe
			cloud.target_groups = ["player"] if foe else ["enemies"]
			cloud.lifetime = 60.0
			add_child(cloud)

# The first of `beats` the body enters. Returns whatever it settled on when nothing does, so
# the failure names the state it got stuck in.
# Double or nothing, resolved on the victim: the same source hits an insect twice as hard as
# it hits anything else. Both halves have to hold — a weakness that never matches is a drop that
# quietly does nothing, and one that always matches is a global damage buff nobody authored.
func _weakness_doubles() -> int:
	var fails := 0
	# Any damage source will do — the victim reads `weakness` off whatever hit it, so a blast
	# and a bullet and a contact zone all resolve identically.
	var source := DamageZone.new()
	source.weakness = GameConstants.KIND_INSECT
	# Well under the wasp's own health, or the doubling would be hidden by the floor at 0.
	for probe in [["wasp", WASP, 10], ["sporefly", ROSTER["sporefly"], 5]]:
		var body := await _spawn(probe[1], Vector2.ZERO)
		var before: int = body.health
		body.hurtbox.hurt.emit(5, source)
		await get_tree().physics_frame
		fails += _expect("an insect-seeking 5 took %d off a %s, expected %d"
			% [before - body.health, probe[0], probe[2]], before - body.health == probe[2])
		body.queue_free()
		await get_tree().physics_frame
	source.free()
	if fails == 0:
		print("  ok: weakness — insect doubles on the wasp, flat on everything else")
	return fails

# The set's two turrets, from the player's side of the same seam: planted where you aimed,
# rooted there, and fed by YOUR spores and nothing the dungeon laid. Both halves fail silently —
# a fed rung that never fires is a turret that looks like it works, and one the dungeon's own
# floor empowers hands the room's ammunition to the side it was meant to threaten.
func _turret_reads_the_floor(id: String, spell: SummonResource, fed: String, plain: String) -> int:
	var fails := 0
	var at := Vector2(spell.spawn_distance, 0)  # a caster at the origin aiming right
	var foe := _foe(at + Vector2(24, 0))
	for leg in [["clean floor", -1, plain], ["the dungeon's spores", 1, plain],
			["your own field", 0, fed]]:
		if leg[1] >= 0:
			_coat(at, 3, leg[1] == 1)
		var minion := await _plant(spell)
		fails += _expect("a planted %s stood %.0fpx off its aim point"
			% [id, minion.global_position.distance_to(at)],
			minion.global_position.distance_to(at) <= 1.0)
		var got := await _await_beat(minion, [fed, plain])
		fails += _expect("%s on %s took %s, expected %s" % [id, leg[0], got, leg[2]],
			got == leg[2])
		# The beat AFTER the first is where a fed turret used to slip: two spells are two
		# cooldown clocks, so once the empowered one is cooling the plain rung is the only
		# thing left willing to run, and the ladder quietly hands the weak version back.
		if leg[2] == fed:
			while _state(minion) == fed:
				await get_tree().physics_frame
			var again := await _await_beat(minion, [fed, plain])
			fails += _expect("a fed %s followed %s with %s" % [id, fed, again], again == fed)
		minion.queue_free()
		_clear()
		await get_tree().physics_frame
	foe.queue_free()
	await get_tree().physics_frame
	if fails == 0:
		print("  ok: %s — planted on your aim, %s in your own field, %s otherwise"
			% [id, fed, plain])
	return fails

# Cast the summon the way the game does — the effect scene, set up from a caster — rather than
# placing the minion by hand, so the placement this checks is the one the player gets.
func _plant(spell: SummonResource) -> Creature:
	var caster := Node2D.new()
	caster.set_script(STUB_CASTER)
	add_child(caster)
	var effect: Node2D = spell.effect_scene.instantiate()
	effect.setup(spell, caster)
	add_child(effect)
	var minion: Creature = null
	while minion == null:
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group("summon"):
			minion = node
	_wake(minion)
	caster.queue_free()
	return minion

# Something for a turret to shoot at: on the enemy layer and in the enemy group, which is what
# a summon hunts and what its reach probe can see.
func _foe(at: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.collision_layer = 32
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	body.add_child(shape)
	body.add_to_group("enemies")
	body.position = at
	add_child(body)
	return body

# The roster pays what it casts, badged (see the design's drops). Nothing at runtime can tell
# a side tier from its plain twin except this one field, so a drop left pointing at the plain
# .tres is a bug with no symptom until someone counts damage in the hive.
func _pays_the_badged_tier() -> int:
	var fails := 0
	for id in ROSTER:
		var body: Creature = ROSTER[id].instantiate()
		if body.data:
			for drop in body.data.drops:
				var stem: String = drop.item.resource_path.get_file().get_basename()
				var spell := stem.trim_suffix("_insect").rstrip("0123456789")
				# Anything else is a set piece (Whumf, the detonator), which drops unchanged.
				if spell in SIDE_TIERED:
					fails += _expect("%s pays a plain %s" % [id, stem],
						drop.item.weakness == GameConstants.KIND_INSECT)
		body.free()
	if fails == 0:
		print("  ok: drops — every basic tier the roster pays is the insect side tier")
	return fails

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
