extends CharacterBody2D
class_name Enemy

@export var data: EnemyResource

## Groups this character hunts. Default is the player plus any summons, so enemies
## split aggro onto the player's minions for free. A summon flips this to the
## "enemies" group (see halp_minion) — the targeting code below is faction-agnostic.
@export var target_groups: Array[String] = ["player", "summon"]
## Physics layer the weapon stamps on bullets it fires. Enemies fire enemy bullets;
## a summon overrides this to player bullets so its shots hit enemy hurtboxes.
@export var bullet_collision_layer: int = GameConstants.LAYER_ENEMY_BULLETS

# Mirrored from `data` at _ready so behaviours can read enemy.skill / enemy.max_health
# directly and damage can mutate health.
var max_health: int
var skill: int
var drops: Array[LootDrop]
var health: int

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM

func _ready() -> void:
	max_health = data.max_health
	skill = data.skill
	drops = data.drops
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

# Nearest node across target_groups — the thing this character should attack.
func get_target() -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for group in target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var dist: float = global_position.distance_squared_to(node.global_position)
			if dist < best:
				best = dist
				nearest = node
	return nearest

func probe_sees(probe: RayCast2D) -> bool:
	var collider = probe.get_collider()
	if collider == null:
		return false
	for group in target_groups:
		if collider.is_in_group(group):
			return true
	return false

func look_for_target(probe: RayCast2D) -> bool:
	var target = get_target()
	if not target:
		return false
	probe.look_at(target.global_position)
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
