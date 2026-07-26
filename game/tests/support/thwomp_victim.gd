extends Node2D

## The two capabilities Thwomp's radial pulse reaches for on anything in the caster's target
## groups, and nothing else: a `hurtbox` whose `hurt` signal carries the hit, and
## apply_knockback for the shove. Player and Creature both expose them, so a stub carrying
## just these proves the pulse lands by capability rather than by knowing what it hit.

class Box extends Node:
	signal hurt(damage: int, source: Node)

var health: int = 100
var knocked: Vector2 = Vector2.ZERO
var hurtbox := Box.new()

func _ready() -> void:
	add_child(hurtbox)
	hurtbox.hurt.connect(func(damage: int, _source: Node) -> void: health -= damage)

func apply_knockback(impulse: Vector2) -> void:
	knocked += impulse
