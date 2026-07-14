extends Node2D
class_name CreatureSpellCaster

## The creature-side head of the spell system, replacing the old CreatureWeapon:
## a behaviour hands it a SpellResource (usually an ad-hoc WeaponSpellResource —
## the enemy's bespoke, unregistered version of a player spell) and calls
## try_cast when its timing says attack. The effect is spawned through the same
## setup(spell, caster) contract the player's SpellCaster uses, with the owning
## Creature as the caster — faction (bullet layer, target groups), aim, and
## skill all come from the creature, so player and enemy fire the same effects.
##
## One node per spell; a creature with two attacks carries two casters. The
## cooldown runs from the cast (behaviours drive their own cadence and poll
## can_cast, exactly as they polled can_fire).

var spell: SpellResource
var can_cast: bool = true

var _cooldown: Timer
var _creature: Creature

func setup_for_creature(p_spell: SpellResource) -> void:
	spell = p_spell
	_creature = _owner_creature()
	if _cooldown == null:
		_cooldown = Timer.new()
		_cooldown.one_shot = true
		_cooldown.timeout.connect(func(): can_cast = true)
		add_child(_cooldown)

## Cast toward target_position. Returns true if the cast went off.
func try_cast(from_position: Vector2, target_position: Vector2) -> bool:
	if not can_cast or spell == null or spell.effect_scene == null:
		return false
	# The behaviour decides where to aim (rotated rings, flank shots, last known
	# position); stamp it on the creature so the effect's get_aim_direction —
	# sampled at each shot — reads this cast's aim.
	if _creature:
		_creature.aim_direction = (target_position - from_position).normalized()
	var effect := spell.effect_scene.instantiate()
	effect.setup(spell, _creature if _creature else self)
	get_tree().root.add_child(effect)
	can_cast = false
	_cooldown.start(maxf(spell.cooldown, 0.05))
	return true

func _owner_creature() -> Creature:
	var node: Node = get_parent()
	while node and not (node is Creature):
		node = node.get_parent()
	return node as Creature
