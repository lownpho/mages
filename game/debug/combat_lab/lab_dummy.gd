extends CharacterBody2D
## Combat-lab target dummy: a configurable punching bag. Swapped onto a placeholder.tscn
## instance by combat_lab.gd (set_script before add_child), so it reuses the placeholder's
## sprite/hurtbox/label without its own scene file. max_health 0 = never dies; otherwise it
## "dies" by going dark for a second and respawning at full health. Flat defence is
## subtracted per hit (min 1) so mitigation math can be eyeballed against the damage numbers.

var max_health := 0     ## 0 = invulnerable tank
var defence := 0
var health := 0

@onready var _label: Label = $NameLabel
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	health = max_health
	$Hurtbox.hurt.connect(_on_hurt)
	_refresh()


func _on_hurt(damage: int, source: Node) -> void:
	damage = maxi(1, damage - defence)
	GlobalEvent.entity_damaged.emit(self, damage, source)
	if max_health <= 0:
		return
	health -= damage
	if health <= 0:
		_respawn()
	_refresh()


func _refresh() -> void:
	if max_health <= 0:
		_label.text = "dummy  def %d" % defence if defence > 0 else "dummy"
	else:
		_label.text = "%d/%d" % [maxi(health, 0), max_health] \
				+ ("  def %d" % defence if defence > 0 else "")


func _respawn() -> void:
	_sprite.modulate = Color(0.3, 0.3, 0.3)
	$Hurtbox.monitoring = false
	get_tree().create_timer(1.0).timeout.connect(func():
		if not is_instance_valid(self):
			return
		health = max_health
		_sprite.modulate = Color.WHITE
		$Hurtbox.monitoring = true
		_refresh())
