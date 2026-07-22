extends CharacterBody2D

@export var base_max_health: int = 100
@export var base_skill: int = 25
@export var base_speed: int = 80
@export var base_defence: int = 0
## Defence never blocks more than this fraction of a hit, so chip damage from
## weak enemies always lands and armour can't make you immune.
@export var defence_floor_fraction: float = 0.20
## Fraction of max health at or below which the low-health warning aura shows.
@export var low_resource_warning_fraction: float = 0.25
## Debug scenes only: dying refills health instead of wiping the save and bouncing to the
## title (permadeath would clobber the player's real run from inside a test arena).
@export var debug_never_die := false

@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var low_health_aura: AnimatedSprite2D = $LowHealthAura

var health: int

# Derived stats: base values + modifiers from equipped spells.
# Always read these; never write them directly — call _recompute_stats() instead.
var max_health: int
var skill: int
var speed: int
var defence: int

## While set, incoming damage is filtered through its absorb(damage) -> int
## (the remainder) before touching health — Nope's shield registers here.
var damage_absorber: Node2D = null
## Timed stat buffs (e.g. Nyoom). Each entry exposes the same *_modifier fields
## as ItemResource; an effect adds itself on cast and removes itself on expiry,
## and _recompute_stats folds them in alongside equipment. Generic on purpose —
## any buff effect reuses it by handing over a modifier-carrying resource.
var active_buffs: Array = []
var can_act: bool = true
# ChargeDash: while Time.get_ticks_msec() < _dash_until_ms the player is driven
# by _dash_velocity, overriding FSM movement (see start_dash).
var _dash_velocity: Vector2 = Vector2.ZERO
var _dash_until_ms: int = 0
## While true, bullet-spell bullets fired pass through hurtboxes (Clang buff).
## A spell effect sets it on cast and clears it when its window ends.
var bullets_pierce: bool = false
## The bullet-spell burst currently firing, if any — only one is ever live.
## Starting another burst (register_burst) or an exclusive spell, a cast or
## channel (cancel_bursts, called by SpellCaster), ends it onto its cooldown;
## instant spells leave it firing.
var _live_burst: Node = null
## While Time.get_ticks_msec() < this, incoming damage is ignored — a spawn buffer so
## enemies placed near the spawn point can't chip you before you've taken control.
var _grace_until_ms: int = 0

func _ready() -> void:
	add_to_group("player")

	var idle_state = $FSM/Idle
	idle_state.on_enter.connect(func(): animated_sprite.play("idle"))
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var move_state = $FSM/Move
	move_state.on_enter.connect(func(): animated_sprite.play("run"))
	move_state.on_physics_update.connect(_on_move_physics_update)
	var cast_state = $FSM/Cast
	cast_state.on_enter.connect(_on_cast_enter)
	cast_state.on_exit.connect(_on_cast_exit)

	hurtbox.hurt.connect(_on_hurt)

	GlobalEvent.equipment_changed.connect(_on_equipment_changed)
	GlobalEvent.player_health_changed.connect(_on_health_or_max_health_changed)
	GlobalEvent.player_max_health_changed.connect(_on_health_or_max_health_changed)

	# equipment_changed only fires on slot edits, not when a fresh player spawns in a
	# new scene — so fold the persisted GlobalInventory loadout into the stats once.
	_recompute_stats()
	health = max_health
	_broadcast_stats()

# On gamepad the right stick owns aim; it persists while the stick is neutral so
# a flick keeps firing that way, and falls back to the movement direction when
# the player never touches it (twin-stick convention).
var _pad_aim := Vector2.RIGHT

# Aim for spells and bullet bursts: the direction from the player toward the
# mouse, or the pad aim when the last input device was a gamepad. The single
# aim read in the spell path — effects take a direction, never a position.
func get_aim_direction() -> Vector2:
	if GlobalInput.using_gamepad:
		return _pad_aim
	return (get_global_mouse_position() - global_position).normalized()

func register_burst(burst: Node) -> void:
	cancel_bursts()  # one burst at a time: the new burst cancels any live one
	_live_burst = burst

func unregister_burst(burst: Node) -> void:
	if _live_burst == burst:
		_live_burst = null

## Interrupt the live burst — it ends onto its full cooldown. Called when an
## exclusive spell starts: a new bullet-spell burst, a cast, or a channel.
## interrupt() unwinds through unregister_burst, which clears _live_burst.
func cancel_bursts() -> void:
	if is_instance_valid(_live_burst):
		_live_burst.interrupt()

func can_burst_fire(burst: Node) -> bool:
	return can_act and _live_burst == burst

func get_input_direction() -> Vector2:
	# While the HUD captures input (controller slot navigation) the stick moves
	# the focus, not the mage.
	if GlobalInput.ui_captured:
		return Vector2.ZERO
	var direction_x := Input.get_axis("left", "right")
	var direction_y := Input.get_axis("up", "down")
	return Vector2(direction_x, direction_y).normalized()

# Generic dash: an effect (ChargeDash) drives the player in a fixed direction at
# dash_speed for `duration`, overriding normal movement and locking casts. Any
# future dash/charge spell reuses it — the effect fires its own side bullets.
func start_dash(direction: Vector2, dash_speed: float, duration: float) -> void:
	_dash_velocity = direction.normalized() * dash_speed
	_dash_until_ms = Time.get_ticks_msec() + int(duration * 1000.0)
	can_act = false

func _is_dashing() -> bool:
	return Time.get_ticks_msec() < _dash_until_ms

func _physics_process(_delta: float) -> void:
	_sample_pad_aim()
	if _is_dashing():
		velocity = _dash_velocity
		move_and_slide()
	elif _dash_velocity != Vector2.ZERO:
		# Dash just ended: stop and hand control back. Casts can't start mid-dash
		# (can_act is false), so restoring it here is always correct.
		_dash_velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		can_act = true

func _sample_pad_aim() -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick != Vector2.ZERO:
		_pad_aim = stick.normalized()
		return
	# Right stick idle: while moving, aim follows the run so casts go forward.
	var moving := get_input_direction()
	if moving != Vector2.ZERO:
		_pad_aim = moving

func _on_idle_physics_update(_delta: float) -> void:
	if _is_dashing():
		return
	var direction = get_input_direction()

	if direction != Vector2.ZERO:
		fsm.transition_to("Move")
		return

	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.y = move_toward(velocity.y, 0, speed)
	move_and_slide()

func _on_move_physics_update(_delta: float) -> void:
	if _is_dashing():
		return
	var direction = get_input_direction()

	if direction == Vector2.ZERO:
		fsm.transition_to("Idle")
		return

	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
	velocity = direction * speed
	move_and_slide()

# Spells with a cast time root the player here; SpellCaster drives the
# transition in and back out when the cast resolves.
func _on_cast_enter() -> void:
	can_act = false
	velocity = Vector2.ZERO
	animated_sprite.play("channel")

func _on_cast_exit() -> void:
	can_act = true

func _on_health_or_max_health_changed(_value: int) -> void:
	low_health_aura.visible = health > 0 and health <= max_health * low_resource_warning_fraction

func _die(source: Node) -> void:
	if debug_never_die:
		health = max_health
		GlobalEvent.player_health_changed.emit(health)
		return
	GlobalEvent.player_died.emit(source)
	# Permadeath: clear the save so there is nothing to Continue, then bounce to
	# the title screen (which frees this scene, so no queue_free needed here).
	GameState.game_over()

# Ignore all incoming damage for `seconds`, starting now (see world.gd spawn placement).
func grant_spawn_grace(seconds: float = 2.0) -> void:
	_grace_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)

func _on_hurt(damage: int, source: Node) -> void:
	# Already dead: a burst that lands several lethal hits in one frame must not
	# re-run death (duplicate death events/feed entries, repeated game_over).
	if health <= 0:
		return
	if Time.get_ticks_msec() < _grace_until_ms:
		return
	if damage_absorber and is_instance_valid(damage_absorber):
		damage = damage_absorber.absorb(damage)
		if damage <= 0:
			return
	# Flat per-hit reduction: favours the close-range playstyle (many small hits)
	# over flat HP, which only buys effective health regardless of hit size.
	damage = maxi(ceili(damage * defence_floor_fraction), damage - defence)
	health -= damage
	health = max(health, 0)
	GlobalEvent.player_health_changed.emit(health)
	# Report the post-mitigation damage so the floating number and debug tally
	# reflect what defence (and any shield) actually blocked.
	GlobalEvent.entity_damaged.emit(self, damage, source)

	if health <= 0:
		_die(source)

# Computes derived stats from base values and equipped spell modifiers.
# Call this whenever equipment changes or on init.
func _recompute_stats() -> void:
	max_health = base_max_health
	skill = base_skill
	speed = base_speed
	defence = base_defence

	for slot in GlobalInventory.spell_slots.slots:
		if slot.item:
			max_health += slot.item.max_health_modifier
			skill += slot.item.skill_modifier
			speed += slot.item.speed_modifier
			defence += slot.item.defence_modifier
	for buff in active_buffs:
		max_health += buff.max_health_modifier
		skill += buff.skill_modifier
		speed += buff.speed_modifier
		defence += buff.defence_modifier

	health = clamp(health, 0, max_health)

# Registers/removes a timed stat buff and refreshes derived stats. The buff is
# any resource carrying the ItemResource *_modifier fields; the effect that owns
# it (e.g. Nyoom) calls add on cast and remove when its duration ends.
func add_buff(buff: ItemResource) -> void:
	if buff not in active_buffs:
		active_buffs.append(buff)
	_recompute_stats()
	_broadcast_stats()

func remove_buff(buff: ItemResource) -> void:
	active_buffs.erase(buff)
	_recompute_stats()
	_broadcast_stats()

func _broadcast_stats() -> void:
	GlobalEvent.player_max_health_changed.emit(max_health)
	GlobalEvent.player_health_changed.emit(health)
	GlobalEvent.player_skill_changed.emit(skill)
	GlobalEvent.player_speed_changed.emit(speed)
	GlobalEvent.player_defence_changed.emit(defence)

func _on_equipment_changed(_slot: GlobalInventory.Slot) -> void:
	_recompute_stats()
	_broadcast_stats()
