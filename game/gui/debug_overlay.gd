extends CanvasLayer

## Text-based debug overlay for balancing spells and weapons: live player stats
## plus running damage-dealt / damage-taken tallies (totals, avg, max, recent DPS)
## and a log of the last few hits. Toggle with F3, reset the tallies with Backspace.
## Self-contained — listens on GlobalEvent.entity_damaged and polls the player node.

const DPS_WINDOW := 5.0
const LOG_SIZE := 8

@onready var panel: PanelContainer = %Panel
@onready var label: Label = %Label

var dealt_total := 0
var dealt_hits := 0
var dealt_max := 0
var taken_total := 0
var taken_hits := 0
var taken_max := 0

# [time, amount] pairs, pruned to the last DPS_WINDOW seconds for the rolling DPS.
var dealt_window: Array = []
var taken_window: Array = []
var recent: Array[String] = []

func _ready() -> void:
	GlobalEvent.entity_damaged.connect(_on_entity_damaged)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			panel.visible = not panel.visible
		elif event.keycode == KEY_BACKSPACE and panel.visible:
			_reset()

# Player vs enemy is decided by group membership: the player's hurtbox owner is
# in the "player" group, everything else is an enemy taking our damage.
func _on_entity_damaged(victim: Node, amount: int, _source: Node) -> void:
	if victim and victim.is_in_group("player"):
		taken_total += amount
		taken_hits += 1
		taken_max = maxi(taken_max, amount)
		taken_window.append([_now(), amount])
	else:
		dealt_total += amount
		dealt_hits += 1
		dealt_max = maxi(dealt_max, amount)
		dealt_window.append([_now(), amount])
	var vname := str(victim.name) if victim else "?"
	recent.push_front("%-11s %4d" % [vname.left(11), amount])
	if recent.size() > LOG_SIZE:
		recent.resize(LOG_SIZE)

func _process(_delta: float) -> void:
	_prune(dealt_window)
	_prune(taken_window)
	if panel.visible:
		label.text = _build_text()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _prune(window: Array) -> void:
	var cutoff := _now() - DPS_WINDOW
	while not window.is_empty() and window[0][0] < cutoff:
		window.pop_front()

func _window_dps(window: Array) -> float:
	var sum := 0
	for e in window:
		sum += e[1]
	return sum / DPS_WINDOW

func _avg(total: int, hits: int) -> float:
	return float(total) / hits if hits > 0 else 0.0

func _reset() -> void:
	dealt_total = 0
	dealt_hits = 0
	dealt_max = 0
	taken_total = 0
	taken_hits = 0
	taken_max = 0
	dealt_window.clear()
	taken_window.clear()
	recent.clear()

func _build_text() -> String:
	var p := get_tree().get_first_node_in_group("player")
	var lines: Array[String] = []
	lines.append("DEBUG  F3 hide  Bksp reset")
	lines.append("-- STATS ----------------")
	if p:
		lines.append("HP    %d / %d" % [p.health, p.max_health])
		lines.append("Mana  %d / %d" % [p.mana, p.max_mana])
		lines.append("Skill %d" % p.skill)
		lines.append("Speed %d" % p.speed)
	else:
		lines.append("(no player)")
	lines.append("-- DAMAGE DEALT ---------")
	lines.append("total %d  hits %d" % [dealt_total, dealt_hits])
	lines.append("avg %.1f  max %d" % [_avg(dealt_total, dealt_hits), dealt_max])
	lines.append("dps %.1f  (last %ds)" % [_window_dps(dealt_window), int(DPS_WINDOW)])
	lines.append("-- DAMAGE TAKEN ---------")
	lines.append("total %d  hits %d" % [taken_total, taken_hits])
	lines.append("avg %.1f  max %d" % [_avg(taken_total, taken_hits), taken_max])
	lines.append("dps %.1f  (last %ds)" % [_window_dps(taken_window), int(DPS_WINDOW)])
	lines.append("-- RECENT (victim dmg) --")
	if recent.is_empty():
		lines.append("(none yet)")
	else:
		lines.append_array(recent)
	return "\n".join(lines)
