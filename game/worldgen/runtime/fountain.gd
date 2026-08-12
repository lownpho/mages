@tool
class_name Fountain
extends Area2D

## A healing pool. Walking in restores the player to full and puts the fountain
## dormant (still water, no animation) until `cooldown` lapses.

## Art variants packed one sheet per biome, frame 0 dormant + 4 flowing.
enum Style { GLADE, DEEPWOOD }

@export var style := Style.GLADE: # Runs on assignment so the editor preview tracks the choice.
	set(value):
		style = value
		_apply_style()

@export var cooldown := 60.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _cooldown: Timer = $Cooldown


func _ready() -> void:
	_apply_style()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	_cooldown.timeout.connect(_apply_style)


func _apply_style() -> void:
	if not is_node_ready():
		return
	var biome := "glade" if style == Style.GLADE else "deepwood"
	_sprite.play("%s_%s" % [biome, "dormant" if _cooldown.time_left > 0.0 else "flow"])


func _on_body_entered(body: Node2D) -> void:
	if _cooldown.time_left > 0.0 or body.health >= body.max_health:
		return
	body.health = body.max_health
	GlobalEvent.player_health_changed.emit(body.health)
	_cooldown.start(cooldown)
	_apply_style()

	$HealAura.show()
	$HealAura.play()
	var tween := create_tween()
	tween.tween_property($HealAura, "modulate:a", 0.0, 0.45).set_delay(0.15)
	tween.tween_callback($HealAura.hide)
	tween.tween_property($HealAura, "modulate:a", 1.0, 0.0)
