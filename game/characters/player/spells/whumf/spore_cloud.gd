extends Node2D
class_name SporeCloud

## A patch of spores on the floor. It ticks whatever its caster hunts for very little. Like a
## mine it's a dumb object — no health, no hurtbox, nothing can shoot it off the floor — and
## the Mycelium's roster lays these with the same scene the player does.
##
## Only the PLAYER'S spores are ammunition. Light sets those off (see SporeDetonator) and the
## blast spreads through every cloud touching them; an enemy's field is inert terrain that
## nothing can light. Detonation is a thing the player's own kit does with its own spores, so
## a room the dungeon has coated is a room to cross, never a free bomb to cash in.

const GROUP := "spore_clouds"
## The patch is 32px of art, so it covers two tiles either side of itself. Tied to the sheet
## rather than exported: a radius that disagrees with the picture is a lie about where it
## is safe to stand.
const RADIUS := 2.0 * GameConstants.PX_PER_TILE
## Half a body, added only to the `feeds` query — see the note there.
const BODY_REACH := 0.5 * GameConstants.PX_PER_TILE
const TICK_INTERVAL := 0.5
## Seconds of die-back animation, taken out of the end of the lifetime.
const WITHER_TIME := 1.2

# Stamped by whoever lays the cloud, before it enters the tree. The damage defaults are the
# DUNGEON's: every enemy spore on the floor hurts the same, whether a puffcap popped or a
# spitter lobbed it, so the number is authored here and nowhere else. Only the player's Whumf
# overrides it, because only the player's spores scale with stats and only theirs can be lit.
var lifetime: float = 12.0
var tick_damage: int = 5
var blast_damage: int = 0
var target_groups: Array = ["enemies"]
## Whose floor this is. Player clouds are blue, enemy ones purple, both glinting yellow —
## standing in the wrong one costs health, so it has to read without thinking.
var foe: bool = false

var _spent := false
var _tick := 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	add_to_group(GROUP)
	# Whole pixels only: a patch on a half pixel smears off the grid the floor sits on.
	global_position = global_position.round()
	# Every cloud plays the same four frames, so a field laid in one cast would be seven
	# copies of one scatter. Flipping gives four patterns out of the one sheet.
	_sprite.flip_h = randi() % 2 == 0
	_sprite.flip_v = randi() % 2 == 0
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.play(_anim("grow"))
	get_tree().create_timer(maxf(lifetime - WITHER_TIME, 0.1)) \
		.timeout.connect(_end.bind(_anim("fade")))

func _physics_process(delta: float) -> void:
	if _spent:
		return
	_tick += delta
	if _tick < TICK_INTERVAL:
		return
	_tick = 0.0
	for victim in _victims(target_groups):
		_hurt(victim, tick_damage)

## True if `point` is inside the patch and there's still something here to light.
func covers(point: Vector2, slack: float = 0.0) -> bool:
	return not _spent and point.distance_to(global_position) <= RADIUS + slack

## True if any live patch on `foe`'s side of the floor covers `point`.
static func any_covers(point: Vector2, foe_side: bool, slack: float = 0.0) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for cloud in tree.get_nodes_in_group(GROUP):
		if cloud.foe == foe_side and cloud.covers(point, slack):
			return true
	return false

## True while `body` stands in its OWN side's spores — the empowerment query behind
## Behaviour.needs_cloud. Sides never mix, for the same reason detonation doesn't: the player's
## field is ammunition they laid and paid for, and a dungeon that got stronger standing in it
## would turn the player's own answer into the dungeon's. The side test is the one that stamps
## `foe` on a cloud in the first place, so a body is fed by exactly the clouds it could have
## laid itself.
##
## Half a body wide of slack, because "standing in spores" is a claim about the two sprites the
## player can see touching, not about the single pixel a body's origin sits on: the patch is 32px
## of art and a body is another 8px, so one visibly parked in the field is up to 20px off the
## nearest centre. Rooted bodies ate this constantly — nothing lobs dust onto a turret's exact
## pixel, it lands beside it — so a shellcap standing in an obvious field kept firing its plain
## volley. Only this query is generous; ticking and detonation still answer on the patch itself,
## since those are about where the art actually hurts.
static func feeds(body: Node2D) -> bool:
	var layer = body.get("bullet_collision_layer")
	return any_covers(body.global_position,
		layer != null and layer != GameConstants.LAYER_PLAYER_BULLETS, BODY_REACH)

## Set off by light. The blast jumps to every cloud touching this one and hits each
## victim ONCE — the chain widens the area, it doesn't stack hits — and it hunts the
## DETONATOR's enemies rather than each cloud's, so lighting your own field can never be a
## way to blow yourself up.
##
## An enemy's spores refuse outright, here rather than in the detonator, so no future match
## can find a way to light them: the dungeon's floor is a hazard to walk, not ammunition it
## hands you.
func detonate(groups: Array) -> void:
	if _spent or foe:
		return
	var victims := {}
	for cloud in _chain():
		# One yellow row serves both sides: a detonation is the same event whoever laid it.
		cloud._end("flash")
		for victim in cloud._victims(groups):
			victims[victim] = true
	for victim in victims:
		_hurt(victim, blast_damage)

# Flood out through overlapping clouds. ponytail: O(n²) over the clouds on the floor,
# which is fine at a roomful — index them by cell if a boss ever coats the whole arena.
func _chain() -> Array:
	var found: Array = [self]
	var queue: Array = [self]
	while not queue.is_empty():
		var cloud: SporeCloud = queue.pop_back()
		for other in get_tree().get_nodes_in_group(GROUP):
			# Never across sides: a blast that jumped into the dungeon's own field would
			# spend it, which is the same free bomb detonate() just refused.
			if other in found or other._spent or other.foe != foe:
				continue
			if other.global_position.distance_to(cloud.global_position) <= RADIUS * 2:
				found.append(other)
				queue.append(other)
	return found

func _victims(groups: Array) -> Array:
	var out: Array = []
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			if node.global_position.distance_to(global_position) <= RADIUS:
				out.append(node)
	return out

# The victim's own Hurtbox signal — the same one a bullet reaches through — so armour,
# shields and the floating numbers behave exactly as they do for any other hit.
func _hurt(node: Node, amount: int) -> void:
	if amount <= 0:
		return
	var hurtbox = node.get("hurtbox")
	if hurtbox:
		hurtbox.hurt.emit(amount, self)

# Both endings are one beat with a different picture: dying back on its own clock, or the
# yellow pop. Either way the cloud stops ticking and frees itself when the animation ends.
func _end(anim: String) -> void:
	if _spent:
		return
	_spent = true
	_sprite.play(anim)

func _anim(anim_name: String) -> String:
	return ("foe_" + anim_name) if foe else anim_name

func _on_animation_finished() -> void:
	if _sprite.animation.ends_with("grow"):
		_sprite.play(_anim("idle"))
	else:
		queue_free()
