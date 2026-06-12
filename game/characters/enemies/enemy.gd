extends CharacterBody2D
class_name Enemy

@export var max_health: int = 100
@export var skill: int = 0
## Each entry is rolled independently on death, so an enemy can drop several items at once.
@export var drops: Array[LootDrop] = []
var health: int

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM

func _ready() -> void:
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	# Deferred: the freshly instantiated tree is still blocked during _ready, so
	# behaviours can't parent their timers yet. Deferred calls flush FIFO and the
	# behaviours' _ready run before ours, so every timer exists before start().
	fsm.start.call_deferred()

func make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(on_timeout)
	add_child.call_deferred(timer)  # deferred for the same reason as fsm.start()
	return timer

func get_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]

func probe_sees(probe: RayCast2D) -> bool:
	var collider = probe.get_collider()
	return collider != null and collider.is_in_group("player")

func look_for_player(probe: RayCast2D) -> bool:
	var player = get_player()
	if not player:
		return false
	probe.look_at(player.global_position)
	return probe_sees(probe)

func play(anim: String) -> void:
	sprite.play(anim)

func face(dir_x: float) -> void:
	# Deadzone ignores near-vertical headings so the sprite doesn't flip-flicker.
	if absf(dir_x) > 0.01:
		sprite.flip_h = dir_x < 0.0

func die() -> void:
	for drop in drops:
		if drop.roll():
			GlobalEvent.loot_dropped.emit(drop.item, global_position)
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage
	if health <= 0:
		die()
