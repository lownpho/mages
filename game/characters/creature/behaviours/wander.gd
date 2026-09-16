extends Hold
class_name Wander

# A Hold that drifts: same clock, detection and hand-off, but it picks a random heading on
# entry and walks it until the timer lapses. The drift is leashed to the spot the creature
# spawned on, and walls turn it rather than letting it slide along them: an unleashed drift
# random-walks a room's enemies out of the fight the generator placed and piles them against
# the tree line and down the corridors over the minutes before the player ever arrives.

@export var speed: float = 12.0
## How far, in tiles, the drift may take a creature from where it spawned. 0 unleashes it.
@export var leash_tiles: float = 4.0

var _dir: Vector2 = Vector2.ZERO
## Where it spawned. Taken once, after the spawner has placed it.
var _home: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	_home = creature.global_position

func enter() -> void:
	_dir = _heading()
	super()

func _tick(_delta: float) -> void:
	creature.velocity = _dir * speed
	creature.move_and_slide()
	# Turning on contact costs the rest of the beat's slide along the wall, which is what
	# gathers a room's drifters into a line against it.
	if creature.get_slide_collision_count() > 0:
		_dir = _dir.bounce(creature.get_slide_collision(0).get_normal())
	creature.face(_dir.x)

# A random heading while the creature is inside its leash, and the way home once it isn't —
# so it drifts freely around its post and is walked back whenever a beat starts too far out.
func _heading() -> Vector2:
	if leash_tiles <= 0.0:
		return Vector2.from_angle(randf() * TAU)
	var home := _home - creature.global_position
	if home.length() < leash_tiles * GameConstants.PX_PER_TILE:
		return Vector2.from_angle(randf() * TAU)
	return home.normalized()
