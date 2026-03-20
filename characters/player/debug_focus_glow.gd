extends Node

func _ready() -> void:
	var player = get_parent()
	var focus_state = player.get_node("FSM/Focus")
	focus_state.on_enter.connect(_on_focus_enter)
	focus_state.on_exit.connect(_on_focus_exit)
	focus_state.on_physics_update.connect(_on_focus_physics_update)

func _on_focus_enter() -> void:
	get_parent().get_node("Sprite2D").modulate = Color(0.7, 0.7, 1.5, 1.0)

func _on_focus_exit() -> void:
	get_parent().get_node("Sprite2D").modulate = Color.WHITE

func _on_focus_physics_update(_delta: float) -> void:
	var player = get_parent()
	var t = clampf(player.focus_time / player.focus_ramp_time, 0.0, 1.0)
	var curve_val = player.focus_curve.sample(t) if player.focus_curve else t
	var pulse = (1.0 + sin(player.focus_time * 8.0)) * 0.5
	var glow = Color(0.5, 0.5, 2.0, 1.0).lerp(Color(1.0, 1.0, 3.0, 1.0), pulse)
	player.get_node("Sprite2D").modulate = Color.WHITE.lerp(glow, curve_val)
