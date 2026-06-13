extends Node

# Declaration of global event signals, each node is then responsible for connecting to the signals it needs
# and emitting them when necessary

# Player signals
signal player_max_health_changed(max_health: int)
signal player_health_changed(health: int)
signal player_max_mana_changed(max_mana: int)
signal player_mana_changed(mana: int)
signal player_skill_changed(skill: int)
signal player_speed_changed(speed: int)

# Inventory signals
signal slot_updated(slot: GlobalInventory.Slot)
signal item_picked_up(slot: GlobalInventory.Slot)
# Emitted only for weapon/hat/robe slots — players and characters connect here
signal equipment_changed(slot: GlobalInventory.Slot)
# Emitted when a player drops an item from the inventory to the ground
signal item_dropped(item: ItemResource)
# Emitted when an enemy dies and a loot roll succeeds, once per dropped item
signal loot_dropped(item: ItemResource, position: Vector2)

# Spell signals
# Cooldowns are keyed by the spell resource, not the slot it was cast from.
signal spell_cooldown_started(spell: SpellResource, duration: float)

# Debug signals
# Emitted by every Hurtbox on a successful hit. victim is the character struck,
# source is the bullet/damage area. The debug overlay tallies these.
signal entity_damaged(victim: Node, amount: int, source: Node)
