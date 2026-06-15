extends Node2D

## Nope channel effect: while the button is held, the caster's incoming damage
## drains mana instead of health. It registers itself as the player's
## damage_absorber (the hook in Player._on_hurt); channel_released() — button
## release, mana-out, or the 1-second cap ending the channel — unregisters it. The
## shield ring spins overlaid on the caster and flashes on each absorbed hit.

const _FLATTEN_SHADER = preload("res://gui/flatten.gdshader")
const _FLASH_COLOR = Color("dff6f5")  # Zughy 32 light — same as the UI ready-flash

var data: NopeResource

var _caster: Node2D

func setup(spell: SpellResource, caster: Node2D) -> void:
	data = spell
	_caster = caster
	caster.damage_absorber = self
	global_position = caster.global_position

func _process(_delta: float) -> void:
	if not is_instance_valid(_caster):
		queue_free()
		return
	global_position = _caster.global_position

## Player hook: incoming damage in, damage left for health out. The covered
## part drains mana at mana_per_damage per point.
func absorb(damage: int) -> int:
	if not is_instance_valid(_caster):
		return damage
	var cost := ceili(damage * data.mana_per_damage)
	if cost <= _caster.mana:
		_caster.mana -= cost
		GlobalEvent.player_mana_changed.emit(_caster.mana)
		_flash()
		return 0
	# Mana covers only part of the hit; the rest lands on health. SpellCaster
	# ends the channel on the next physics frame (mana hit zero).
	var covered := int(_caster.mana / data.mana_per_damage)
	_caster.mana = 0
	GlobalEvent.player_mana_changed.emit(0)
	_flash()
	return damage - covered

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
