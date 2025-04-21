extends CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GlobalEvent.connect("player_max_health_changed", _on_player_max_health_changed)
	GlobalEvent.connect("player_health_changed", _on_player_health_changed)
	GlobalEvent.connect("player_max_mana_changed", _on_player_max_mana_changed)
	GlobalEvent.connect("player_mana_changed", _on_player_mana_changed)
	GlobalEvent.connect("player_skill_changed", _on_player_skill_changed)
	GlobalEvent.connect("player_speed_changed", _on_player_speed_changed)

func _on_player_max_health_changed(max_health: int) -> void:
	%HealthBar.max_value = max_health

func _on_player_health_changed(health: int) -> void:
	%HealthBar.value = health

func _on_player_max_mana_changed(max_mana: int) -> void:
	%ManaBar.max_value = max_mana

func _on_player_mana_changed(mana: int) -> void:
	%ManaBar.value = mana

func _on_player_skill_changed(skill: int) -> void:
	%SkillValue.text = str(skill)

func _on_player_speed_changed(speed: int) -> void:
	%SpeedValue.text = str(speed)
