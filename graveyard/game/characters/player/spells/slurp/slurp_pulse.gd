extends Area2D

## One Slurp tick: a circular DamageZone centred on the player. On the player-bullet
## layer so enemy hurtboxes take `damage` like any AoE; it also masks the enemy body
## layer, so body_entered tells it which enemies it drained from — each one heals the
## caster for heal_per_hit and spits a red drop of drained life that flies into the
## player. Lives a beat, then frees itself.

const _LIFE := 0.08
const _DropScene = preload("res://characters/player/spells/slurp/slurp_drop.tscn")

var damage: int = 0
var heal_per_hit: int = 0
var caster: CharacterBody2D

func get_damage() -> int:
	return damage

func build_radius(radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	$CollisionShape2D.shape = shape

func _ready() -> void:
	body_entered.connect(_on_body)
	var life := Timer.new()
	life.one_shot = true
	life.autostart = true
	life.wait_time = _LIFE
	life.timeout.connect(queue_free)
	add_child(life)

func _on_body(body: Node2D) -> void:
	if not is_instance_valid(caster):
		return
	if heal_per_hit > 0:
		caster.health = mini(caster.health + heal_per_hit, caster.max_health)
		GlobalEvent.player_health_changed.emit(caster.health)
	var drop = _DropScene.instantiate()
	drop.position = body.global_position
	drop.target = caster
	get_tree().root.add_child.call_deferred(drop)
