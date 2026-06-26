extends Node

## Central scene-transition autoload. Doors (and anything else that needs to send
## the player to another scene) call `go_to()` instead of poking the SceneTree
## directly, so transitions have one home — and later, fades.

## Emitted just before the tree swaps scenes.
signal scene_changing(target: PackedScene)


## Swap to `target`.
func go_to(target: PackedScene) -> void:
	if not target:
		push_warning("SceneManager.go_to called with a null target scene")
		return
	scene_changing.emit(target)
	# Deferred: doors fire from body_entered, a physics callback, where freeing the
	# current scene's collision nodes mid-step is disallowed.
	get_tree().change_scene_to_packed.call_deferred(target)
	
