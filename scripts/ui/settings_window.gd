class_name SettingsWindow
extends PanelContainer
## Settings with three tabs: Audio (volumes), Game (day/night cycle, high-speed rendering) and
## Accessibility (hide the day/night cycle when zoomed in). Changes apply at once and are saved.

signal closed

var _zoom_label: Label
var _speed_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(620, 440)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	v.add_child(_label("Settings", 26, Color(1.0, 0.82, 0.48)))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)

	# --- audio
	var audio := _tab(tabs, "Audio")
	_slider(audio, "Master volume", Settings.master_volume, _set_prop.bind("master_volume"))
	_slider(audio, "Music volume", Settings.music_volume, _set_prop.bind("music_volume"))
	_slider(audio, "Sound effects volume", Settings.sfx_volume, _set_prop.bind("sfx_volume"))
	_check(audio, "Button click sounds", Settings.ui_sounds, _set_prop.bind("ui_sounds"))
	var tr := HBoxContainer.new()
	audio.add_child(tr)
	var now := _label("Now playing: " + Sound.current_title, 13, Color(0.75, 0.72, 0.65))
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(now)
	var skip := Button.new()
	skip.text = "Next track"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_on_skip.bind(now))
	tr.add_child(skip)

	# --- game
	var game := _tab(tabs, "Game")
	_check(game, "Show the day/night cycle", Settings.day_night, _set_prop.bind("day_night"))
	_check(game, "Show FPS counter", Settings.show_fps, _set_prop.bind("show_fps"))
	game.add_child(_label("Off: the world stays in daylight all the time (the clock still runs).", 12, Color(0.72, 0.7, 0.64)))
	var sr := HBoxContainer.new()
	game.add_child(sr)
	var sl := _label("Hide people and animals at game speed of", 14)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sl)
	var opt := OptionButton.new()
	for k in [[8.0, "8x or faster"], [16.0, "16x or faster"], [32.0, "32x only"], [999.0, "Never"]]:
		opt.add_item(k[1])
		opt.set_item_metadata(opt.item_count - 1, k[0])
		if absf(float(k[0]) - Settings.derender_speed) < 0.1:
			opt.select(opt.item_count - 1)
	opt.item_selected.connect(_on_speed_opt.bind(opt))
	sr.add_child(opt)
	game.add_child(_label("At high speeds the game skips drawing every person and animal, which keeps the frame rate smooth.", 12, Color(0.72, 0.7, 0.64)))

	# --- accessibility
	var acc := _tab(tabs, "Accessibility")
	_check(acc, "Hide the day/night cycle when zoomed in", Settings.freeze_zoomed, _set_prop.bind("freeze_zoomed"))
	acc.add_child(_label("The day and night pass quickly. Close up, the screen stays in steady daylight so the light doesn't keep flashing.", 12, Color(0.72, 0.7, 0.64)))
	var zr := HBoxContainer.new()
	acc.add_child(zr)
	var zl := _label("...when zoomed in more than", 14)
	zl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zr.add_child(zl)
	var zs := HSlider.new()
	zs.min_value = 35
	zs.max_value = 500
	zs.step = 5
	zs.value = Settings.freeze_zoom_pct
	zs.custom_minimum_size = Vector2(200, 24)
	zs.focus_mode = Control.FOCUS_NONE
	zr.add_child(zs)
	_zoom_label = _label("%d%%" % int(Settings.freeze_zoom_pct), 14, Color(0.6, 0.85, 1.0))
	_zoom_label.custom_minimum_size.x = 60
	zr.add_child(_zoom_label)
	zs.value_changed.connect(_on_zoom_pct)
	acc.add_child(_label("100% is the normal close-up view; the game opens at about 220%. Fully zoomed out is 35%.", 12, Color(0.72, 0.7, 0.64)))

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_on_close)
	v.add_child(close)


func _set_prop(v: Variant, prop: String) -> void:
	Settings.set(prop, v)
	_changed()


func _on_skip(now: Label) -> void:
	Sound.skip_track()
	now.text = "Now playing: " + Sound.current_title


func _on_speed_opt(i: int, opt: OptionButton) -> void:
	Settings.derender_speed = float(opt.get_item_metadata(i))
	_changed()


func _on_zoom_pct(x: float) -> void:
	Settings.freeze_zoom_pct = x
	_zoom_label.text = "%d%%" % int(x)
	_changed()


func _on_close() -> void:
	Settings.save_settings()
	closed.emit()


func _on_slider(x: float, vl: Label, cb: Callable) -> void:
	vl.text = "%d%%" % int(x * 100.0)
	cb.call(x)


func _changed() -> void:
	Settings.apply()
	Settings.save_settings()


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var m := MarginContainer.new()
	m.name = title
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	tabs.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v


func _slider(parent: Control, text: String, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(text, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(240, 24)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var vl := _label("%d%%" % int(value * 100.0), 14, Color(0.6, 0.85, 1.0))
	vl.custom_minimum_size.x = 50
	row.add_child(vl)
	s.value_changed.connect(_on_slider.bind(vl, cb))


func _check(parent: Control, text: String, on: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	parent.add_child(c)


func _label(text: String, fsize := 14, color := Color(0.93, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
