extends Control
## Main menu with its pages: title screen, new world setup, custom game rules, races, the flag
## designer and loading a saved game.

const SIZES := [[256, "Small (256 x 256)"], [384, "Medium (384 x 384)"], [512, "Large (512 x 512)"]]

var bg_tex: TextureRect
var pages := {}
var seed_edit: LineEdit
var size_opt: OptionButton
var map_opt: OptionButton
var easy_check: CheckButton
var tribes_spin: SpinBox
var tribe_edit: LineEdit
var preview: TextureRect
var preview_label: Label
var race_opt: OptionButton
var races_box: VBoxContainer
var rules_values := {}        # rule key -> Label
var rules_sliders := {}
var flag_previews: Array = []
var flag_controls := {}


func _ready() -> void:
	theme = UiTheme.make()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	bg_tex = TextureRect.new()
	bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.modulate = Color(0.45, 0.45, 0.45)
	bg_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bg_tex)
	_make_backdrop()
	pages["title"] = _page_title()
	pages["new"] = _page_new()
	pages["rules"] = _page_rules()
	pages["races"] = _page_races()
	pages["flag"] = _page_flag()
	pages["load"] = _page_load()
	pages["settings"] = _page_settings()
	show_page("title")
	if OS.get_cmdline_user_args().has("--menushots"):
		_menu_shots()


func _menu_shots() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	for pg in ["title", "new", "rules", "races", "flag", "settings"]:
		show_page(pg)
		if pg == "new":
			_on_preview()
		for k in 8:
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("/tmp/shots/menu_%s.png" % pg)
		print("saved menu ", pg)
	get_tree().quit()


## A random world rendered behind the menu.
func _make_backdrop() -> void:
	var wm := WorldGen.generate(randi() % 100000, 256)
	bg_tex.texture = MapView.make_texture(wm)


func show_page(name: String) -> void:
	for k in pages.keys():
		pages[k].visible = k == name
	if name == "new":
		_refresh_race_opt()
		_refresh_flags()


func _center_panel(min_w := 520.0) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_w
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	return [center, v]


# ---------------------------------------------------------------- title
func _page_title() -> Control:
	var cv := _center_panel(420.0)
	var v: VBoxContainer = cv[1]
	var t := _label("FIRSTBORN", 64, Color(1.0, 0.78, 0.42))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := _label("From the first humans to civilization", 18, Color(0.9, 0.86, 0.74))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	v.add_child(HSeparator.new())
	for e in [["New Game", func(): show_page("new")], ["Load Game", func(): show_page("load")],
			["Settings", func(): show_page("settings")], ["Quit", func(): get_tree().quit()]]:
		var b := _button(e[0], e[1])
		b.custom_minimum_size.y = 46
		b.add_theme_font_size_override("font_size", 20)
		v.add_child(b)
	var hint := _label("Two humans. One untamed world. Stone, bronze, iron — and the empires that follow.", 12, Color(0.72, 0.7, 0.64))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	return cv[0]


# ---------------------------------------------------------------- new world
func _page_new() -> Control:
	var cv := _center_panel(900.0)
	var v: VBoxContainer = cv[1]
	v.add_child(_label("Create a New World", 30, Color(1.0, 0.82, 0.48)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 6)
	h.add_child(left)

	left.add_child(_label("Your tribe's name", 15))
	tribe_edit = LineEdit.new()
	tribe_edit.placeholder_text = "Your Tribe"
	tribe_edit.max_length = 24
	tribe_edit.text = Config.tribe_name if Config.tribe_name != "Your Tribe" else ""
	left.add_child(tribe_edit)

	var rr := HBoxContainer.new()
	left.add_child(rr)
	var rl := _label("Your race", 15)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rr.add_child(rl)
	race_opt = OptionButton.new()
	race_opt.custom_minimum_size.x = 200
	race_opt.item_selected.connect(func(i): Config.player_race = i)
	rr.add_child(race_opt)

	left.add_child(_label("World seed", 15))
	var seed_row := HBoxContainer.new()
	left.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "leave empty for a random world"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_edit)
	seed_row.add_child(_button("Random", _on_random))

	left.add_child(_label("Map", 15))
	map_opt = OptionButton.new()
	map_opt.add_item("Random world", 0)
	map_opt.add_item("Earth (today's continents)", 1)
	map_opt.tooltip_text = "Earth: today's continents, seas, mountains, deserts, rainforests and great rivers, from 80°N to 56°S."
	map_opt.select(1 if Config.earth_mode else 0)
	map_opt.item_selected.connect(func(i): Config.earth_mode = i == 1; _on_preview())
	left.add_child(map_opt)
	left.add_child(_label("World size", 15))
	size_opt = OptionButton.new()
	for i in SIZES.size():
		size_opt.add_item(SIZES[i][1], i)
	size_opt.select(1)
	left.add_child(size_opt)

	var trow := HBoxContainer.new()
	left.add_child(trow)
	var tl := _label("Rival tribes (AI)", 15)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tl)
	tribes_spin = SpinBox.new()
	tribes_spin.min_value = 0
	tribes_spin.max_value = 10
	tribes_spin.value = Config.ai_tribes
	trow.add_child(tribes_spin)

	var fog_check := CheckButton.new()
	fog_check.text = "Fog of war (the map starts hidden)"
	fog_check.button_pressed = Config.fog_of_war
	fog_check.focus_mode = Control.FOCUS_NONE
	fog_check.tooltip_text = "Only the land around your camp is known at first. Your Billies uncover the rest as they explore."
	fog_check.toggled.connect(func(on): Config.fog_of_war = on)
	left.add_child(fog_check)
	easy_check = CheckButton.new()
	easy_check.text = "Easy Birth (every woman has at least 2 children)"
	easy_check.button_pressed = Config.rule("easy_birth") >= 0.5
	easy_check.focus_mode = Control.FOCUS_NONE
	easy_check.tooltip_text = "Every woman gives birth at least twice before 45 (once when her tribe has more than 100 people). Paused while the tribe lacks housing. Also in Game Rules."
	easy_check.toggled.connect(func(on): Config.rules["easy_birth"] = 1.0 if on else 0.0; _sync_easy())
	left.add_child(easy_check)
	left.add_child(HSeparator.new())
	var custom := HBoxContainer.new()
	custom.add_theme_constant_override("separation", 6)
	left.add_child(custom)
	for e in [["Game Rules…", "rules"], ["Races…", "races"], ["Flag Designer…", "flag"]]:
		var b := _button(e[0], show_page.bind(e[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom.add_child(b)
	left.add_child(_label("Rule presets:", 13, Color(0.85, 0.8, 0.65)))
	var pre := HBoxContainer.new()
	pre.add_theme_constant_override("separation", 4)
	left.add_child(pre)
	for pn in Config.PRESETS.keys():
		var pb := _button(pn, _on_preset.bind(pn))
		pb.tooltip_text = Config.PRESET_DESC[pn]
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.add_theme_font_size_override("font_size", 13)
		pre.add_child(pb)
	var rr2 := _button("Randomize all rule sliders", _on_rules_random_new)
	rr2.tooltip_text = "Every Game Rules slider gets a random (but playable) value. Open Game Rules to see or tweak them."
	left.add_child(rr2)
	left.add_child(_label("After the world is made you choose where your tribe begins.", 12, Color(0.72, 0.7, 0.64)))
	left.add_child(_button("Preview world", _on_preview))
	var start := _button("Start New Game", _on_start)
	start.custom_minimum_size.y = 46
	start.add_theme_font_size_override("font_size", 19)
	left.add_child(start)
	left.add_child(_button("Back", show_page.bind("title")))

	var right := VBoxContainer.new()
	h.add_child(right)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(400, 400)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(preview)
	preview_label = _label("Press Preview to see the world.\nThe same seed always creates the same land.", 12, Color(0.72, 0.7, 0.64))
	preview_label.custom_minimum_size.x = 400
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(preview_label)
	var fr := HBoxContainer.new()
	right.add_child(fr)
	fr.add_child(_label("Your flag:", 14))
	fr.add_child(_flag_preview(Vector2(90, 60)))
	return cv[0]


func _refresh_race_opt() -> void:
	race_opt.clear()
	for i in Config.races.size():
		race_opt.add_item(Config.race_name(i), i)
	Config.player_race = clampi(Config.player_race, 0, Config.races.size() - 1)
	race_opt.select(Config.player_race)


func _current_seed() -> int:
	if seed_edit.text.strip_edges().is_empty():
		_on_random()
	return Config.seed_from_text(seed_edit.text)


func _current_size() -> int:
	return int(SIZES[size_opt.selected][0])


func _on_random() -> void:
	seed_edit.text = str(randi() % 1000000000)


func _on_preview() -> void:
	var s := _current_seed()
	preview_label.text = "Generating…"
	await get_tree().process_frame
	var wm := EarthGen.generate(s, _current_size()) if Config.earth_mode else WorldGen.generate(s, _current_size())
	var img := MapView.make_texture(wm).get_image()
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var q := wm.spawn + Vector2i(ox, oy)
			if wm.inb(q):
				img.set_pixel(q.x, q.y, Color(1, 1, 1))
	preview.texture = ImageTexture.create_from_image(img)
	preview_label.text = "Seed %d · %d x %d tiles. White dot = suggested starting point." % [s, wm.w, wm.h]


func _on_start() -> void:
	Config.new_game(_current_seed(), _current_size())
	Config.ai_tribes = int(tribes_spin.value)
	var tn := tribe_edit.text.strip_edges()
	Config.tribe_name = tn if tn != "" else "Your Tribe"
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# ---------------------------------------------------------------- rules
func _page_rules() -> Control:
	var cv := _center_panel(760.0)
	var v: VBoxContainer = cv[1]
	v.add_child(_label("Game Rules", 30, Color(1.0, 0.82, 0.48)))
	v.add_child(_label("Tune births, aging, illness, research and the world. Hover a rule for details.", 13, Color(0.8, 0.77, 0.7)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ""
	for r in Config.RULES:
		if r[7] != group:
			group = r[7]
			var gl := _label(group, 18, Color(1.0, 0.85, 0.5))
			list.add_child(gl)
		var row := HBoxContainer.new()
		row.tooltip_text = r[8]
		list.add_child(row)
		var nl := _label(r[1], 14)
		nl.custom_minimum_size.x = 300
		nl.tooltip_text = r[8]
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nl)
		var sl := HSlider.new()
		sl.min_value = r[2]
		sl.max_value = r[3]
		sl.step = r[4]
		sl.value = Config.rule(r[0])
		sl.custom_minimum_size = Vector2(300, 24)
		sl.focus_mode = Control.FOCUS_NONE
		sl.tooltip_text = r[8]
		row.add_child(sl)
		var vl := _label("", 14, Color(0.6, 0.85, 1.0))
		vl.custom_minimum_size.x = 90
		row.add_child(vl)
		rules_values[r[0]] = vl
		rules_sliders[r[0]] = sl
		sl.value_changed.connect(_on_rule_changed.bind(r[0]))
		_show_rule(r[0])
	var bh := HBoxContainer.new()
	v.add_child(bh)
	bh.add_child(_button("Reset to defaults", _on_rules_reset))
	bh.add_child(_button("Randomize", _on_rules_random))
	bh.add_child(VSeparator.new())
	for pn in Config.PRESETS.keys():
		var pb2 := _button(pn, _on_preset.bind(pn))
		pb2.tooltip_text = Config.PRESET_DESC[pn]
		bh.add_child(pb2)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	bh.add_child(_button("Done", show_page.bind("new")))
	return cv[0]


func _on_rule_changed(v: float, key: String) -> void:
	Config.rules[key] = v
	_show_rule(key)
	if key == "easy_birth":
		_sync_easy()


## Keeps the Easy Birth switch on the new-world page and the Game Rules slider in step.
func _sync_easy() -> void:
	if easy_check != null:
		easy_check.set_pressed_no_signal(Config.rule("easy_birth") >= 0.5)
	if rules_sliders.has("easy_birth"):
		rules_sliders["easy_birth"].set_value_no_signal(Config.rule("easy_birth"))
		_show_rule("easy_birth")


func _show_rule(key: String) -> void:
	var v := Config.rule(key)
	for r in Config.RULES:
		if r[0] != key:
			continue
		match r[6]:
			"x":
				rules_values[key].text = "%.2fx" % v
			"%":
				rules_values[key].text = "%d%%" % int(round(v * 100.0))
			"b":
				rules_values[key].text = "On" if v >= 0.5 else "Off"
			_:
				rules_values[key].text = ("%d" % int(v)) if absf(v - roundf(v)) < 0.01 else ("%.2f" % v)
		var changed := absf(v - float(r[5])) > 0.001
		rules_values[key].add_theme_color_override("font_color", Color(1.0, 0.75, 0.35) if changed else Color(0.6, 0.85, 1.0))


func _on_preset(pn: String) -> void:
	Config.apply_preset(pn)
	_sync_easy()
	for k in rules_sliders.keys():
		rules_sliders[k].set_value_no_signal(Config.rule(k))
		_show_rule(k)
	preview_label.text = "%s rules applied: %s Open Game Rules… to fine-tune them." % [pn, Config.PRESET_DESC[pn]]


func _on_rules_random_new() -> void:
	Config.randomize_rules()
	_sync_easy()
	preview_label.text = "Game rules randomized! Open Game Rules… to see them."


func _on_rules_random() -> void:
	Config.randomize_rules()
	_sync_easy()
	for k in rules_sliders.keys():
		rules_sliders[k].set_value_no_signal(Config.rule(k))
		_show_rule(k)


func _on_rules_reset() -> void:
	Config.reset_rules()
	for k in rules_sliders.keys():
		rules_sliders[k].set_value_no_signal(Config.rule(k))
		_show_rule(k)


# ---------------------------------------------------------------- races
func _page_races() -> Control:
	var cv := _center_panel(640.0)
	var v: VBoxContainer = cv[1]
	v.add_child(_label("Races", 30, Color(1.0, 0.82, 0.48)))
	v.add_child(_label("Peoples from other worlds. Name them and pick their skin colour. Rival tribes are drawn from these races.", 13, Color(0.8, 0.77, 0.7)))
	races_box = VBoxContainer.new()
	races_box.add_theme_constant_override("separation", 4)
	v.add_child(races_box)
	var mixed := CheckButton.new()
	mixed.text = "Rival tribes have random races (off: everyone is your race)"
	mixed.button_pressed = Config.mixed_races
	mixed.focus_mode = Control.FOCUS_NONE
	mixed.toggled.connect(func(on): Config.mixed_races = on)
	v.add_child(mixed)
	var bh := HBoxContainer.new()
	v.add_child(bh)
	bh.add_child(_button("Add race", _on_add_race))
	bh.add_child(_button("Reset races", _on_reset_races))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	bh.add_child(_button("Done", show_page.bind("new")))
	_rebuild_races()
	return cv[0]


func _rebuild_races() -> void:
	for c in races_box.get_children():
		races_box.remove_child(c)
		c.queue_free()
	for i in Config.races.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		races_box.add_child(row)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(28, 28)
		sw.color = Config.races[i]["skin"]
		row.add_child(sw)
		var ne := LineEdit.new()
		ne.text = str(Config.races[i]["name"])
		ne.max_length = 20
		ne.custom_minimum_size.x = 220
		ne.text_changed.connect(_on_race_name.bind(i))
		row.add_child(ne)
		var cp := ColorPickerButton.new()
		cp.color = Config.races[i]["skin"]
		cp.edit_alpha = false
		cp.custom_minimum_size = Vector2(90, 28)
		cp.color_changed.connect(_on_race_color.bind(i, sw))
		row.add_child(cp)
		row.add_child(_label("skin", 12, Color(0.75, 0.72, 0.65)))
		if Config.races.size() > 1:
			row.add_child(_button("Remove", _on_remove_race.bind(i)))


func _on_race_name(t: String, i: int) -> void:
	Config.races[i]["name"] = t if t.strip_edges() != "" else "Race %d" % (i + 1)


func _on_reset_races() -> void:
	Config.reset_races()
	_rebuild_races()


func _on_race_color(col: Color, i: int, sw: ColorRect) -> void:
	Config.races[i]["skin"] = col
	sw.color = col


func _on_flag_opt(idx: int, key: String) -> void:
	Config.flag[key] = idx
	_refresh_flags()


func _on_flag_color(col: Color, key: String) -> void:
	Config.flag[key] = col
	_refresh_flags()


func _on_add_race() -> void:
	if Config.races.size() >= 10:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Config.races.append({"name": Names.tribe(rng, rng.randi_range(0, 5)).split(" ")[0], "skin": Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.6), rng.randf_range(0.45, 0.9))})
	_rebuild_races()


func _on_remove_race(i: int) -> void:
	Config.races.remove_at(i)
	Config.player_race = clampi(Config.player_race, 0, Config.races.size() - 1)
	_rebuild_races()


# ---------------------------------------------------------------- flag designer
func _page_flag() -> Control:
	var cv := _center_panel(640.0)
	var v: VBoxContainer = cv[1]
	v.add_child(_label("Flag Designer", 30, Color(1.0, 0.82, 0.48)))
	v.add_child(_label("Your banner flies over your camp and marks your land on the world map.", 13, Color(0.8, 0.77, 0.7)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var big := _flag_preview(Vector2(270, 180))
	h.add_child(big)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("v_separation", 8)
	h.add_child(g)
	g.add_child(_label("Background", 14))
	flag_controls["bg"] = _color_btn("bg")
	g.add_child(flag_controls["bg"])
	g.add_child(_label("Pattern", 14))
	var po := OptionButton.new()
	for i in FlagArt.PATTERNS.size():
		po.add_item(FlagArt.PATTERNS[i], i)
	po.item_selected.connect(_on_flag_opt.bind("pattern"))
	flag_controls["pattern"] = po
	g.add_child(po)
	g.add_child(_label("Pattern colour", 14))
	flag_controls["fg"] = _color_btn("fg")
	g.add_child(flag_controls["fg"])
	g.add_child(_label("Emblem", 14))
	var eo := OptionButton.new()
	for i in FlagArt.EMBLEMS.size():
		eo.add_item(FlagArt.EMBLEMS[i], i)
	eo.item_selected.connect(_on_flag_opt.bind("emblem"))
	flag_controls["emblem"] = eo
	g.add_child(eo)
	g.add_child(_label("Emblem colour", 14))
	flag_controls["em"] = _color_btn("em")
	g.add_child(flag_controls["em"])
	var bh := HBoxContainer.new()
	v.add_child(bh)
	bh.add_child(_button("Randomize", _on_flag_random))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	bh.add_child(_button("Done", show_page.bind("new")))
	_sync_flag_controls()
	return cv[0]


func _color_btn(key: String) -> ColorPickerButton:
	var cp := ColorPickerButton.new()
	cp.color = Config.flag[key]
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(120, 30)
	cp.color_changed.connect(_on_flag_color.bind(key))
	return cp


func _flag_preview(sz: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.draw.connect(func(): FlagArt.draw(c, Rect2(Vector2(4, 4), sz - Vector2(8, 8)), Config.flag))
	flag_previews.append(c)
	return c


func _refresh_flags() -> void:
	for c in flag_previews:
		(c as Control).queue_redraw()


func _sync_flag_controls() -> void:
	flag_controls["bg"].color = Config.flag["bg"]
	flag_controls["fg"].color = Config.flag["fg"]
	flag_controls["em"].color = Config.flag["em"]
	flag_controls["pattern"].select(int(Config.flag["pattern"]))
	flag_controls["emblem"].select(int(Config.flag["emblem"]))
	_refresh_flags()


func _on_flag_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Config.flag = FlagArt.random_flag(rng, Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.5, 0.95)))
	_sync_flag_controls()


# ---------------------------------------------------------------- settings
func _page_settings() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var sw := SettingsWindow.new()
	sw.closed.connect(show_page.bind("title"))
	center.add_child(sw)
	return center


# ---------------------------------------------------------------- load
func _page_load() -> Control:
	var cv := _center_panel(480.0)
	var v: VBoxContainer = cv[1]
	v.add_child(_label("Load Game", 30, Color(1.0, 0.82, 0.48)))
	for i in SaveSystem.SLOTS:
		var b := _button(SaveSystem.describe(i), _on_load.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 40
		b.disabled = SaveSystem.info(i).is_empty()
		v.add_child(b)
	v.add_child(_button("Back", show_page.bind("title")))
	return cv[0]


func _on_load(slot: int) -> void:
	Config.load_game(slot)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# ---------------------------------------------------------------- helpers
func _label(text: String, fsize := 14, color := Color(0.93, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
