extends Control

## Throwaway screenshot harness for the leaderboard table, driven with fabricated rows
## (show_entries takes data, so nothing here touches Talo). Shot over the glade floor because the
## panel frame is the theme's dark 9-slice and vanishes against black. Upscaled x4 nearest so 8px
## art is readable. Must run WINDOWED: --headless renders nothing to grab.

const OUT := "/tmp/claude-1000/-home-dario-Workspace-mages/7b83a6c4-8fee-434a-a6b9-a344eaa2fe99/scratchpad"
const ZOOM := 4


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("3e6b47")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel: Control = load("res://gui/leaderboard/leaderboard_panel.tscn").instantiate()
	add_child(panel)
	panel.show()
	await get_tree().process_frame
	panel.get_node("%Emblem").modulate = Color.WHITE  # the logged-out refresh reddened it
	panel.show_entries(_fake_rows())
	for _i in 6:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png("%s/board.png" % OUT)
	get_tree().quit()


func _fake_rows() -> Array[BoardEntry]:
	var now := float(Time.get_unix_time_from_system())
	var specs := [
		# alias, kills, deaths, ratio, minutes since death, killer
		["golemfood", 30.0, 5.0, 3.7, 90.0, "dirt_golem"],
		["dario", 27.0, 14.0, 1.8, 2.0, "sproutling"],
		["averyverylongname20", 24.0, 31.0, 0.9, 8.0, "fae"],
		["mo", 19.0, 3.0, 2.4, 45.0, "gnarlking"],
		["neverdies", 12.0, BoardEntry.MISSING, 12.4, BoardEntry.MISSING, ""],
		["ghost", 9.0, 7.0, 1.1, 600.0, "not_an_enemy"],
		["viperfood", 4.0, 22.0, 0.4, 15.0, "viper"],
		["freshaccount", 1.0, BoardEntry.MISSING, BoardEntry.MISSING, 120.0, "wasp"],
	]
	var out: Array[BoardEntry] = []
	for spec: Array in specs:
		var row := BoardEntry.new()
		row.player_id = spec[0]
		row.alias = spec[0]
		row.kills = spec[1]
		row.deaths = spec[2]
		row.ratio = spec[3]
		row.last_death = BoardEntry.MISSING if spec[4] == BoardEntry.MISSING else now - spec[4] * 60.0
		row.killer = spec[5]
		row.bestiary = {"sproutling": 12, "hopper": 3, "wasp": 5, "fae": 1, "mandrake": 2}
		out.append(row)
	return out
