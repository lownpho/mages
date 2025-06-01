extends Node2D
class_name BaseItem

@export var skill_modifier: int = 0
@export var speed_modifier: int = 0
@export var max_health_modifier: int = 0
@export var max_mana_modifier: int = 0

func apply_stats(target) -> void:
	target.max_health += max_health_modifier
	target.max_mana += max_mana_modifier
	target.skill += skill_modifier
	target.speed += speed_modifier

func remove_stats(target) -> void:
	target.max_health -= max_health_modifier
	target.max_mana -= max_mana_modifier
	target.skill -= skill_modifier
	target.speed -= speed_modifier
