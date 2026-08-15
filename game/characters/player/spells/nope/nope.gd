extends Node2D

## Nope channel effect: while the button is held, the caster's incoming damage is soaked by
## an absorb pool instead of health. It registers itself as the caster's damage_absorber;
## channel_released() unregisters it. When the pool runs dry the bubble breaks early.

const _FLATTEN_SHADER = preload("res://gui/flatten.gdshader")
const _FLASH_COLOR = Palette.WHITE  # Zughy 32 light — same as the UI ready-flash

var data: NopeResource

var _caster: Node2D
var _absorb_left: int
var _leech_pool: float

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	_absorb_left = data.absorb_amount
	caster.damage_absorber = self
	global_position = caster.global_position

func _process(_delta: float) -> void:
	if not is_instance_valid(_caster):
		queue_free()
		return
	global_position = _caster.global_position

## Player hook: incoming damage in, damage left for health out. absorb_amount 0
## means the bubble is bottomless for the channel's duration.
func absorb(damage: int) -> int:
	if not is_instance_valid(_caster):
		return damage
	_flash()
	if data.absorb_amount <= 0:
		_leech(damage)
		return 0
	var covered := mini(damage, _absorb_left)
	_absorb_left -= covered
	_leech(covered)
	if _absorb_left <= 0:
		_break_shield()
	return damage - covered

# Small hits round to nothing on their own, so the fraction carries between them.
func _leech(blocked: int) -> void:
	_leech_pool += blocked * data.leech_fraction
	var healed := int(_leech_pool)
	if healed <= 0:
		return
	_leech_pool -= healed
	_caster.health = mini(_caster.health + healed, _caster.max_health)
	if _caster.is_in_group("player"):
		GlobalEvent.player_health_changed.emit(_caster.health)

# The pool ran dry: stop absorbing immediately. The channel itself keeps its
# own lifecycle (SpellCaster still calls channel_released on release/cap).
func _break_shield() -> void:
	if is_instance_valid(_caster) and _caster.damage_absorber == self:
		_caster.damage_absorber = null
	$Ring.hide()

func channel_released() -> void:
	if is_instance_valid(_caster) and _caster.damage_absorber == self:
		_caster.damage_absorber = null
	queue_free()

func _flash() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _FLATTEN_SHADER
	mat.set_shader_parameter("flat_color", _FLASH_COLOR)
	$Ring.material = mat
	var tween := create_tween()
	tween.tween_interval(0.1)
	tween.tween_callback(func(): $Ring.material = null)
