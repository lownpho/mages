extends Idle
class_name HitAlertIdle

# Idle that also alerts on taking a hit, not just on sight — for rooted defenders
# (e.g. rosebud) that should snap into their guard the instant something lands a
# blow, even a melee swing from outside the detect probe's cone.

func enter() -> void:
	super()
	creature.hurtbox.hurt.connect(_on_hit)

func exit() -> void:
	super()
	if creature.hurtbox.hurt.is_connected(_on_hit):
		creature.hurtbox.hurt.disconnect(_on_hit)

func _on_hit(_damage: int, _source: Node) -> void:
	creature.fsm.transition_to(alert_state)
