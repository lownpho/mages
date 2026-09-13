class_name GeneratedEncounter
extends RefCounted
## One deterministic fight generated in a Room. Ordinary and Teaching Rooms can contain several;
## a set-piece Room contains exactly one authored Fixed encounter.

var key := ""
var room_key := ""
var centre := Vector2i.ZERO
## Challenge used for density and ordinary eligibility. Teaching Rooms expose their dipped value.
var challenge := 0
var fixed := false
var members: Array[EncounterMember] = []


func enemy_counts() -> Dictionary[CreatureResource, int]:
	var out: Dictionary[CreatureResource, int] = {}
	for member in members:
		out[member.enemy] = out.get(member.enemy, 0) + 1
	return out


func distinct_types() -> int:
	return enemy_counts().size()
