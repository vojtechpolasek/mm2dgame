extends RefCounted


static func apply(root: Node) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.22, 0.14)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.38, 0.2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.16, 0.1)
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("focus", hover)
		button.add_theme_color_override("font_color", Color(0.94, 0.96, 0.9))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 0.96))
		button.add_theme_color_override("font_pressed_color", Color(0.9, 0.92, 0.84))
		button.add_theme_font_size_override("font_size", 22)
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.88))
