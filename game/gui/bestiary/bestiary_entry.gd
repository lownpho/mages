extends PanelContainer

## One bestiary card: the enemy's idle animation (a CreatureIcon) with its kill count below.
## Locked entries show a gray silhouette and no count — the silhouette is the "not discovered
## yet" signal, no text needed. All the icon/silhouette/animation work lives in CreatureIcon;
## this card just binds it and drives the count.

var enemy_id: StringName = &""

func _ready() -> void:
	GlobalEvent.bestiary_updated.connect(_on_bestiary_updated)

## Bind the card to an enemy type, or to &"" for a blank filler cell (frame only).
func show_entry(id: StringName) -> void:
	enemy_id = id
	_refresh()

func _refresh() -> void:
	var unlocked := enemy_id != &"" and GlobalBestiary.is_unlocked(enemy_id)
	%Icon.show_creature(enemy_id, unlocked)
	%Count.text = str(GlobalBestiary.kill_count(enemy_id)) if unlocked else ""

func _on_bestiary_updated(id: StringName, _kills: int) -> void:
	if id == enemy_id:
		_refresh()
