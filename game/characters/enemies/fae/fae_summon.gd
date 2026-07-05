extends Behaviour
class_name FaeSummon

# Calls in a knot of allies (plain hostile Creature scenes, no faction flip needed —
# they're already enemies) spread in a ring around the boss, then hangs back and waits
# for them to die or for a timeout to lapse, so a player who just kites the summons
# forever still gets the fight back.

@export var summon_scenes: Array[PackedScene] = []
@export var summon_count: int = 3
@export var spawn_radius: float = 48.0
@export var timeout: float = 20.0
@export var done_state: String = "Pattern"
@export var summon_anim: String = "summon"

var _spawned: Array[Node] = []
var _timer: Timer

func _ready() -> void:
	super()
	_timer = creature.make_timer(func(): creature.fsm.transition_to(done_state))

func enter() -> void:
	creature.velocity = Vector2.ZERO
	creature.play(summon_anim)
	_spawned.clear()
	if not summon_scenes.is_empty():
		for i in summon_count:
			var scene: PackedScene = summon_scenes[randi() % summon_scenes.size()]
			var minion: Node2D = scene.instantiate()
			var angle := TAU * i / float(summon_count)
			minion.global_position = creature.global_position + Vector2(spawn_radius, 0).rotated(angle)
			get_tree().root.add_child.call_deferred(minion)
			_spawned.append(minion)
	_timer.start(timeout)

func exit() -> void:
	_timer.stop()

func physics_update(_delta: float) -> void:
	_spawned = _spawned.filter(func(n): return is_instance_valid(n))
	if _spawned.is_empty() and not summon_scenes.is_empty():
		creature.fsm.transition_to(done_state)
