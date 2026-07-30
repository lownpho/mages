extends PanelContainer

## One bestiary card: the enemy's idle animation (a CreatureIcon) with its kill count below.
## Locked entries show a gray silhouette and no count — the silhouette is the "not discovered
## yet" signal, no text needed. All the icon/silhouette/animation work lives in CreatureIcon;
## this card just binds it and drives the count. The count is handed in rather than looked up,
## so the same card serves the local book and another player's (the leaderboard drill-in).
##
## The cell is a FIXED 24x24 and clips: creatures draw at native size (never scaled, so a
## sproutling stays smaller than a golem), which means the grid must not reflow around whatever
## art it is handed. Anything larger than the cell is cropped rather than allowed to resize the
## slot — if a future enemy needs more room, raise the cell for every card at once.

var enemy_id: StringName = &""

# Remote cards are a snapshot of someone else's progress, so they ignore live kill signals.
var _live := true

func _ready() -> void:
	GlobalEvent.bestiary_updated.connect(_on_bestiary_updated)

## Bind the card to an enemy type and its kill count, or to &"" for a blank filler cell (frame
## only). A count of zero is the locked state; pass `live` false to freeze the card.
func show_entry(id: StringName, kills: int, live := true) -> void:
	enemy_id = id
	_live = live
	_refresh(kills)

func _refresh(kills: int) -> void:
	%Icon.show_creature(enemy_id, kills > 0)
	%Count.text = str(kills) if kills > 0 else ""

func _on_bestiary_updated(id: StringName, kills: int) -> void:
	if _live and id == enemy_id:
		_refresh(kills)
