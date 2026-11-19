class_name SettingsWindow
extends PanelContainer
## Settings with four tabs: Audio (volumes), Game (calendar speed, day/night cycle, high-speed
## rendering), Game Rules (every rule, editable before and during a game) and Accessibility
## (hide the day/night cycle when zoomed in). Changes apply at once.

signal closed

var _zoom_label: Label
var _speed_label: Label
var _rule_values := {}
var _rule_sliders := {}


func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)
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
	game.add_child(_label("Time", 16, Color(1.0, 0.85, 0.5)))
	_rule_row(game, Config.RULES[_rule_index("calendar_speed")])
	game.add_child(_label("How fast dates, months, years and the clock move (5x = default). Walking and working speed don't change.", 12, Color(0.72, 0.7, 0.64)))
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

	# --- game rules
	var rules := _tab(tabs, "Game Rules")
	rules.add_child(_label("Every rule of the game. Changes take effect immediately, also in a game you're playing, and are saved with it.", 12, Color(0.72, 0.7, 0.64)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rules.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ""
	for r in Config.RULES:
		if r[7] != group:
			group = r[7]
			list.add_child(_label(group, 16, Color(1.0, 0.85, 0.5)))
		_rule_row(list, r)
	var reset := Button.new()
	reset.text = "Reset all rules to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_rules_reset)
	rules.add_child(reset)

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


# ---------------------------------------------------------------- rules
func _rule_index(key: String) -> int:
	for i in Config.RULES.size():
		if Config.RULES[i][0] == key:
			return i
	return 0


func _rule_row(parent: Control, r: Array) -> void:
	var row := HBoxContainer.new()
	row.tooltip_text = r[8]
	parent.add_child(row)
	var nl := _label(r[1], 13)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.custom_minimum_size.x = 300
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.tooltip_text = r[8]
	nl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(nl)
	var sl := HSlider.new()
	sl.min_value = r[2]
	sl.max_value = r[3]
	sl.step = r[4]
	sl.value = Config.rule(r[0])
	sl.custom_minimum_size = Vector2(240, 22)
	sl.focus_mode = Control.FOCUS_NONE
	sl.tooltip_text = r[8]
	row.add_child(sl)
	var vl := _label("", 13, Color(0.6, 0.85, 1.0))
	vl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vl.custom_minimum_size.x = 70
	row.add_child(vl)
	if not _rule_values.has(r[0]):
		_rule_values[r[0]] = []
		_rule_sliders[r[0]] = []
	_rule_values[r[0]].append(vl)
	_rule_sliders[r[0]].append(sl)
	sl.value_changed.connect(_on_rule.bind(r[0]))
	_show_rule(r[0])


func _on_rule(v: float, key: String) -> void:
	Config.rules[key] = v
	for s2 in _rule_sliders[key]:
		(s2 as HSlider).set_value_no_signal(v)
	_show_rule(key)


func _show_rule(key: String) -> void:
	var v := Config.rule(key)
	var r: Array = Config.RULES[_rule_index(key)]
	var text := ""
	match r[6]:
		"x":
			text = "%.2fx" % v
		"%":
			text = "%d%%" % int(round(v * 100.0))
		"b":
			text = "On" if v >= 0.5 else "Off"
		_:
			text = ("%d" % int(v)) if absf(v - roundf(v)) < 0.01 else ("%.2f" % v)
	var changed := absf(v - float(r[5])) > 0.001
	for vl in _rule_values[key]:
		(vl as Label).text = text
		(vl as Label).add_theme_color_override("font_color", Color(1.0, 0.75, 0.35) if changed else Color(0.6, 0.85, 1.0))


func _on_rules_reset() -> void:
	Config.reset_rules()
	for k in _rule_sliders.keys():
		for s2 in _rule_sliders[k]:
			(s2 as HSlider).set_value_no_signal(Config.rule(k))
		_show_rule(k)


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
