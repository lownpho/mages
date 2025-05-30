extends Node

# Declaration of global event signals, each node is then responsible for connecting to the signals it needs
# and emitting them when necessary

# Player signals
signal player_position_changed(position: Vector2)

# There is a better way for sure...
signal player_max_health_changed(max_health: int)
signal player_health_changed(health: int)
signal player_max_mana_changed(max_mana: int)
signal player_mana_changed(mana: int)
signal player_skill_changed(skill: int)
signal player_speed_changed(speed: int)

# UI global signals
signal drag_state_changed(is_dragging: bool)

# Inventory signals
# This should be enough for add and remove from bag, equipping (just check the slot)
signal slot_updated(slot: GlobalInventory.Slot)
signal item_picked_up(slot: GlobalInventory.Slot)
