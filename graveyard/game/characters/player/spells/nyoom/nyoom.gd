extends Node2D

## Nyoom buff effect: on cast it converts the caster's skill into speed for
## `duration` seconds — speed climbs by skill * scaling while skill drops to
## what's left, the "cash damage into legs" trade. The conversion is captured as
## a one-off stat-modifier buff (see Player.add_buff) so the player's recompute
## flow folds it in like equipment; when the timer ends the buff is removed.
## The effect plays a one-shot speck-burst, then settles into a sparse drifting
## loop of motes overlaid on the caster for the duration.

var data: NyoomResource

var _caster: Node2D
var _buff: ItemResource

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	global_position = caster.global_position

	# Snapshot skill now and trade it: +speed, −skill for the duration.
	var skill: int = caster.skill
	_buff = ItemResource.new()
	_buff.speed_modifier = roundi(skill * data.skill_to_speed_scaling)
	_buff.skill_modifier = -skill
	if caster.has_method("add_buff"):
		caster.add_buff(_buff)

	# autostart, not start(): setup() runs before SpellCaster adds us to the tree,
	# and a Timer only counts down once it's in the tree — autostart fires it the
	# moment the effect (and this child) enters, regardless of call order.
	var timer := Timer.new()
	timer.one_shot = true
	timer.autostart = true
	timer.wait_time = data.duration
	timer.timeout.connect(_expire)
	add_child(timer)

	$Wind.play("activate")
	$Wind.animation_finished.connect(func(): $Wind.play("loop"))

func _process(_delta: float) -> void:
	if not is_instance_valid(_caster):
		_expire()
		return
	global_position = _caster.global_position

func _expire() -> void:
	if is_instance_valid(_caster) and _caster.has_method("remove_buff"):
		_caster.remove_buff(_buff)
	queue_free()
