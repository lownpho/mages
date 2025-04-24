extends CanvasLayer


func _ready() -> void:
	GlobalEvent.connect("player_max_health_changed", _on_player_max_health_changed)
	GlobalEvent.connect("player_health_changed", _on_player_health_changed)
	GlobalEvent.connect("player_max_mana_changed", _on_player_max_mana_changed)
	GlobalEvent.connect("player_mana_changed", _on_player_mana_changed)
	GlobalEvent.connect("player_skill_changed", _on_player_skill_changed)
	GlobalEvent.connect("player_speed_changed", _on_player_speed_changed)
	GlobalEvent.connect("item_picked_up", _on_item_picked_up)

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

func _on_item_picked_up(node_name, _type, _scene: PackedScene, texture: Texture2D) -> void:
	var slots = %Inventory.get_children()
	for slot in slots:
		if slot.empty:
			slot.set_item(texture)
			GlobalEvent.item_added_to_inventory.emit(node_name)
			return
