extends CharacterBody2D
class_name Creature

## A faction-agnostic AI combatant (FSM + hurtbox + weapon + targeting), shared by the
## hostile enemy roster and the player's summoned minions. Hostiles author a `data`
## resource and drops; summons leave `data` null and have their stats injected by the
## summon spawner before they enter the tree (see summon_spawner).
@export var data: CreatureResource

## Groups this creature hunts. Default is the player plus any summons, so enemies
## split aggro onto the player's minions for free. A summon flips this to the
## "enemies" group — the targeting code below is faction-agnostic.
@export var target_groups: Array[String] = ["player", "summon"]
## Physics layer the weapon stamps on bullets it fires. Enemies fire enemy bullets;
## a summon overrides this to player bullets so its shots hit enemy hurtboxes.
@export var bullet_collision_layer: int = GameConstants.LAYER_ENEMY_BULLETS

# Mirrored from `data` at _ready (when present) so behaviours can read
# creature.max_health directly and damage can mutate health. Summons inject
# max_health instead of carrying a `data` resource.
var max_health: int
var drops: Array[LootDrop] = []
var health: int

# Multiplier applied to incoming damage in _on_hurt. A behaviour that armours the
# creature for a beat (e.g. rosebud's Guard reload pose) drops this below 1.0 in
# enter() and restores it to 1.0 in exit(); left at 1.0 it's a no-op for everyone else.
var incoming_damage_scale: float = 1.0

# Off-screen sleep margin: the area (centred on the creature) that must touch the screen
# for it to stay awake. 8 tiles each side so a creature wakes well before it scrolls into
# view rather than popping into motion at the edge.
const SLEEP_MARGIN := 8 * GameConstants.PX_PER_TILE
const SLEEP_RECT := Rect2(-SLEEP_MARGIN, -SLEEP_MARGIN, 2 * SLEEP_MARGIN, 2 * SLEEP_MARGIN)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM

func _ready() -> void:
	if data:
		max_health = data.max_health
		drops = data.drops
	health = max_health
	hurtbox.hurt.connect(_on_hurt)
	# Sleep while off-screen: disable the whole creature (AI, physics, timers, hurtbox)
	# when it leaves the screen and wake it when it returns, so a large world only ticks
	# the creatures the player can see. The notifier's visibility check runs in the server,
	# not in _process, so a process-disabled creature still wakes itself back up.
	var enabler := VisibleOnScreenEnabler2D.new()
	enabler.rect = SLEEP_RECT
	add_child(enabler)
	# RayCast2D defaults hit_from_inside to false, so a probe whose origin sits inside the
	# target's own collider (the player standing on/overlapping this creature) reports no
	# hit at all — the creature goes blind at melee range. Force every LOS probe on so
	# adjacency never breaks targeting.
	for child in get_children():
		if child is RayCast2D:
			child.hit_from_inside = true
	# Deferred: the freshly instantiated tree is still blocked during _ready, so
	# behaviours can't parent their timers yet. Deferred calls flush FIFO and the
	# behaviours' _ready run before ours, so every timer exists before start().
	fsm.start.call_deferred()

func make_timer(on_timeout: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(on_timeout)
	add_child.call_deferred(timer)  # deferred for the same reason as fsm.start()
	return timer

# Nearest node across target_groups — the thing this character should attack.
func get_target() -> Node2D:
	var nearest: Node2D = null
	var best := INF
	for group in target_groups:
		for node in get_tree().get_nodes_in_group(group):
			var dist: float = global_position.distance_squared_to(node.global_position)
			if dist < best:
				best = dist
				nearest = node
	return nearest

func probe_sees(probe: RayCast2D) -> bool:
	var collider = probe.get_collider()
	if collider == null:
		return false
	for group in target_groups:
		if collider.is_in_group(group):
			return true
	return false

func look_for_target(probe: RayCast2D) -> bool:
	var target = get_target()
	if not target:
		return false
	probe.look_at(target.global_position)
	# RayCast2D only recasts once per physics step; without forcing an update here,
	# probe_sees would read the collision from *before* this frame's look_at, which is
	# harmless for callers polling every physics frame (the lag self-corrects) but wrong
	# for a one-shot check like Guard's post-windup decision.
	probe.force_raycast_update()
	return probe_sees(probe)

func play(anim: String) -> void:
	# A summon may lack an animation a behaviour asks for (e.g. a static turret with no
	# idle tag). Rather than error on the missing anim, lock in place on the current frame.
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	else:
		sprite.pause()

func face(dir_x: float) -> void:
	# Deadzone ignores near-vertical headings so the sprite doesn't flip-flicker.
	if absf(dir_x) > 0.01:
		sprite.flip_h = dir_x < 0.0

func die() -> void:
	if data:
		GlobalEvent.creature_died.emit(data, global_position)
	for drop in drops:
		if drop.roll():
			GlobalEvent.loot_dropped.emit(drop.item, global_position)
	queue_free()

func _on_hurt(damage: int, source: Node) -> void:
	if incoming_damage_scale != 1.0:
		damage = maxi(1, int(ceil(damage * incoming_damage_scale)))
	health -= damage
	# Emit before die() frees us so the floating number still spawns on a live node.
	GlobalEvent.entity_damaged.emit(self, damage, source)
	if health <= 0:
		die()
