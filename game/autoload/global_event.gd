extends Node

# Declaration of global event signals, each node is then responsible for connecting to the signals it needs
# and emitting them when necessary

# Player signals
signal player_max_health_changed(max_health: int)
signal player_health_changed(health: int)
signal player_skill_changed(skill: int)
signal player_speed_changed(speed: int)
signal player_defence_changed(defence: int)

# Inventory signals
signal slot_updated(slot: GlobalInventory.Slot)
signal item_picked_up(slot: GlobalInventory.Slot)
# Emitted only for spell (loadout) slots — the player recomputes stats here
signal equipment_changed(slot: GlobalInventory.Slot)
# Emitted when SHIFT cycles which spell page the cast buttons drive
signal spell_page_changed(page: int)
# Emitted when a player drops an item from the inventory to the ground
signal item_dropped(item: ItemResource)
# Emitted when an enemy dies and a loot roll succeeds, once per dropped item
signal loot_dropped(item: ItemResource, position: Vector2)

# Emitted when the player steps into a biome, including the starting biome at spawn.
# Relayed from WorldStreamer.biome_entered by world.gd; dungeon scenes can emit it
# directly on entry. The bestiary reveals a biome's section on first visit.
signal biome_entered(biome_id: StringName)

# Bestiary signals
# Emitted by Creature.die() for any creature with an authored stat sheet (summons
# carry no `data`, so they never register).
signal creature_died(data: CreatureResource, position: Vector2)
# First kill of an enemy type — its bestiary entry just unlocked.
signal bestiary_entry_unlocked(enemy_id: StringName)
# Every counted kill, the unlocking one included.
signal bestiary_updated(enemy_id: StringName, kills: int)

# Spell signals
# Cooldowns are keyed by the spell resource, not the slot it was cast from.
signal spell_cooldown_started(spell: SpellResource, duration: float)

# World signals
# Emitted by world.gd once the overworld is built and the player is placed; carries the
# streamer so listeners (minimap) can read the deterministic room caches.
signal world_ready(streamer: WorldStreamer)

# Leaderboard signals
# Emitted when the Talo session opens or closes (login, logout, restore at boot).
signal leaderboard_session_changed(logged_in: bool)

# Debug signals
# Emitted by every Hurtbox on a successful hit. victim is the character struck,
# source is the bullet/damage area. The debug overlay tallies these.
signal entity_damaged(victim: Node, amount: int, source: Node)
