class_name EncounterMember
extends RefCounted
## One generated enemy at a World tile. Its key follows its place through Room, encounter and
## member, and is the persistence identity ticket 07 consumes. Runtime summons and death splits do
## not pass through this type and therefore receive no generated key.

var key := ""
var encounter_key := ""
var room_key := ""
var enemy: CreatureResource
var tile := Vector2i.ZERO
var leader := false
var filler := false
var teaching := false


func enemy_id() -> StringName:
	return StringName(enemy.resource_path.get_base_dir().get_file()) if enemy != null else &""
