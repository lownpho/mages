@tool
class_name Professor
extends Area2D

## A Professor. Walk up and they read the Bestiary page of the Biome they stand in, and a page with
## every creature on it earns what lies one Biome onward: a portal Professor opens a way into it, an
## item Professor gives up one of the things that drop there. Anything less earns only a remark on
## how far the page has come, worded so it tells the visitor which of the two they are standing in
## front of, and a Professor with nothing onward to point at says so.
##
## The gift comes once a Run: the Professor writes `given` into its Object state, which outlives its
## scene, so a portal it opened stands again when its chunk reloads and an item is never handed over
## twice. Which page it reads, which Biome lies onward and what that earns are all generated
## (SitePlanner); the wording and the tints are the scene's.
##
## The art is a tinted player frame for now, one tint per kind.

## Relayed from the portal this Professor opens, so ObjectSpawner carries the traveller through it.
signal warp_entered(body: Node2D, destination_room: String, landing: Vector2i)

const PORTAL_SCENE := preload("res://objects/door/door.tscn")

## Where the portal stands relative to the Professor: inside the clear disc the interior stamps
## around an Object spot, and far enough out that walking up to the Professor isn't already walking
## into it.
const PORTAL_OFFSET := Vector2(24, 0)
## Where a gift lands. Below the Professor, clear of the spot the visitor is standing on.
const GIFT_OFFSET := Vector2(0, 24)

## What they say, line by line. The note is a progress line and a promise line, joined. {biome} is
## the page they read, {next} the Biome onward, {seen} and {total} the page's count.
@export_group("Progress")
@export_multiline var unknown_line := ""
@export_multiline var partial_line := ""
@export_multiline var complete_line := ""
@export_group("Promise")
@export_multiline var portal_promise := ""
@export_multiline var portal_reward := ""
@export_multiline var item_promise := ""
@export_multiline var item_reward := ""
@export_multiline var dormant_line := ""
@export_multiline var spent_line := ""
@export_group("Art")
@export var portal_tint := Color(0.6, 0.85, 0.75)
@export var item_tint := Color(0.6, 0.85, 0.75)

## Generated setup data, and the Object state inside it. Empty for a hand-placed Professor, who then
## reads an empty page and has nothing onward.
var _data: Dictionary = {}
var _state: Dictionary = {}
var _portal: Door

@onready var _label: Label = $Label
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_label.visible = false
	_sprite.modulate = portal_tint if _opens_portal() else item_tint
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# A portal opened earlier this Run comes back with its Professor, so a chunk reload can't
	# strand the player on this side of a way they already earned.
	if _opens_portal() and _given():
		_open_portal()


## Configure a World Professor from its generated data (ObjectSpawner). It arrives before the node
## is in the tree, so everything it decides is applied in _ready().
func setup(data: Dictionary) -> void:
	_data = data
	_state = data.get("state", {})


func _on_body_entered(_body: Node2D) -> void:
	var earned := not _given() and _has_reward() and _page_is_complete()
	if earned:
		_give()
	_label.text = _note(earned)
	_label.visible = true


func _on_body_exited(_body: Node2D) -> void:
	_label.visible = false


## Hands over what the page earned and remembers it, so the rest of the Run gets only the note.
func _give() -> void:
	_state["given"] = true
	if _opens_portal():
		_open_portal()
	else:
		GlobalEvent.loot_dropped.emit(_data.reward_item, global_position + GIFT_OFFSET)


## Stands the portal beside the Professor, leading where its generated data points and wearing the
## door art of the Biome it opens onto. A Door arms only after a physics step with nothing
## overlapping it, so one appearing under the visitor waits for them to step out and walk back in
## rather than flinging them off at once. The opening visit happens inside a physics query flush,
## where an Area2D may not come online, so the portal joins the tree deferred.
func _open_portal() -> void:
	if is_instance_valid(_portal):
		return
	_portal = PORTAL_SCENE.instantiate() as Door
	_portal.setup({"art": _data.art, "destination_room": _data.destination_room,
			"landing": _data.landing})
	_portal.position = PORTAL_OFFSET
	_portal.warp_entered.connect(func(body: Node2D, room: String, landing: Vector2i) -> void:
		warp_entered.emit(body, room, landing))
	add_child.call_deferred(_portal)


## The progress line and the promise line, joined. `earned` marks the visit that just paid out, so
## the Professor names the gift then and only remarks on it afterwards.
func _note(earned: bool) -> String:
	var progress := _progress()
	var fields := {"biome": _title(_data.get("biome", &"")), "next": _title(_data.get("next_biome", &"")),
			"seen": progress.x, "total": progress.y}
	var lines: Array[String] = []
	if progress.x == 0:
		lines.append(unknown_line)
	elif progress.x < progress.y:
		lines.append(partial_line)
	else:
		lines.append(complete_line)
	if not _has_reward():
		lines.append(dormant_line)
	elif earned:
		lines.append(portal_reward if _opens_portal() else item_reward)
	elif _given():
		lines.append(spent_line)
	else:
		lines.append(portal_promise if _opens_portal() else item_promise)
	return "\n".join(lines).format(fields)


## How many of the page's creatures the Bestiary has unlocked, as (killed, total).
func _progress() -> Vector2i:
	var page: Array = _data.get("page", [])
	var done := 0
	for id: StringName in page:
		if GlobalBestiary.is_unlocked(id):
			done += 1
	return Vector2i(done, page.size())


func _page_is_complete() -> bool:
	var progress := _progress()
	return progress.y > 0 and progress.x == progress.y


func _opens_portal() -> bool:
	return _data.get("opens_portal", false)


## Whether this Professor has anything to give: a portal needs somewhere planned to land, an item
## needs a Biome onward that drops something.
func _has_reward() -> bool:
	if _data.get("next_biome", &"") == &"":
		return false
	if _opens_portal():
		return _data.get("destination_room", "") != "" and _data.get("landing", Vector2i.MAX) != Vector2i.MAX
	return _data.get("reward_item") != null


func _given() -> bool:
	return _state.get("given", false)


## "deepwood" -> "Deepwood", the name the Bestiary prints above that page.
func _title(biome_id: StringName) -> String:
	return String(biome_id).capitalize()
