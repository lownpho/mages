class_name RunCloudSave extends TaloLoadable
## The run save as Talo sees it: one field holding save.cfg's own text, so the account
## copy and the local file are the same bytes and the run is only ever serialised once
## (by GameState.persist). GameState owns both ends — see its cloud save section.

func register_fields() -> void:
	register_field("cfg", GameState.save_text())

func on_loaded(data: Dictionary) -> void:
	GameState.adopt_cloud_save(str(data.get("cfg", "")))
