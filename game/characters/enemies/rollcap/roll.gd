extends Behaviour

## The one thing in the Mycelium that never looks at you: a heading picked once, held forever,
## and reflected off whatever it runs into. It is a hazard with a health bar, so there is no
## target, no probe and no hand-off — the beat the body enters is the beat it dies in.
##
## Coated floor is its whole empowerment, and it takes both shapes at once: it rolls faster,
## and it starts shooting. The gate lives inside this beat rather than behind a `needs_cloud`
## rung of a Gate, because the roll never ends — there is no hand-off for a ladder to make, and
## a Cast beat would plant the ball to fire, which is the one thing it must never do.

@export var speed: float = 40.0
## Speed multiplier while standing in spores — the whole of this creature's empowerment.
@export var cloud_speed_scale: float = 1.5
@export var anim: String = "roll"
## Squash frames, played non-looping off a wall: the roll resumes when they run out, so the
## bounce reads as a bounce rather than a direction that silently changed.
@export var bounce_anim: String = "bounce"

@export_group("Spores")
## Fired at the target while — and only while — the ball is standing in spores. Cadence is the
## spell's own `cooldown`, so cast() is asked every frame and simply refuses until it lapses;
## this beat keeps no clock of its own. Leave it null for a ball that only ever rolls.
@export var spell: SpellResource
@export var caster_path: NodePath

@onready var _caster: SpellCaster = get_node_or_null(caster_path)

## Rolled once on entry and only ever reflected after — public so a test can aim one at a
## wall instead of waiting for a random heading to find it.
var heading: Vector2 = Vector2.ZERO

func enter() -> void:
	if heading == Vector2.ZERO:
		heading = Vector2.from_angle(randf() * TAU)
	creature.play(anim)

func physics_update(_delta: float) -> void:
	var fed := SporeCloud.feeds(creature)
	var scale := cloud_speed_scale if fed else 1.0
	creature.velocity = heading * speed * scale
	creature.move_and_slide()
	var bounced := false
	for i in creature.get_slide_collision_count():
		var normal := creature.get_slide_collision(i).get_normal()
		# Only walls it's still heading into: in a corner both normals answer, and reflecting
		# off one it's already leaving would turn it straight back into the other.
		if heading.dot(normal) < 0.0:
			heading = heading.bounce(normal)
			bounced = true
	creature.face(heading.x)
	if bounced:
		creature.play(bounce_anim)
	elif not creature.sprite.is_playing():
		creature.play(anim)
	if fed:
		_shoot()

# Aim is the only thing here that ever reads the player, and it steers nothing: the shot
# tracks, the ball does not.
func _shoot() -> void:
	if spell == null or _caster == null:
		return
	var target := creature.get_target()
	if target:
		_caster.cast(spell, aim_at(target))

