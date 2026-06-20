extends Node2D

## Spawns floating combat numbers in response to GlobalEvent.entity_damaged — the
## same signal every Hurtbox already emits and the debug overlay consumes. Hits on
## a victim that still has a live, accumulating number merge into it (see
## damage_number.gd) rather than stacking new labels, so rapid multi-hits stay
## readable and the node count stays bounded at ~one per victim.

const NUMBER := preload("res://components/damage_hints/damage_number.tscn")
const HEAD_OFFSET := Vector2(0, -14)  # above the victim's head
# Zughy 32 palette.
const DEALT_COLOR := Color("dff6f5")  # damage the player deals — palette white
const TAKEN_COLOR := Color("e6482e")  # damage the player takes — red

var _active: Dictionary = {}  # victim -> DamageNumber currently accumulating

func _ready() -> void:
	GlobalEvent.entity_damaged.connect(_on_entity_damaged)

func _on_entity_damaged(victim: Node, amount: int, _source: Node) -> void:
	if amount <= 0 or not (victim is Node2D):
		return

	var existing = _active.get(victim)
	if existing and is_instance_valid(existing) and existing.is_accumulating:
		existing.add(amount)
		return

	var color := TAKEN_COLOR if victim.is_in_group("player") else DEALT_COLOR
	var jitter := Vector2(randf_range(-3.0, 3.0), 0.0)
	var num := NUMBER.instantiate()
	add_child(num)
	num.setup(victim, amount, color, HEAD_OFFSET + jitter)
	_active[victim] = num
	# Erase by value, not by the victim key: the victim may be freed before the
	# number fades out, and capturing it would fire a "freed capture" error here.
	# Only drops the entry if it's still us — a fresh number may have replaced it.
	num.tree_exited.connect(func() -> void:
		for v in _active:
			if _active[v] == num:
				_active.erase(v)
				return)
