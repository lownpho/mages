extends Node
## Headless check that every HUD overlay wears its window title: a %Title label across the top of
## the panel, centred, in capitals, and clear of everything else the panel draws — its close button,
## its header on every page, the body underneath. The overlays are whatever ui.gd registers in
## _panel_buttons, so a new panel without a title fails here. A title that collides with a long
## page heading is silent at 320x180, which is why every page is walked. Run:
##   godot --headless --path game res://tests/test_panel_titles.tscn

const UI_SCENE := preload("res://gui/ui.tscn")

func _ready() -> void:
	var fails: Array[String] = []

	get_window().size = Vector2i(320, 180)
	var ui := UI_SCENE.instantiate()
	add_child(ui)
	await get_tree().process_frame

	var titles: Dictionary = {}
	for panel: Control in ui._panel_buttons:
		ui._close_panels()
		panel.visible = true
		await get_tree().process_frame
		await get_tree().process_frame

		var title := panel.get_node_or_null("%Title") as Label
		if title == null:
			fails.append("%s has no %%Title" % panel.name)
			continue
		if title.text.is_empty() or title.text != title.text.to_upper():
			fails.append("%s's title '%s' is not a capitalised name" % [panel.name, title.text])
		if titles.has(title.text):
			fails.append("%s and %s are both titled '%s'" % [titles[title.text], panel.name, title.text])
		titles[title.text] = panel.name

		# Walk every page a paged panel has (clamping ends the walk), checking the title on each.
		var page := 0
		while true:
			if panel.has_method("_set_page"):
				panel._set_page(page)
				await get_tree().process_frame
			_check_title(fails, panel, title, "page %d" % page)
			if not panel.has_method("_set_page") or panel._page != page:
				break
			page += 1
		if panel.has_method("_set_page"):
			panel._set_page(0)

	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for f in fails:
			print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _check_title(fails: Array[String], panel: Control, title: Label, where: String) -> void:
	# Where the letters actually are: the label spans the panel, the text is centred inside it.
	var font := title.get_theme_font(&"font")
	var width := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			title.get_theme_font_size(&"font_size")).x
	var text := Rect2(title.global_position.x + (title.size.x - width) / 2.0, title.global_position.y,
			width, title.size.y)
	var frame := panel.get_global_rect()
	if absf(text.get_center().x - frame.get_center().x) > 1.0:
		fails.append("%s (%s): the title centres at x %s, the panel at x %s"
				% [panel.name, where, text.get_center().x, frame.get_center().x])
	if not frame.grow(-4.0).encloses(text):
		fails.append("%s (%s): the title %s runs outside the panel %s" % [panel.name, where, text, frame])
	# Everything drawn: every visible leaf Control, bar bare layout spacers.
	for c: Control in panel.find_children("*", "Control", true, false):
		if c == title or c.get_child_count() > 0 or not c.is_visible_in_tree():
			continue
		if c.get_class() == "Control" and c.get_script() == null:
			continue  # an empty spacer draws nothing
		if c is Label and (c as Label).text.is_empty():
			continue
		if text.intersects(c.get_global_rect()):
			fails.append("%s (%s): the title overlaps '%s' at %s"
					% [panel.name, where, panel.get_path_to(c), c.get_global_rect()])
