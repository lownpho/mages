extends Node2D

## Clang: for `duration` seconds the caster's weapon-spell bullets pierce. Sets
## the generic Player.bullets_pierce flag on cast and clears it on expiry — the
## flag is read by weapon_spell.gd when it stamps each bullet, so no bullet code
## knows about Clang. Self-cast; no aim, no collision.

var data: ClangResource
var _caster: Node2D

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	global_position = caster.global_position

func _ready() -> void:
	if _caster.get("bullets_pierce") != null:
		_caster.bullets_pierce = true
	var timer := Timer.new()
	timer.one_shot = true
	timer.autostart = true
	timer.wait_time = data.duration
	timer.timeout.connect(_expire)
	add_child(timer)

func _process(_delta: float) -> void:
	if not is_instance_valid(_caster):
		queue_free()

func _expire() -> void:
	if is_instance_valid(_caster) and _caster.get("bullets_pierce") != null:
		_caster.bullets_pierce = false
	queue_free()
