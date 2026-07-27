extends Node2D

## Thwomp: an instant radial pulse centred on the caster — the "get off me" button, and the
## gnarlking's ground slam. One sweep over the caster's target groups does both halves of it,
## because both fall off with the same distance: the hit is full at the centre and chip at
## the rim, and the shove is an impulse through Creature.apply_knockback on the same curve.
##
## Faction-agnostic by construction: who it hits is CastContext.target_groups, so the player's
## panic button and a boss's slam are one file. Damage goes through each victim's own Hurtbox
## signal rather than a DamageZone — a zone carries ONE number for everyone inside it, which
## is exactly the thing a falloff pulse can't do.

## The shockwave: MARK_COUNT copies of the Mark sprite flung out to the rim. Radius is per-tier
## data (6 tiles here, 12 for the gnarlking's big slam) so a single ring sprite could only match
## it by being scaled — marks placed ON the rim keep the art native and the reach honest at any
## radius. The sprite itself is a borrowed bullet frame, standing in for proper art.
const FRAME_TIME = 0.07
## Ring radius per frame, as a fraction of the spell's own. The wave blows out and then holds
## two frames at the true rim — that hold is what the player reads the range off.
const RING_GROW = [0.55, 0.8, 1.0, 1.0]
const MARK_COUNT = 8

var data: ThwompResource
var ctx: CastContext

var _radius := 0.0
var _age := 0.0
var _frame := -1
var _marks: Array[Sprite2D] = []

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	ctx = CastContext.new(spell, caster)
	# Whole pixels only — a half-pixel origin smears the whole ring off the grid.
	global_position = caster.global_position.round()

func _ready() -> void:
	var radius := data.radius_tiles * GameConstants.PX_PER_TILE
	_radius = radius
	var full := ctx.damage.compute(ctx.skill, ctx.speed, ctx.defence) if ctx.damage else 0
	for group in ctx.target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var offset: Vector2 = node.global_position - global_position
			var dist := offset.length()
			if dist > radius:
				continue
			# 1 at the centre, 0 at the rim — the curve both halves ride.
			var falloff := 1.0 - dist / radius
			_hit(node, roundi(full * lerpf(data.edge_damage, 1.0, falloff)))
			if node.has_method("apply_knockback"):
				var dir := offset.normalized() if dist > 0.01 else Vector2.RIGHT
				node.apply_knockback(dir * data.knockback_force * falloff)
	for _i in MARK_COUNT:
		var mark: Sprite2D = $Mark.duplicate()
		mark.show()
		add_child(mark)
		_marks.append(mark)
	_advance(0)

func _process(delta: float) -> void:
	_age += delta
	var frame := int(_age / FRAME_TIME)
	if frame >= RING_GROW.size():
		queue_free()
		return
	if frame != _frame:
		_advance(frame)

func _advance(frame: int) -> void:
	_frame = frame
	var r: float = _radius * RING_GROW[frame]
	for i in _marks.size():
		# Rounded: a mark on a half pixel would smear off the grid the rest of the art sits on.
		_marks[i].position = (Vector2.RIGHT.rotated(TAU * i / _marks.size()) * r).round()

# The victim's own Hurtbox signal — the same one a bullet body reaches through — so shields,
# armour and the floating numbers all behave exactly as they do for any other hit.
func _hit(node: Node, amount: int) -> void:
	if amount <= 0:
		return
	var hurtbox = node.get("hurtbox")
	if hurtbox:
		hurtbox.hurt.emit(amount, self)
