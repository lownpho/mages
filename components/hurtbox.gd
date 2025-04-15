extends Area2D

# Just damage for now, it can be a more complex "effect"
signal hurt(damage: int)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	var damage = 0
	
	if body.has_method("get_damage"):
		damage = body.get_damage()
		emit_signal("hurt", damage)
	else:
		print("Body has no get_damage method! Body name: ", body.name)
		
	 # This logic should be in the bullet
	if body.is_in_group("bullets"):
		body.queue_free()
