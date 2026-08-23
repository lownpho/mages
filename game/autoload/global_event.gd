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
# Emitted on any inventory slot edit — the player recomputes stats here
signal equipment_changed(slot: GlobalInventory.Slot)
# Emitted when SHIFT cycles which inventory line the cast buttons drive
signal active_line_changed(line: int)
# Emitted when a player drops an item from the inventory to the ground
signal item_dropped(item: ItemResource)
# Emitted when an enemy dies and a loot roll succeeds, once per dropped item
signal loot_dropped(item: ItemResource, position: Vector2)

# Emitted when the player steps into a biome, including the starting biome at spawn.
# Relayed from WorldStreamer.biome_entered by world.gd; dungeon scenes can emit it
# directly on entry. The bestiary reveals a biome's section on first visit.
signal biome_entered(biome_id: StringName)

# Emitted by the player on real death (not debug_never_die), before the run is torn
# down. source is the damage source that landed the killing hit.
signal player_died(source: Node)

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
# A two-way warp door was walked into. world.gd owns the streamer and the player, so it does the
# moving: `body` lands beside the door in `target_slot`'s room, on the far side of it relative to
# `heading` (the cardinal it walked in on), so it comes out the other end still walking away.
signal warp_requested(target_slot: Vector2i, body: Node2D, heading: Vector2i)

# A stair door was walked into: move the player one dungeon floor (delta -1 up, +1 down). The
# dungeon scene owns the floors and answers this; walking off either end of the ladder leaves
# for the overworld.
signal floor_change_requested(delta: int, body: Node2D)

# Leaderboard signals
# Emitted when the Talo session opens or closes (login, logout, restore at boot).
signal leaderboard_session_changed(logged_in: bool)

# Debug signals
# Emitted by every Hurtbox on a successful hit. victim is the character struck,
# source is the bullet/damage area. The debug overlay tallies these.
signal entity_damaged(victim: Node, amount: int, source: Node)
