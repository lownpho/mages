extends CharacterBody2D

## Debug target: stands still and never dies. Hits still flow through its
## Hurtbox, so GlobalEvent.entity_damaged fires and the debug overlay tallies
## the damage — it just absorbs everything instead of losing health.
## Uses the generic placeholder sprite.

func _ready() -> void:
	add_to_group("enemies")
	$Hurtbox.hurt.connect(_on_hurt)

func _on_hurt(damage: int, source: Node) -> void:
	# Invincible by design, but still report the hit so the debug overlay tallies it.
	GlobalEvent.entity_damaged.emit(self, damage, source)
