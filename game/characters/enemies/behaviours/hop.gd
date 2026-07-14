extends Behaviour
class_name Hop

# Impulse hop: leaps in a random cardinal direction for a beat, loosing one ring burst as
# it launches, then hands back. The mid-hop ring means standing next to the beetle is
# dangerous even while it's airborne; pairing it after a Volley makes the beetle hard to pin.

@export var weapon_path: NodePath
@export var weapon_data: WeaponResource
@export var duration: float = 0.4
@export var speed: float = 90.0
@export var done_state: String = "Chase"
@export var hop_anim: String = "attack"

@onready var _weapon: CreatureWeapon = get_node(weapon_path)
var _timer: Timer
var _dir: Vector2 = Vector2.RIGHT

func _ready() -> void:
	super()
	if weapon_data:
		_weapon.setup_for_creature(weapon_data)
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.play(hop_anim)
	var cardinals := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	_dir = cardinals[randi() % cardinals.size()]
	# The ring fires as it launches — a RingPattern ignores aim, so any direction is fine.
	_weapon.try_fire(creature.global_position, creature.global_position + _dir)
	_timer.start(duration)

func exit() -> void:
	_timer.stop()
	creature.velocity = Vector2.ZERO

func physics_update(_delta: float) -> void:
	creature.velocity = _dir * speed
	creature.move_and_slide()
