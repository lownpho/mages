extends Node

# Declaration of global event signals, each node is then responsible for connecting to the signals it needs
# and emitting them when necessary

signal player_position_changed(position: Vector2)

signal item_picked_up(item_name: String, item_type: GlobalDefs.ItemType, scene: PackedScene, texture: Texture2D)
signal item_added_to_inventory(node_name: String)
signal drag_state_changed(is_dragging: bool)


# There is a better way for sure...
signal player_max_health_changed(max_health: int)
signal player_health_changed(health: int)
signal player_max_mana_changed(max_mana: int)
signal player_mana_changed(mana: int)
signal player_skill_changed(skill: int)
signal player_speed_changed(speed: int)
