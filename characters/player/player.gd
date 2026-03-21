extends CharacterBody2D

@export var base_max_health: int = 100
@export var base_max_mana: int = 10
@export var base_skill: int = 25
@export var base_speed: int = 80
@export var focus_mana_per_second: float = 5.0
@export var focus_ramp_time: float = 3.0
@export var focus_curve: Curve

@onready var hurtbox = $Hurtbox
@onready var fsm: FSM = $FSM

var health: int
var mana: int

# Derived stats: base values + modifiers from equipped items.
# Always read these; never write them directly — call _recompute_stats() instead.
var max_health: int
var max_mana: int
var skill: int
var speed: int

var weapon: PlayerWeapon
var hat: ItemResource
var robe: ItemResource
var can_use_weapon: bool = true
var focus_time: float = 0.0
var focus_mana_remainder: float = 0.0

func _ready() -> void:
	add_to_group("player")

	var idle_state = $FSM/Idle
	idle_state.on_physics_update.connect(_on_idle_physics_update)
	var move_state = $FSM/Move
	move_state.on_physics_update.connect(_on_move_physics_update)
	var focus_state = $FSM/Focus
	focus_state.on_physics_update.connect(_on_focus_physics_update)
	focus_state.on_enter.connect(_on_focus_enter)
	focus_state.on_exit.connect(_on_focus_exit)

	hurtbox.hurt.connect(_on_hurt)

	GlobalEvent.equipment_changed.connect(_on_equipment_changed)

	_recompute_stats()
	health = max_health
	mana = max_mana
	_broadcast_stats()

func get_input_direction() -> Vector2:
	var direction_x := Input.get_axis("left", "right")
	var direction_y := Input.get_axis("up", "down")
	return Vector2(direction_x, direction_y).normalized()

func _on_idle_physics_update(_delta: float) -> void:
	if Input.is_action_just_pressed("focus"):
		fsm.transition_to("Focus")
		return

	var direction = get_input_direction()

	if direction != Vector2.ZERO:
		fsm.transition_to("Move")
		return

	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.y = move_toward(velocity.y, 0, speed)
	move_and_slide()

func _on_move_physics_update(_delta: float) -> void:
	var direction = get_input_direction()

	if direction == Vector2.ZERO:
		fsm.transition_to("Idle")
		return

	velocity = direction * speed
	move_and_slide()

func _on_focus_enter() -> void:
	can_use_weapon = false
	focus_time = 0.0
	focus_mana_remainder = 0.0

func _on_focus_exit() -> void:
	can_use_weapon = true

func _on_focus_physics_update(delta: float) -> void:
	if Input.is_action_just_released("focus"):
		fsm.transition_to("Idle")
		return

	focus_time += delta
	var t = clampf(focus_time / focus_ramp_time, 0.0, 1.0)
	var rate = focus_curve.sample(t) * focus_mana_per_second if focus_curve else t * focus_mana_per_second

	focus_mana_remainder += rate * delta
	var whole = int(focus_mana_remainder)
	if whole > 0 and mana < max_mana:
		focus_mana_remainder -= whole
		mana = mini(mana + whole, max_mana)
		GlobalEvent.player_mana_changed.emit(mana)

func _die() -> void:
	queue_free()

func _on_hurt(damage: int) -> void:
	health -= damage
	health = max(health, 0)
	GlobalEvent.player_health_changed.emit(health)

	if health <= 0:
		_die()

# Computes derived stats from base values and equipped item modifiers.
# Call this whenever equipment changes or on init.
func _recompute_stats() -> void:
	max_health = base_max_health
	max_mana = base_max_mana
	skill = base_skill
	speed = base_speed

	if weapon and weapon.data:
		max_health += weapon.data.max_health_modifier
		max_mana += weapon.data.max_mana_modifier
		skill += weapon.data.skill_modifier
		speed += weapon.data.speed_modifier
	if hat:
		max_health += hat.max_health_modifier
		max_mana += hat.max_mana_modifier
		skill += hat.skill_modifier
		speed += hat.speed_modifier
	if robe:
		max_health += robe.max_health_modifier
		max_mana += robe.max_mana_modifier
		skill += robe.skill_modifier
		speed += robe.speed_modifier

	health = clamp(health, 0, max_health)
	mana = clamp(mana, 0, max_mana)

func _broadcast_stats() -> void:
	GlobalEvent.player_max_health_changed.emit(max_health)
	GlobalEvent.player_health_changed.emit(health)
	GlobalEvent.player_max_mana_changed.emit(max_mana)
	GlobalEvent.player_mana_changed.emit(mana)
	GlobalEvent.player_skill_changed.emit(skill)
	GlobalEvent.player_speed_changed.emit(speed)

func _on_equipment_changed(slot: GlobalInventory.Slot) -> void:
	match slot.type:
		GlobalInventory.ItemType.WEAPON:
			if weapon:
				weapon.queue_free()
				weapon = null
			if slot.item:
				weapon = PlayerWeapon.new()
				weapon.name = "Weapon"
				add_child(weapon)
				weapon.setup_for_player(slot.item as WeaponResource, self)
		GlobalInventory.ItemType.HAT:
			hat = slot.item
		GlobalInventory.ItemType.ROBE:
			robe = slot.item
	_recompute_stats()
	_broadcast_stats()
