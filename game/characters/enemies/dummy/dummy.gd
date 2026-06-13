extends CharacterBody2D

## Debug target: stands still and never dies. Hits still flow through its
## Hurtbox, so GlobalEvent.entity_damaged fires and the debug overlay tallies
## the damage — it just absorbs everything instead of losing health.
## Reuses the small demon sprite.

func _ready() -> void:
	add_to_group("enemies")
	$Hurtbox.hurt.connect(_on_hurt)

func _on_hurt(_damage: int) -> void:
	pass  # invincible by design
