class_name UiTheme
extends RefCounted
## Shared look for all menus and HUD panels.


static func make() -> Theme:
	var th := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.10, 0.09, 0.07, 0.88)
	panel.border_color = Color(0.62, 0.50, 0.32, 0.55)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(8)
	th.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.27, 0.21, 0.14, 0.95)
	btn.border_color = Color(0.62, 0.50, 0.32, 0.7)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(5)
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.40, 0.31, 0.19, 0.95)
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.55, 0.40, 0.20, 0.95)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.18, 0.16, 0.14, 0.8)
	for cls in ["Button", "OptionButton"]:
		th.set_stylebox("normal", cls, btn)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		th.set_stylebox("disabled", cls, disabled)
		th.set_stylebox("focus", cls, StyleBoxEmpty.new())
		th.set_color("font_color", cls, Color(0.95, 0.9, 0.8))
		th.set_color("font_disabled_color", cls, Color(0.55, 0.52, 0.48))
		th.set_font_size("font_size", cls, 14)
	th.set_color("font_color", "Label", Color(0.93, 0.9, 0.82))
	th.set_font_size("font_size", "Label", 14)
	th.set_color("default_color", "RichTextLabel", Color(0.93, 0.9, 0.82))
	th.set_font_size("normal_font_size", "RichTextLabel", 14)
	th.set_font_size("bold_font_size", "RichTextLabel", 15)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	bg.set_corner_radius_all(3)
	th.set_stylebox("background", "ProgressBar", bg)
	return th
