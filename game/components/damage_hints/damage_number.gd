extends Node2D

## A floating combat number: accumulates hits on its victim, then drifts up and fades.

const RELEASE_DELAY := 0.15  # idle time before the number stops accumulating
const DRIFT := 16.0          # pixels risen while fading
const FADE_TIME := 0.5

@onready var label: Label = $Label

var victim: Node2D
var offset: Vector2
var is_accumulating := true

var _total := 0
var _idle := 0.0
var _age := 0.0

func setup(p_victim: Node2D, amount: int, color: Color, p_offset: Vector2) -> void:
	victim = p_victim
	offset = p_offset
	_total = amount
	modulate = color  # tints the number; the fade later drops modulate.a
	label.text = str(_total)
	_snap_to_victim()

func add(amount: int) -> void:
	_total += amount
	_idle = 0.0
	label.text = str(_total)

func _process(delta: float) -> void:
	if is_accumulating:
		_idle += delta
		_snap_to_victim()
		if _idle >= RELEASE_DELAY:
			is_accumulating = false
	else:
		_age += delta
		position.y -= DRIFT * delta / FADE_TIME
		modulate.a = 1.0 - _age / FADE_TIME
		if _age >= FADE_TIME:
			queue_free()

func _snap_to_victim() -> void:
	if is_instance_valid(victim):
		global_position = (victim.global_position + offset).round()
