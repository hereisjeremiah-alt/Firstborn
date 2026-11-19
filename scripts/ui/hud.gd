class_name HUD
extends CanvasLayer
## In-game interface, built in code: top resource bar, event feed, toolbar, side panels
## (build / jobs / stockpile / colony / help), info panel, minimap, world map and pause menu.

var game: Node
var root: Control
var stat_labels := {}
var season_icon: TextureRect
var clock_icon: TextureRect
var date_label: Label
var clock_label: Label
var temp_label: Label
var weather_label: Label
var speed_buttons: Array = []
var feed: VBoxContainer
var side_panel: PanelContainer
var side_title: Label
var side_body: VBoxContainer
var current_panel := ""
var build_buttons: Array = []
var jobs_pop := -1
var job_status_labels := {}
var info_panel: PanelContainer
var info_text: RichTextLabel
var info_bars: VBoxContainer
var bar_nodes := {}
var demolish_btn: Button
var info_actions: HFlowContainer
var _actions_sig := ""
var rename_layer: Control
var rename_edit: LineEdit
var rename_title: Label
var _rename_target := ""
var minimap: MapView
var worldmap_panel: PanelContainer
var terr_button: Button
var gov_layer: Control
var gov_box: VBoxContainer
var worldmap: MapView
var hint_label: Label
var pause_layer: Control
var pause_box: VBoxContainer
var gameover_shown := false
var picker: PanelContainer
var _refresh_t := 0.0

const KIND_COLORS := {"info": Color(0.92, 0.9, 0.82), "good": Color(0.6, 0.95, 0.55), "bad": Color(1.0, 0.5, 0.45), "warn": Color(1.0, 0.82, 0.4)}


func setup(g: Node) -> void:
	game = g
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)
	_build_top_bar()
	_build_feed()
	_build_toolbar()
	_build_side_panel()
	_build_info_panel()
	_build_minimap()
	_build_worldmap()
	_build_hint()
	_build_pause_menu()
	_build_picker()
	_build_rename_dialog()
	_build_research_tree()
	_build_gov_dialog()
	_build_build_window()
	_build_settings_layer()
	_build_fps()
	_build_passage_dialog()
	_build_deal_card()
	_build_planner()


# ================================================================ passage requests
## A small non-blocking card at the top of the screen when a rival tribe asks to cross your land.
var passage_panel: PanelContainer
var passage_label: Label
var passage_civ := -1


func _build_passage_dialog() -> void:
	passage_panel = PanelContainer.new()
	passage_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	passage_panel.offset_top = 52
	passage_panel.offset_left = -230
	passage_panel.offset_right = 230
	passage_panel.visible = false
	root.add_child(passage_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	passage_panel.add_child(v)
	passage_label = _label("", 14)
	passage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passage_label.custom_minimum_size.x = 440
	v.add_child(passage_label)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	h.add_child(_button("Allow for %d years" % int(Borders.ACCESS_YEARS), _on_passage.bind(true), 150))
	h.add_child(_button("Refuse", _on_passage.bind(false), 100))
	h.add_child(_button("View their tribe", _on_passage_view, 130))


func _refresh_passage() -> void:
	var sim: Sim = game.sim
	if sim.access_asks.is_empty():
		passage_panel.visible = false
		passage_civ = -1
		return
	var cid := int(sim.access_asks[0])
	var oc := sim.civ(cid)
	if oc == null or oc.collapsed or sim.at_war(0, cid):
		sim.access_asks.remove_at(0)
		return
	if cid != passage_civ:
		passage_civ = cid
		var rel := sim.relation(0, cid)
		passage_label.text = "The %s (%s, relations %s) ask permission for their Billies to cross your land.\nIf you refuse they will keep out — and resent it a little." % [
			oc.name, oc.era, Sim.relation_label(rel)]
	passage_panel.visible = true


func _on_passage(yes: bool) -> void:
	if passage_civ >= 0:
		Borders.answer(game.sim, passage_civ, yes)
	passage_civ = -1
	_refresh_passage()


func _on_passage_view() -> void:
	if passage_civ >= 0:
		game.select_civ(passage_civ)


# ================================================================ milestones
func _panel_milestones() -> void:
	var sim: Sim = game.sim
	var c := sim.colony
	side_title.text = "Milestones  (%d / %d)" % [Milestones.count_done(c), Milestones.LIST.size()]
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size.x = 370
	var s := "[color=#a09a88]Goals for your tribe. Each one pays a reward the moment you reach it.[/color]\n"
	var group := ""
	for m in Milestones.LIST:
		if str(m[4]) != group:
			group = str(m[4])
			s += "\n[b][color=#ffd27a]%s[/color][/b]\n" % group
		var id := str(m[0])
		var reward := Milestones.reward_text(m[3])
		if c.milestones.has(id):
			s += "[color=#9fe08a]✔ [b]%s[/b][/color] [color=#7f9a78]— %s[/color]\n" % [m[1], m[2]]
		else:
			var pr := Milestones.progress(sim, c, id)
			var goal := int(pr[1])
			var prog := ("  [color=#9fd8ff]%d / %d[/color]" % [mini(int(pr[0]), goal), goal]) if goal > 1 else ""
			s += "○ [b]%s[/b] — %s%s\n   [color=#c8b98a]Reward: %s[/color]\n" % [m[1], m[2], prog, reward]
	t.text = s
	side_body.add_child(t)


# ================================================================ town planner
## A palette at the bottom of the screen for painting zones and laying out roads.
var planner: PanelContainer
var planner_hint: Label


func _build_planner() -> void:
	planner = PanelContainer.new()
	planner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	planner.offset_bottom = -12
	planner.offset_top = -112
	planner.offset_left = -330
	planner.offset_right = 330
	planner.visible = false
	root.add_child(planner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	planner.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tl := _label("Plan Town", 16, Color(1.0, 0.85, 0.5))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(_button("x", toggle_planner, 28))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	v.add_child(h)
	for z in Defs.ZONES.keys():
		var zd: Dictionary = Defs.ZONES[z]
		var b := _button("%s zone" % zd["name"], game.set_tool.bind("zone%d" % int(z)), 100)
		b.add_theme_color_override("font_color", (zd["color"] as Color).lightened(0.3))
		b.tooltip_text = zd["desc"]
		h.add_child(b)
	h.add_child(_button("Erase zone", game.set_tool.bind("zone0"), 90))
	h.add_child(_button("Road", game.set_tool.bind("road"), 60))
	h.add_child(_button("Remove road", game.set_tool.bind("unroad"), 100))
	planner_hint = _label("", 12, Color(0.8, 0.78, 0.7))
	planner_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	planner_hint.custom_minimum_size.x = 640
	v.add_child(planner_hint)


func toggle_planner() -> void:
	planner.visible = not planner.visible
	if not planner.visible:
		if game.tool_mode.begins_with("zone") or game.tool_mode.ends_with("road"):
			game.set_tool("")
	else:
		game.set_tool("zone1")


func _planner_hint() -> String:
	var m: String = game.tool_mode
	if m.begins_with("zone"):
		var z := int(m.substr(4))
		if z == 0:
			return "Drag a box to erase zones."
		var zd: Dictionary = Defs.ZONES[z]
		return "Drag a box to paint a %s zone. %s" % [zd["name"], zd["desc"]]
	if m == "road":
		return "Drag from one point to another to lay out a road (it bends once). Laborers and builders build it; Billies walk about twice as fast on roads."
	if m == "unroad":
		return "Drag a box to remove roads and road plans."
	return "Pick a zone or the road tool. Zones: buildings standing in the zone that suits them get bonuses. Roads make Billies faster."


# ================================================================ deal offers
var deal_panel: PanelContainer
var deal_label: RichTextLabel
var deal_counter_btn: Button
var deal_shown := -1


func _build_deal_card() -> void:
	deal_panel = PanelContainer.new()
	deal_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	deal_panel.offset_top = 52
	deal_panel.offset_left = -250
	deal_panel.offset_right = 250
	deal_panel.visible = false
	root.add_child(deal_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	deal_panel.add_child(v)
	deal_label = RichTextLabel.new()
	deal_label.bbcode_enabled = true
	deal_label.fit_content = true
	deal_label.scroll_active = false
	deal_label.custom_minimum_size.x = 480
	v.add_child(deal_label)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(_button("Accept", _on_deal_answer.bind("accept"), 90))
	h.add_child(_button("Decline", _on_deal_answer.bind("decline"), 90))
	deal_counter_btn = _button("Counter", _on_deal_answer.bind("counter"), 170)
	h.add_child(deal_counter_btn)


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


func _refresh_deal() -> void:
	var sim: Sim = game.sim
	# the passage card takes the slot first; deals wait behind it
	if sim.deal_offers.is_empty() or passage_panel.visible:
		deal_panel.visible = false
		return
	var o: Dictionary = sim.deal_offers[0]
	if int(o["id"]) != deal_shown:
		deal_shown = int(o["id"])
		var from := sim.civ(int(o["from"]))
		var title: String = {"trade": "Trade offer", "alliance": "Alliance proposal", "tribute": "Demand for tribute", "land": "Demand for land"}[str(o["type"])]
		var col: String = "ff9f7a" if str(o["type"]) in ["tribute", "land"] else "ffd27a"
		var t := "[b][color=#%s]%s[/color][/b] from the [color=#%s]%s[/color] (%s)\n%s" % [col, title, from.color.to_html(false), from.name, Sim.relation_label(sim.relation(0, from.civ_id)), _cap(Deals.describe(sim, o))]
		if str(o["type"]) in ["tribute", "land"]:
			t += "\n[color=#a09a88]Their strength %d vs yours %d. Refusing may mean war.[/color]" % [int(sim.military_strength(from)), int(sim.military_strength(sim.colony))]
		t += "\n[color=#a09a88]Counter-offer: about %d%% chance they agree.[/color]" % roundi(Deals.counter_chance(sim, o) * 100.0)
		deal_label.text = t
		deal_counter_btn.text = Deals.counter_text(sim, o)
	deal_panel.visible = true


func _on_deal_answer(how: String) -> void:
	var sim: Sim = game.sim
	if sim.deal_offers.is_empty():
		return
	Deals.answer(sim, sim.deal_offers[0], how)
	deal_shown = -1
	_refresh_deal()


# ================================================================ FPS counter
var fps_label: Label


func _build_fps() -> void:
	fps_label = _label("", 15, Color(0.75, 1.0, 0.6))
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_top = 46
	fps_label.offset_right = -10
	fps_label.offset_left = -110
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_override("font", _tabular_font())
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = false
	root.add_child(fps_label)


# ================================================================ theme
func _label(text: String, fsize := 14, color := Color(0.93, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(cb)
	return b


func _icon(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(20, 20)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


# ================================================================ top bar
func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 40
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)
	for key in ["pop", "food", "water", "wood", "stone", "sticks", "health", "money"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(_icon(Art.icons[key]))
		var l := _label("0")
		box.add_child(l)
		box.tooltip_text = {"pop": "Population", "food": "Food stored (days of food for everyone)", "water": "Stored water / capacity",
			"wood": "Wood", "stone": "Stone", "sticks": "Sticks", "health": "Average colony health",
			"money": "%s in your tribe's bank. Traders earn them by selling goods to other tribes." % Defs.MONEY_NAME}[key]
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(box)
		stat_labels[key] = l
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	season_icon = _icon(Art.icons["spring"])
	h.add_child(season_icon)
	# fixed-width, tabular-digit labels so the bar never shifts as the date and time change
	date_label = _label("")
	_fix_width(date_label, _date_samples())
	h.add_child(date_label)
	clock_icon = _icon(Art.icons["sun"])
	h.add_child(clock_icon)
	clock_label = _label("")
	_fix_width(clock_label, ["00:00 Morning", "00:00 Evening", "00:00 Night", "00:00 Day"])
	h.add_child(clock_label)
	h.add_child(_icon(Art.icons["temp"]))
	temp_label = _label("")
	_fix_width(temp_label, ["-00°C"])
	h.add_child(temp_label)
	weather_label = _label("")
	_fix_width(weather_label, ["Cloudy", "Storm", "Clear"])
	h.add_child(weather_label)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 2)
	h.add_child(sp)
	for s in [0.0, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]:
		var txt := "||" if s == 0.0 else "%dx" % int(s)
		var b := _button(txt, Callable(game, "set_speed").bind(s), 34.0)
		b.toggle_mode = true
		b.tooltip_text = "Pause (Space)" if s == 0.0 else "Speed %dx (keys 1-6)" % int(s)
		sp.add_child(b)
		speed_buttons.append([b, s])


var _tnum_font: FontVariation


## A copy of the UI font with tabular (equal-width) digits.
func _tabular_font() -> Font:
	if _tnum_font == null:
		_tnum_font = FontVariation.new()
		_tnum_font.base_font = ThemeDB.fallback_font
		var ts := TextServerManager.get_primary_interface()
		_tnum_font.opentype_features = {ts.name_to_tag("tnum"): 1}
	return _tnum_font


## Gives a label tabular digits and a fixed width wide enough for its longest possible text.
func _fix_width(l: Label, samples: Array) -> void:
	var f := _tabular_font()
	l.add_theme_font_override("font", f)
	var w := 0.0
	for t in samples:
		w = maxf(w, f.get_string_size(str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	l.custom_minimum_size.x = ceilf(w) + 4.0
	l.clip_text = true


func _date_samples() -> Array:
	var out: Array = []
	for se in Defs.SEASONS:
		for m in Defs.MONTHS:
			out.append("%s · %s 00, Year 0000" % [se, m])
	return out


# ================================================================ event feed
## Announcements sit in the left column, between the menu buttons and the minimap.
## Newest at the bottom; old lines fade out or drop off the top when the box is full.
var feed_box: PanelContainer


func _build_feed() -> void:
	feed_box = PanelContainer.new()
	feed_box.anchor_top = 0.0
	feed_box.anchor_bottom = 1.0
	feed_box.offset_left = 8
	feed_box.offset_right = 300
	feed_box.offset_top = 440
	feed_box.offset_bottom = -232
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.05, 0.55)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	feed_box.add_theme_stylebox_override("panel", sb)
	root.add_child(feed_box)
	feed = VBoxContainer.new()
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_theme_constant_override("separation", 3)
	feed_box.add_child(feed)
	feed_box.visible = false


func push_event(text: String, kind: String) -> void:
	var l := _label(text, 14, KIND_COLORS.get(kind, KIND_COLORS["info"]))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 278
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("age", 0.0)
	feed.add_child(l)
	feed_box.visible = true
	_trim_feed()


## Drops the oldest lines until everything fits in the box.
func _trim_feed() -> void:
	var room := feed_box.size.y - 12.0
	if room <= 20.0:
		room = 260.0
	while feed.get_child_count() > 1:
		var total := 0.0
		for n in feed.get_children():
			if not n.is_queued_for_deletion():
				total += (n as Control).get_combined_minimum_size().y + 3.0
		if total <= room and feed.get_child_count() <= 14:
			break
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()


# ================================================================ toolbar + side panel
func _build_toolbar() -> void:
	var tb := PanelContainer.new()
	tb.position = Vector2(8, 50)
	root.add_child(tb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	tb.add_child(v)
	v.add_child(_button("Build  [B]", toggle_build_window, 112))
	v.add_child(_button("Jobs  [J]", toggle_panel.bind("jobs"), 112))
	v.add_child(_button("Research  [R]", toggle_panel.bind("research"), 112))
	v.add_child(_button("Stockpile  [I]", toggle_panel.bind("stock"), 112))
	v.add_child(_button("Colony  [C]", toggle_panel.bind("colony"), 112))
	v.add_child(_button("Clear Land [X]", func(): game.set_tool("" if game.tool_mode == "clear" else "clear"), 112))
	v.add_child(_button("Plan Town [Z]", toggle_planner, 112))
	v.add_child(_button("Milestones [G]", toggle_panel.bind("milestones"), 112))
	v.add_child(_button("World Map [M]", toggle_worldmap, 112))
	v.add_child(_button("Help  [H]", toggle_panel.bind("help"), 112))
	v.add_child(_button("Menu  [Esc]", toggle_pause_menu, 112))


func _build_side_panel() -> void:
	side_panel = PanelContainer.new()
	side_panel.position = Vector2(136, 50)
	side_panel.custom_minimum_size = Vector2(390, 0)
	side_panel.visible = false
	root.add_child(side_panel)
	var v := VBoxContainer.new()
	side_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	side_title = _label("", 17, Color(1.0, 0.85, 0.5))
	side_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(side_title)
	head.add_child(_button("x", close_panel, 28))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	side_body = VBoxContainer.new()
	side_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_body.add_theme_constant_override("separation", 6)
	scroll.add_child(side_body)


func toggle_panel(which: String) -> void:
	if which == "research":
		toggle_research()
		return
	if which == "build":
		toggle_build_window()
		return
	if build_layer.visible:
		build_layer.visible = false
	if research_layer.visible:
		research_layer.visible = false
	if current_panel == which and side_panel.visible:
		close_panel()
		return
	current_panel = which
	side_panel.visible = true
	feed.visible = false
	_rebuild_panel()


func close_panel() -> void:
	research_layer.visible = false
	build_layer.visible = false
	settings_layer.visible = false
	side_panel.visible = false
	current_panel = ""
	feed.visible = true


func is_panel_open() -> bool:
	return side_panel.visible or research_layer.visible or build_layer.visible or settings_layer.visible


func _clear_body() -> void:
	for c in side_body.get_children():
		side_body.remove_child(c)
		c.queue_free()
	build_buttons.clear()
	job_status_labels.clear()


func _rebuild_panel() -> void:
	_clear_body()
	match current_panel:
		"build":
			_panel_build()
		"jobs":
			_panel_jobs()
		"stock":
			_panel_stock()
		"colony":
			_panel_colony()
		"help":
			_panel_help()
		"milestones":
			_panel_milestones()


func _panel_build() -> void:
	side_title.text = "Build"
	side_body.add_child(_label("Pick a structure and left-click the map to place its blueprint.\nIt costs nothing up front: your people carry the materials there\nand build it. Right-click or Esc cancels. Shift keeps placing.", 12, Color(0.8, 0.78, 0.7)))
	for type in Defs.BUILD_ORDER:
		var d: Dictionary = Defs.BUILDINGS[type]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		var unlocked: bool = game.sim.colony.is_unlocked(type)
		var b := _button("%s   (%dx%d)" % [d["name"], d["size"].x, d["size"].y], _on_build_pick.bind(type))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(b)
		var info := "Cost: " + Defs.cost_text(d["cost"]) + "\n" + str(d["desc"])
		if not unlocked:
			var tech: Dictionary = Defs.TECHS[str(d["tech"])]
			info = "[Locked] Research %s (%s)\n" % [tech["name"], Defs.ERAS[int(tech["era"])]] + info
		box.add_child(_label(info, 12, Color(0.78, 0.76, 0.68) if unlocked else Color(0.55, 0.53, 0.5)))
		side_body.add_child(box)
		build_buttons.append([b, type])
	_refresh_build_buttons()


# ================================================================ research tree
# A full-screen tech tree: eras are columns (left to right), categories are rows. Each tech
# needs the one before it in its row. Knowledge points (KP) come from materials carried to the
# Research Table; 1,000 KP convert into 1 research point (RP), which buys techs.
const CATEGORY_COLORS := {"Food": Color(0.95, 0.75, 0.35), "Construction": Color(0.85, 0.7, 0.5), "Medicine": Color(0.6, 0.95, 0.6),
	"Weapons": Color(1.0, 0.55, 0.45), "Tools": Color(0.65, 0.8, 1.0), "Ships": Color(0.45, 0.85, 0.95),
	"Military": Color(0.9, 0.4, 0.4), "Civics": Color(0.85, 0.65, 1.0)}
const NODE_W := 204.0
const NODE_H := 62.0
const GAP_X := 30.0
const GAP_Y := 18.0
const ROW_LABEL_W := 0.0
const ERA_PAD := 26.0
const TREE_TOP := 40.0
var research_layer: Control
var tree_canvas: Control
var tree_scroll: ScrollContainer
var tree_nodes := {}            # tech id -> Button
var tree_pos := {}              # tech id -> Rect2
var era_rects: Array = []       # [Rect2, era index]
var _tree_sig := ""
var rt_title: Label
var rt_kp: RichTextLabel
var rt_info: RichTextLabel
var rt_convert1: Button
var rt_convert_all: Button
var rt_share: HSlider
var rt_share_label: Label
var rt_advance: Button
var rt_auto_conv: CheckBox
var rt_auto_res: CheckBox
var build_layer: Control
var build_tabs: TabContainer
var _build_sig := ""
var settings_layer: Control


func _build_research_tree() -> void:
	research_layer = PanelContainer.new()
	research_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	research_layer.offset_left = 20
	research_layer.offset_top = 52
	research_layer.offset_right = -20
	research_layer.offset_bottom = -20
	research_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	research_layer.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.065, 0.06, 1.0)
	bg.border_color = Color(0.55, 0.45, 0.28)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(10)
	research_layer.add_theme_stylebox_override("panel", bg)
	root.add_child(research_layer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	research_layer.add_child(v)
	# header
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	rt_title = _label("Research Tree", 20, Color(1.0, 0.85, 0.5))
	h.add_child(rt_title)
	rt_kp = RichTextLabel.new()
	rt_kp.bbcode_enabled = true
	rt_kp.fit_content = true
	rt_kp.scroll_active = false
	rt_kp.custom_minimum_size = Vector2(300, 26)
	rt_kp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rt_kp)
	rt_convert1 = _button("Convert 1,000 KP → 1 RP", _on_convert.bind(1))
	h.add_child(rt_convert1)
	rt_convert_all = _button("Convert all", _on_convert.bind(1000000))
	h.add_child(rt_convert_all)
	h.add_child(VSeparator.new())
	rt_share_label = _label("To research: 25%", 14)
	rt_share_label.custom_minimum_size.x = 132
	h.add_child(rt_share_label)
	rt_share = HSlider.new()
	rt_share.min_value = 0
	rt_share.max_value = 100
	rt_share.step = 5
	rt_share.custom_minimum_size = Vector2(150, 24)
	rt_share.focus_mode = Control.FOCUS_NONE
	rt_share.tooltip_text = "Share of every material your people bring into the stockpile that is set aside\nfor research. Researchers carry it from the stockpile to the Research Table."
	rt_share.value_changed.connect(_on_share_changed)
	h.add_child(rt_share)
	h.add_child(VSeparator.new())
	rt_advance = _button("Advance Era", _on_advance_era)
	h.add_child(rt_advance)
	rt_auto_conv = CheckBox.new()
	rt_auto_conv.text = "Auto-convert"
	rt_auto_conv.tooltip_text = "Researchers turn every 1,000 KP into a research point on their own."
	rt_auto_conv.focus_mode = Control.FOCUS_NONE
	rt_auto_conv.toggled.connect(func(on): game.sim.colony.auto_convert = on)
	h.add_child(rt_auto_conv)
	rt_auto_res = CheckBox.new()
	rt_auto_res.text = "Auto-research"
	rt_auto_res.tooltip_text = "Researchers spend research points on the cheapest tech they can unlock."
	rt_auto_res.focus_mode = Control.FOCUS_NONE
	rt_auto_res.toggled.connect(func(on): game.sim.colony.auto_research = on)
	h.add_child(rt_auto_res)
	h.add_child(_button("Close  [R]", close_panel, 90))
	rt_info = RichTextLabel.new()
	rt_info.bbcode_enabled = true
	rt_info.fit_content = true
	rt_info.scroll_active = false
	rt_info.custom_minimum_size = Vector2(600, 20)
	v.add_child(rt_info)
	# the tree itself, with the category names pinned on the left
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	v.add_child(body)
	var labels := Control.new()
	labels.custom_minimum_size = Vector2(118, 0)
	labels.draw.connect(_draw_tree_rows.bind(labels))
	body.add_child(labels)
	tree_scroll = ScrollContainer.new()
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tree_scroll)
	tree_canvas = Control.new()
	tree_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	tree_canvas.draw.connect(_draw_tree)
	tree_scroll.add_child(tree_canvas)
	_layout_tree()


## Places every tech: x by era and step along its category chain, y by category.
func _layout_tree() -> void:
	tree_pos.clear()
	era_rects.clear()
	var x := ROW_LABEL_W
	var rows := Defs.TECH_CATEGORIES.size()
	var height := TREE_TOP + rows * (NODE_H + GAP_Y) + 10.0
	for e in Defs.ERAS.size():
		var steps := 0
		for id in Defs.techs_of_era(e):
			steps = maxi(steps, Defs.tech_step(id) + 1)
		var w := ERA_PAD * 2.0 + steps * NODE_W + maxi(0, steps - 1) * GAP_X
		era_rects.append([Rect2(x, 0, w, height), e])
		for id in Defs.techs_of_era(e):
			var row := Defs.TECH_CATEGORIES.find(str(Defs.TECHS[id]["kind"]))
			var px := x + ERA_PAD + Defs.tech_step(id) * (NODE_W + GAP_X)
			var py := TREE_TOP + row * (NODE_H + GAP_Y)
			tree_pos[id] = Rect2(px, py, NODE_W, NODE_H)
		x += w + 8.0
	tree_canvas.custom_minimum_size = Vector2(x + 10.0, height)


func toggle_research() -> void:
	if research_layer.visible:
		close_panel()
		return
	side_panel.visible = false
	current_panel = ""
	feed.visible = false
	research_layer.visible = true
	_tree_sig = ""
	_refresh_research()
	# scroll so the current era is in view
	var c: Colony = game.sim.colony
	if c.era_i < era_rects.size():
		var r: Rect2 = era_rects[c.era_i][0]
		tree_scroll.set_deferred("scroll_horizontal", int(maxf(0.0, r.position.x - ROW_LABEL_W)))


func _tree_signature() -> String:
	var c: Colony = game.sim.colony
	var sig := "%d|%d|" % [c.era_i, c.researched.size()]
	for id in Defs.techs_of_era(c.era_i):
		sig += "1" if c.can_afford_tech(id) else "0"
	return sig


func _refresh_research() -> void:
	var c: Colony = game.sim.colony
	rt_title.text = "Research Tree — %s" % c.era
	rt_kp.text = "[b]Knowledge:[/b] [color=#ffd27a]%s KP[/color]     [b]Research points:[/b] [color=#9fd8ff]%d RP[/color]" % [_fmt_int(c.knowledge), int(c.research_points)]
	var can_conv := c.knowledge >= Defs.kp_per_rp()
	rt_convert1.disabled = not can_conv
	rt_convert_all.disabled = not can_conv
	if absf(rt_share.value - c.research_share * 100.0) > 0.5:
		rt_share.set_value_no_signal(c.research_share * 100.0)
	rt_share_label.text = "To research: %d%%" % roundi(c.research_share * 100.0)
	rt_auto_conv.set_pressed_no_signal(c.auto_convert)
	rt_auto_res.set_pressed_no_signal(c.auto_research)
	if c.era_i < Defs.ERAS.size() - 1:
		rt_advance.visible = true
		rt_advance.disabled = not c.can_advance_era()
		var acost := c.era_advance_cost()
		if c.can_advance_era():
			rt_advance.text = "Advance to the %s (%s RP)" % [Defs.ERAS[c.era_i + 1], _fmt_int(acost)]
		elif not c.era_complete():
			rt_advance.text = "Next age: research all, then %s RP" % _fmt_int(acost)
		else:
			rt_advance.text = "Next age: %s / %s RP" % [_fmt_int(c.research_points), _fmt_int(acost)]
		rt_advance.tooltip_text = "To enter the %s: research every tech of the %s, then spend %s RP (double the RP of all this age's techs)." % [
			Defs.ERAS[c.era_i + 1], c.era, _fmt_int(acost)]
	else:
		rt_advance.visible = false
	# info line
	var tables := c.count_type("research_table")
	var researchers := 0
	for p in c.living():
		if p.job == "researcher":
			researchers += 1
	var info := ""
	if tables == 0:
		info = "[color=#ffd27a]Build a Research Table first. Then %d%% of every material brought into the stockpile is set aside, and Researchers carry it to the table for knowledge.[/color]" % roundi(c.research_share * 100.0)
	else:
		var parts := PackedStringArray()
		for k in c.research_stock.keys():
			if float(c.research_stock[k]) >= 1.0:
				parts.append("%d %s" % [int(c.research_stock[k]), Defs.item_name(k).to_lower()])
		info = "Research pile: %s  (≈%s KP)" % [", ".join(parts) if not parts.is_empty() else "empty", _fmt_int(c.research_pile_kp())]
		info += "     [color=#a9a39a]KP per unit: grass 20 · sticks 30 · wood/stone 60 · bones/hides 150 · copper 400 · tin 450 · iron 600[/color]"
		if researchers == 0:
			info += "\n[color=#ffd27a]No one has the Researcher job — assign one in Jobs, or the pile just sits there.[/color]"
	rt_info.text = info
	var sig := _tree_signature()
	if sig != _tree_sig:
		_tree_sig = sig
		_rebuild_tree_nodes()


func _fmt_int(v: float) -> String:
	var n := int(v)
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _node_style(bg: Color, border: Color, stripe: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.border_width_left = 6
	st.set_corner_radius_all(5)
	st.content_margin_left = 10
	st.content_margin_right = 6
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	st.shadow_color = Color(0, 0, 0, 0.4)
	st.shadow_size = 3
	if stripe.a > 0.0:
		st.border_color = border
	return st


func _rebuild_tree_nodes() -> void:
	var c: Colony = game.sim.colony
	for id in tree_nodes.keys():
		var old: Button = tree_nodes[id]
		old.queue_free()
	tree_nodes.clear()
	for id in Defs.TECH_ORDER:
		var t: Dictionary = Defs.TECHS[id]
		var r: Rect2 = tree_pos[id]
		var cat_col: Color = CATEGORY_COLORS.get(str(t["kind"]), Color.WHITE)
		var b := Button.new()
		b.position = r.position
		b.size = r.size
		b.custom_minimum_size = r.size
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		var cost := "%d RP" % Defs.tech_rp(id)
		var mats := Defs.tech_materials(id)
		for k in mats.keys():
			cost += " · %d %s" % [int(mats[k]), Defs.item_name(k)]
		var done: bool = c.researched.has(id)
		var avail := c.tech_available(id)
		var afford := avail and c.can_afford_tech(id)
		var state := ""
		var bg := Color(0.13, 0.12, 0.11)
		var border := Color(0.25, 0.24, 0.22)
		var fg := Color(0.5, 0.48, 0.45)
		if done:
			state = "✓ Researched"
			bg = Color(0.16, 0.30, 0.17)
			border = Color(0.45, 0.85, 0.45)
			fg = Color(0.85, 1.0, 0.85)
		elif afford:
			state = "Click to research"
			bg = Color(0.36, 0.27, 0.10)
			border = Color(1.0, 0.82, 0.35)
			fg = Color(1.0, 0.95, 0.8)
		elif avail:
			state = "Need " + cost
			bg = Color(0.21, 0.19, 0.16)
			border = cat_col.darkened(0.2)
			fg = Color(0.92, 0.88, 0.8)
		elif int(t["era"]) == c.era_i:
			state = "Needs " + str(Defs.TECHS[Defs.tech_prereq(id)]["name"])
			border = cat_col.darkened(0.55)
			fg = Color(0.65, 0.62, 0.58)
		else:
			state = Defs.ERAS[int(t["era"])]
		b.text = "%s\n%s\n%s" % [t["name"], cost, state]
		var st := _node_style(bg, border, cat_col)
		st.border_color = border
		# left stripe in the category colour
		var st2 := st.duplicate() as StyleBoxFlat
		st2.bg_color = bg.lightened(0.08)
		for sname in ["normal", "disabled"]:
			b.add_theme_stylebox_override(sname, st)
		b.add_theme_stylebox_override("hover", st2)
		b.add_theme_stylebox_override("pressed", st2)
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_disabled_color", fg)
		b.add_theme_color_override("font_hover_color", fg.lightened(0.1))
		var fx_txt := PackedStringArray()
		for u in t.get("unlocks", []):
			fx_txt.append("Unlocks: " + str(Defs.BUILDINGS[u]["name"]))
		b.tooltip_text = "%s  (%s · %s)\n%s\nCost: %s%s" % [t["name"], t["kind"], Defs.ERAS[int(t["era"])], t["desc"], cost,
			("\n" + "\n".join(fx_txt)) if not fx_txt.is_empty() else ""]
		b.disabled = not afford
		b.pressed.connect(_on_research.bind(id))
		tree_canvas.add_child(b)
		tree_nodes[id] = b
	tree_canvas.queue_redraw()


func _draw_tree() -> void:
	var c: Colony = game.sim.colony
	var font := ThemeDB.fallback_font
	# era columns
	for er in era_rects:
		var r: Rect2 = er[0]
		var e: int = er[1]
		var col := Color(0.16, 0.14, 0.11) if e == c.era_i else (Color(0.11, 0.105, 0.1) if e > c.era_i else Color(0.10, 0.13, 0.10))
		tree_canvas.draw_rect(r, col)
		tree_canvas.draw_rect(r, Color(0.55, 0.45, 0.28) if e == c.era_i else Color(0.25, 0.23, 0.2), false, 1.0)
		var title: String = Defs.ERAS[e] + ("  (current)" if e == c.era_i else ("  ✓" if e < c.era_i else ""))
		tree_canvas.draw_string(font, r.position + Vector2(12, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(1.0, 0.85, 0.5) if e == c.era_i else Color(0.6, 0.58, 0.54))
	# links: prerequisite -> tech
	for id in Defs.TECH_ORDER:
		var pre := Defs.tech_prereq(id)
		if pre == "":
			continue
		var a: Rect2 = tree_pos[pre]
		var b: Rect2 = tree_pos[id]
		var p1 := Vector2(a.end.x, a.get_center().y)
		var p2 := Vector2(b.position.x, b.get_center().y)
		var col := Color(0.45, 0.85, 0.45, 0.9) if c.researched.has(pre) else Color(0.45, 0.42, 0.38, 0.8)
		var mid := (p1.x + p2.x) * 0.5
		tree_canvas.draw_polyline(PackedVector2Array([p1, Vector2(mid, p1.y), Vector2(mid, p2.y), p2]), col, 2.0)
		tree_canvas.draw_colored_polygon(PackedVector2Array([p2, p2 + Vector2(-7, -4), p2 + Vector2(-7, 4)]), col)


func _draw_tree_rows(ctl: Control) -> void:
	var font := ThemeDB.fallback_font
	for i in Defs.TECH_CATEGORIES.size():
		var cat: String = Defs.TECH_CATEGORIES[i]
		var col: Color = CATEGORY_COLORS.get(cat, Color.WHITE)
		var y := TREE_TOP + i * (NODE_H + GAP_Y)
		ctl.draw_rect(Rect2(4, y + 6, 4, NODE_H - 12), col)
		ctl.draw_string(font, Vector2(14, y + NODE_H * 0.5 + 6), cat, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


func _on_convert(n: int) -> void:
	var made: int = game.sim.colony.convert_knowledge(n)
	if made > 0:
		push_event("Turned %s KP into %d research point%s." % [_fmt_int(made * Defs.kp_per_rp()), made, "" if made == 1 else "s"], "good")
	_refresh_research()


func _on_share_changed(v: float) -> void:
	game.sim.colony.research_share = v / 100.0
	rt_share_label.text = "To research: %d%%" % roundi(v)


func _on_research(id: String) -> void:
	if game.sim.colony.research(id):
		push_event("Researched %s!" % Defs.TECHS[id]["name"], "good")
		game.sim.emit_signal("buildings_changed")
	_tree_sig = ""
	_refresh_research()


func _on_advance_era() -> void:
	if game.sim.colony.advance_era():
		push_event("Your tribe has entered the %s! New research and buildings are available." % game.sim.colony.era, "good")
		game.sim.emit_signal("buildings_changed")
		_tree_sig = ""
		_refresh_research()
		var r: Rect2 = era_rects[game.sim.colony.era_i][0]
		tree_scroll.scroll_horizontal = int(maxf(0.0, r.position.x - ROW_LABEL_W))


func _on_build_pick(type: String) -> void:
	game.start_build(type)


func _refresh_build_buttons() -> void:
	for e in build_buttons:
		var b: Button = e[0]
		var d: Dictionary = Defs.BUILDINGS[e[1]]
		b.disabled = not game.sim.colony.is_unlocked(e[1])


func _panel_jobs() -> void:
	side_title.text = "Jobs & Work Priorities"
	var sim: Sim = game.sim
	jobs_pop = sim.colony.population()
	var aj := CheckButton.new()
	aj.text = "Tribe AI assigns jobs automatically"
	aj.button_pressed = sim.colony.auto_jobs
	aj.focus_mode = Control.FOCUS_NONE
	aj.toggled.connect(_on_auto_jobs)
	side_body.add_child(aj)
	var ab := CheckButton.new()
	ab.text = "Tribe AI plans and places buildings"
	ab.button_pressed = sim.colony.auto_build
	ab.focus_mode = Control.FOCUS_NONE
	ab.toggled.connect(_on_auto_build)
	side_body.add_child(ab)
	var ae := CheckButton.new()
	ae.text = "Tribe AI claims free land nearby"
	ae.button_pressed = sim.colony.auto_expand
	ae.focus_mode = Control.FOCUS_NONE
	ae.toggled.connect(func(on): game.sim.colony.auto_expand = on)
	side_body.add_child(ae)
	if sim.colony.auto_jobs:
		side_body.add_child(_label("Jobs are managed by the tribe AI. Switch it off to assign them yourself.", 12, Color(0.8, 0.78, 0.7)))
	else:
		side_body.add_child(_label("Each person does their own job. When it has no work, they help\nwith other jobs in order of tribe priority (5 = most important).", 12, Color(0.8, 0.78, 0.7)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	side_body.add_child(grid)
	for j in Defs.JOBS:
		var jl2 := _label(Defs.JOB_NAMES[j] + ("" if sim.colony.job_allowed(j) else " ✕"), 13, Color(0.93, 0.9, 0.82) if sim.colony.job_allowed(j) else Color(0.6, 0.58, 0.54))
		if not sim.colony.job_allowed(j):
			jl2.tooltip_text = "Needs a Training Camp or Mercenary Hall" if j == "soldier" else "Needs a %s" % Defs.BUILDINGS[Defs.JOB_NEEDS[j]]["name"]
			jl2.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(jl2)
		var sb := SpinBox.new()
		sb.min_value = 1
		sb.max_value = 5
		sb.value = int(sim.colony.job_priority.get(j, 3))
		sb.custom_minimum_size.x = 70
		sb.value_changed.connect(_on_prio_changed.bind(j))
		grid.add_child(sb)
	side_body.add_child(HSeparator.new())
	for p in sim.colony.living():
		var row := HBoxContainer.new()
		var nm := _label("%s (%s, %d)" % [p.name, p.gender, int(p.age_years())], 13)
		nm.custom_minimum_size.x = 130
		nm.clip_text = true
		row.add_child(nm)
		if p.can_work() and not sim.colony.auto_jobs:
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size.x = 140
			for k in Defs.JOBS.size():
				ob.add_item(Defs.JOB_NAMES[Defs.JOBS[k]], k)
			ob.select(maxi(0, Defs.JOBS.find(p.job)))
			ob.item_selected.connect(_on_job_selected.bind(p.id))
			row.add_child(ob)
		elif p.can_work():
			var jl := _label(Defs.JOB_NAMES.get(p.job, p.job), 13, Color(1.0, 0.85, 0.5))
			jl.custom_minimum_size.x = 140
			row.add_child(jl)
			job_status_labels[-p.id] = jl
		else:
			var young := _label("Too young to work", 12, Color(0.7, 0.7, 0.65))
			young.custom_minimum_size.x = 140
			row.add_child(young)
		var st := _label(p.state, 11, Color(0.75, 0.75, 0.7))
		st.clip_text = true
		st.custom_minimum_size.x = 90
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st)
		job_status_labels[p.id] = st
		side_body.add_child(row)


func _on_auto_jobs(on: bool) -> void:
	game.sim.colony.auto_jobs = on
	_rebuild_panel()


func _on_auto_build(on: bool) -> void:
	game.sim.colony.auto_build = on
	if not on:
		game.sim.colony.want_build = ""


func _on_prio_changed(value: float, job: String) -> void:
	game.sim.colony.job_priority[job] = int(value)


func _on_job_selected(index: int, pid: int) -> void:
	var p: Human = game.sim.colony.person(pid)
	var job: String = Defs.JOBS[index]
	if not game.sim.colony.job_allowed(job):
		var need := "Training Camp or Mercenary Hall" if job == "soldier" else str(Defs.BUILDINGS[Defs.JOB_NEEDS[job]]["name"])
		push_event("%s needs a %s first." % [Defs.JOB_NAMES[job], need], "warn")
		_rebuild_panel()
		return
	if p != null:
		if job == "soldier" and p.job != "soldier":
			p.soldier_kind = Military.balanced_kind(game.sim.colony)
		p.drafted = job == "soldier"
		p.job = job
		p.task = {}
		p.path = []
		game.sim.release_claims(p.id)


func _panel_stock() -> void:
	side_title.text = "Stockpile"
	var c: Colony = game.sim.colony
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size.x = 370
	var s := "[b]Storage[/b]  %d / %d   ·   Water %d / %d\n\n" % [int(c.material_total()), int(c.storage_capacity()), int(c.count("water")), int(c.water_capacity())]
	s += "[b]Food[/b]  (%.1f days for %d people)\n" % [c.food_days(), c.population()]
	for f in Defs.EAT_ORDER:
		if c.count(f) >= 0.5:
			s += "   %s: %d   [color=#a09a88](spoils %d%%/day)[/color]\n" % [Defs.item_name(f), int(c.count(f)), int(float(Defs.FOOD[f]["spoil"]) * 100.0)]
	s += "\n[b]Materials[/b]\n"
	for m in Defs.MATERIALS:
		if c.count(m) >= 0.5:
			s += "   %s: %d\n" % [Defs.item_name(m), int(c.count(m))]
	if c.weapons_in_stock() > 0:
		s += "\n[b]Weapons[/b]\n"
		for w in Defs.WEAPON_ORDER:
			if c.count(w) >= 0.5:
				s += "   %s: %d\n" % [Defs.item_name(w), int(c.count(w))]
	t.text = s
	side_body.add_child(t)


func _panel_colony() -> void:
	var sim: Sim = game.sim
	var c := sim.colony
	side_title.text = c.name
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size.x = 370
	t.meta_clicked.connect(_on_person_link)
	var s := "[url=rename_tribe][color=#ffd27a]Rename tribe[/color][/url]\n[b]Era:[/b] %s   [b]Race:[/b] %s\n" % [c.era, Config.race_name(c.race)]
	if c.government != "":
		s += "[b]Government:[/b] %s%s\n" % [Defs.GOVERNMENTS[c.government]["name"], " (Capitol: bonuses +50%)" if c.has_built("capitol") else ""]
	s += _leader_text(sim, c, true)
	s += _election_text(sim, c)
	var foes := sim.enemies_of(0)
	if not foes.is_empty():
		s += "[color=#ff8a7a][b]At war with:[/b] %s[/color]\n" % ", ".join(PackedStringArray(foes.map(func(e): return e.name)))
	var passes := PackedStringArray()
	for oc in sim.colonies:
		if oc.civ_id != 0 and not oc.collapsed and Borders.access_years_left(sim, 0, oc.civ_id) > 0.0:
			passes.append("%s (%d yrs)" % [oc.name, ceili(Borders.access_years_left(sim, 0, oc.civ_id))])
	if not passes.is_empty():
		s += "[b]Passage through:[/b] %s\n" % ", ".join(passes)
	s += "[b]Soldiers:[/b] %d   [b]Strength:[/b] %d\n" % [c.soldiers().size(), int(sim.military_strength(c))]
	var mine := sim.states.owned_by(0)
	s += "[b]Territory:[/b] %d / %d states — %s\n" % [mine.size(), sim.state_limit(c), ", ".join(PackedStringArray(mine.map(func(x): return sim.states.names[x])))]
	if c.cheat:
		s += "[color=#ff9f4a]Cheats are on.[/color]\n"
	s += "[b]Population:[/b] %d   (housing for %d)\n" % [c.population(), c.housing()]
	s += "[b]Births:[/b] %d   [b]Deaths:[/b] %d\n" % [c.births, c.deaths]
	s += "[b]Average health:[/b] %d%%   [b]Sick:[/b] %d\n" % [int(c.health_pct()), c.sick_count()]
	s += "[b]Food:[/b] %.1f days   [b]Days survived:[/b] %d\n" % [c.food_days(), sim.time.day()]
	s += "[b]Bank:[/b] [color=#f3d9b0]%d %s[/color]   [b]Knowledge:[/b] %d KP · %d RP\n" % [int(c.money), Defs.MONEY_NAME, int(c.knowledge), int(c.research_points)]
	if not c.trade_log.is_empty():
		s += "[b]Recent trades[/b]\n"
		for i in range(maxi(0, c.trade_log.size() - 5), c.trade_log.size()):
			s += "  [color=#cfc6b4]%s[/color]\n" % c.trade_log[i]
	else:
		s += "[color=#a09a88]Give someone the Trader job to sell surplus to other tribes for %s.[/color]\n" % Defs.MONEY_NAME
	s += "\n"
	s += "[b]People[/b] (click to focus)\n"
	for p in c.living():
		var flags := ""
		if p.is_sick():
			flags += " [color=#ff8a7a](%s)[/color]" % Defs.ILLNESS[p.illness["type"]]["name"]
		if p.pregnant_days >= 0.0:
			flags += " [color=#9fe08a](expecting)[/color]"
		if p.id == c.leader_id:
			flags += " [color=#ffd27a](%s)[/color]" % c.leader_title
		s += "  [url=%d]%s[/url] — %s %d, %s · HP %d%s\n" % [p.id, p.name, p.stage(), int(p.age_years()), Defs.JOB_NAMES.get(p.job, "Child"), int(p.health), flags]
	var dead: Array = []
	for p in c.people:
		if not p.alive:
			dead.append(p)
	if not dead.is_empty():
		s += "\n[b]Remembered[/b]\n"
		for p in dead:
			s += "  [color=#a09a88]%s, %d — %s[/color]\n" % [p.name, int(p.age_years()), p.cause]
	s += "\n[b]Other tribes[/b]\n"
	var unknown := 0
	for oc in sim.colonies:
		if oc.civ_id == 0:
			continue
		if not sim.have_met(0, oc.civ_id) and not game.reveal_all:
			unknown += 1
			continue
		var hexc: String = oc.color.to_html(false)
		if oc.collapsed:
			s += "  [color=#%s]%s[/color] — [color=#a09a88]perished[/color]\n" % [hexc, oc.name]
			continue
		var rel := sim.relation(0, oc.civ_id)
		var rel_txt := "%s (%d)" % [Sim.relation_label(rel), int(rel)] if sim.have_met(0, oc.civ_id) else "not met yet"
		s += "  [url=civ:%d][color=#%s]%s[/color][/url] — pop %d, %d buildings, %s · %d %s · %s\n" % [oc.civ_id, hexc, oc.name, oc.population(), oc.buildings.size(), oc.era, int(oc.money), Defs.MONEY_NAME, rel_txt]
	if unknown > 0:
		s += "  [color=#a09a88]%d tribe(s) not yet discovered. Explore to meet them.[/color]\n" % unknown

	t.text = s
	side_body.add_child(t)


func _on_person_link(meta: Variant) -> void:
	var m := str(meta)
	if m == "rename_tribe":
		_start_rename("tribe")
	elif m == "reveal":
		game.reveal_all = not game.reveal_all
		_rebuild_panel()
	elif m.begins_with("back:") or m.begins_with("rally:") or m.begins_with("gift:") or m == "rig" or m == "unrig":
		_on_election_link(m)
	elif m.begins_with("civ:"):
		var oc: Colony = game.sim.civ(int(m.substr(4)))
		game.camera.position = game.sim.world.center_of(oc.home)
		game.clear_selection()
		game.selected_civ_id = oc.civ_id
	else:
		game.select_human(int(m), true)


func _panel_help() -> void:
	side_title.text = "How to Play"
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.custom_minimum_size.x = 370
	t.text = """[b]Goal[/b]
Keep your tribe alive and growing. Everyone needs food, fresh water, sleep and warmth.

[b]Camera[/b]
WASD / arrows to pan (Shift = faster), mouse wheel to zoom, middle-drag to pan.
Click the minimap to jump.

[b]Commanding your people[/b]
Left-click a person to select them, or hold the left button and drag a box to select several (Shift adds to the selection).
Right-click: walk there. Shift + right-click on an animal or a person from another tribe: attack it.
Right-click a ship with people selected: they board it.

[b]Ships[/b]
Research Boatbuilding (Ships, Stone Age), build a Harbor on the coast and order a ship from it. Select the ship and right-click water to sail, or right-click a far shore to land everyone there.

[b]Building[/b]
Placing a building only lays down a blueprint. Your people fetch the materials from storage and build it — gatherers collect anything that's missing.

[b]Time[/b]
Space pauses, 1-6 set speed 1x / 2x / 4x / 8x / 16x / 32x.

[b]Your tribe runs itself[/b]
The tribe AI assigns jobs and plans buildings on its own. You can still place buildings yourself (Build), and you can switch the AI off in the Jobs panel to manage everyone by hand.

[b]Other tribes[/b]
Rival tribes live elsewhere in the world and are controlled by their own AI. Explore to meet them — the Colony panel lists every tribe you know.

[b]Research & eras[/b]
Build a Research Table. A share of every material brought into the stockpile (slider in the Research Tree, R) is set aside for research, and Researchers carry it from the stockpile to the table — never straight from the wild. Each unit gives knowledge points (KP); rarer materials give more (grass 20, sticks 30, wood/stone 60, bones/hides 150, copper 400, tin 450, iron 600).
Convert 1,000 KP into 1 research point (RP) and spend RP in the tree. Each tech needs the one before it in its row, costs rise along each row and jump with every era. Finish every tech of an era to advance: Caveman → Stone → Bronze → Iron Age.

[b]Time & ages[/b]
The calendar runs 5x faster than daily life. To reach the next age, research everything in your age, then pay double the RP of all that age's techs. A Monolith (Standing Stones) skips years for 1,000 KP each.

[b]Leaders & elections[/b]
Every few years the adults elect a Chief (Caveman and Stone Age). From the Bronze Age they elect a President, at most two terms in a row. A leader's best trade makes the whole tribe better at it.

[b]Plan Town (Z)[/b]
Paint Farming, Housing and Workshop zones and lay out roads. Buildings standing in the zone that suits them get bonuses (farms +25%, homes +1 bed and better sleep, workshops and research 20% faster). Billies walk about twice as fast on roads; laborers and builders build them.

[b]Milestones (G)[/b]
27 goals, from your first fire to a realm of many lands. Each pays Talents, knowledge or research points.

[b]Soldiers[/b]
Warriors fight up close, Archers from range. Train them from your own people at a Training Camp or Mercenary Hall, or hire armed newcomers for Talents at a Mercenary Hall (research Mercenary Pacts, Stone Age).

[b]Deals[/b]
Rivals send envoys with trades, alliances, tribute demands and land demands: accept, decline or counter-offer. From a rival's flag you can propose an alliance, ask for a trade, or demand tribute or land. Allies defend each other.

[b]Elections[/b]
In the Colony panel, click a candidate to back them, then hold rallies (Talents), hand out gifts (food) or rig the count — if it's discovered, the tribe falls into unrest for 3 years.

[b]Borders[/b]
Billies need permission to cross another tribe's land. Rivals ask you before crossing yours; you can ask them from their flag. A Billy caught on foreign land without permission can start a war: 30% in the Caveman Age, +10% for each later age.

[b]Territory[/b]
The land is split into states. Claim free neighbouring states by sending someone to their centre (World Map → Territory view → click a state). Taking another tribe's state requires war.

[b]Clear land[/b]
Press X (or Clear Land) and drag a box over trees, bushes, stones or animals. Your people cut it all down and carry it home. Shift+drag removes marks.

[b]Military & war[/b]
Stone Age: research Weaponsmithing (Blacksmith forges weapons), Warrior Training (Training Camp, lets you make Soldiers) and Defensive Perimeters (walls and gates go up around the village).
Bronze Age: choose a government, build a Capitol and a Map Table. Click a rival's flag to declare war, send soldiers to attack, offer peace or send gifts.

[b]Talents & trade[/b]
Every tribe has its own bank of Talents. Give someone the Trader job: they pack your surplus, walk to another tribe (or sail from your Harbor to one overseas), sell it and buy back ores or food you need.

[b]Illness[/b]
Colds, flu, fever, dysentery, typhoid, measles, malaria, pneumonia, tetanus, rabies, tuberculosis and plague. Each sick person shows their chance of dying within a week, month or year. Children and elders are most at risk; healers, a Healer's Hut, medicine research and rest lower it.

[b]Calendar[/b]
Years have 365 days and each season lasts three months. Winter is long — store food, dry meat and keep fires going.

[b]Good first buildings[/b]
A [b]Campfire[/b] near fresh water, then a [b]Primitive Shelter[/b] so children can be raised, a [b]Storage Area[/b] to slow spoilage and a [b]Drying Rack[/b] to preserve meat for winter.

[b]Survival tips[/b]
Lake water can carry disease; rivers and springs are safer.
Raw meat and fish can cause food poisoning — cook it!
Healers treat illness and injuries. Wolves and bears are dangerous, especially at night.
Couples have children when there is food and shelter. Children help from age 6."""
	side_body.add_child(t)


# ================================================================ info panel
func _build_info_panel() -> void:
	info_panel = PanelContainer.new()
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info_panel.custom_minimum_size = Vector2(330, 0)
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_panel.offset_right = -8
	info_panel.offset_bottom = -8
	info_panel.offset_left = -338
	info_panel.offset_top = -8
	root.add_child(info_panel)
	var v := VBoxContainer.new()
	info_panel.add_child(v)
	info_text = RichTextLabel.new()
	info_text.bbcode_enabled = true
	info_text.fit_content = true
	info_text.scroll_active = false
	info_text.custom_minimum_size.x = 314
	v.add_child(info_text)
	info_bars = VBoxContainer.new()
	info_bars.add_theme_constant_override("separation", 2)
	v.add_child(info_bars)
	for k in ["Health", "Food", "Water", "Energy", "Warmth"]:
		var row := HBoxContainer.new()
		var l := _label(k, 12)
		l.custom_minimum_size.x = 60
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(240, 12)
		pb.show_percentage = false
		pb.max_value = 100
		var fill := StyleBoxFlat.new()
		fill.bg_color = {"Health": Color(0.85, 0.25, 0.3), "Food": Color(0.85, 0.6, 0.2), "Water": Color(0.3, 0.6, 0.95),
			"Energy": Color(0.6, 0.85, 0.35), "Warmth": Color(0.95, 0.45, 0.2)}[k]
		fill.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("fill", fill)
		row.add_child(pb)
		info_bars.add_child(row)
		bar_nodes[k] = pb
	demolish_btn = _button("Demolish (refund 50%)", _on_demolish)
	demolish_btn.visible = false
	info_actions = HFlowContainer.new()
	info_actions.add_theme_constant_override("separation", 4)
	v.add_child(info_actions)


## Rebuilds the action buttons under the info text only when the selection changes.
func _set_actions(sig: String, acts: Array) -> void:
	if sig == _actions_sig:
		return
	_actions_sig = sig
	for c in info_actions.get_children():
		info_actions.remove_child(c)
		c.queue_free()
	for a in acts:
		var b := _button(a[0], a[1])
		b.add_theme_font_size_override("font_size", 12)
		info_actions.add_child(b)


func _on_build_ship(bid: int, kind: int) -> void:
	var b: Building = game.sim.building(bid)
	if b == null:
		return
	var err: String = game.sim.order_ship(game.sim.colony, b, kind)
	if err != "":
		push_event(err, "warn")
	else:
		push_event("The harbor has started building a %s." % Defs.SHIP_TYPES[kind]["name"], "info")
	_actions_sig = ""


func _on_unload(sid: int) -> void:
	var sh: Ship = game.sim.ship(sid)
	if sh != null:
		game.sim.unload_now(sh)
	_actions_sig = ""


# ---------------------------------------------------------------- renaming
func _build_rename_dialog() -> void:
	rename_layer = ColorRect.new()
	(rename_layer as ColorRect).color = Color(0, 0, 0, 0.45)
	rename_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rename_layer.visible = false
	root.add_child(rename_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rename_layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(360, 0)
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	rename_title = _label("Rename", 17, Color(1.0, 0.85, 0.5))
	v.add_child(rename_title)
	rename_edit = LineEdit.new()
	rename_edit.max_length = 24
	rename_edit.text_submitted.connect(func(_t): _finish_rename(true))
	v.add_child(rename_edit)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(_button("OK", _finish_rename.bind(true), 100))
	h.add_child(_button("Cancel", _finish_rename.bind(false), 100))


func _start_rename(target: String) -> void:
	_rename_target = target
	var sim: Sim = game.sim
	var current := ""
	if target == "tribe":
		current = sim.colony.name
		rename_title.text = "Name your tribe"
	elif target.begins_with("person:"):
		var p := sim.person(int(target.substr(7)))
		current = p.name if p != null else ""
		rename_title.text = "Rename %s" % current
	elif target.begins_with("ship:"):
		var sh := sim.ship(int(target.substr(5)))
		current = sh.name if sh != null else ""
		rename_title.text = "Rename ship"
	rename_edit.text = current
	rename_layer.visible = true
	game.menu_paused = true
	rename_edit.grab_focus()
	rename_edit.select_all()


func _finish_rename(ok: bool) -> void:
	rename_layer.visible = false
	game.menu_paused = pause_layer.visible
	rename_edit.release_focus()
	var name := rename_edit.text.strip_edges()
	if not ok or name.is_empty():
		return
	var sim: Sim = game.sim
	if _rename_target == "tribe":
		sim.colony.name = name
		push_event("Your tribe is now called the %s." % name, "good")
	elif _rename_target.begins_with("person:"):
		var p := sim.person(int(_rename_target.substr(7)))
		if p != null:
			push_event("%s will now be known as %s." % [p.name, name], "info")
			p.name = name
	elif _rename_target.begins_with("ship:"):
		var sh := sim.ship(int(_rename_target.substr(5)))
		if sh != null:
			sh.name = name
	_actions_sig = ""
	if side_panel.visible:
		_rebuild_panel()


func is_typing() -> bool:
	return rename_layer != null and rename_layer.visible


func _on_demolish() -> void:
	game.demolish_selected()


func _refresh_info() -> void:
	var sim: Sim = game.sim
	info_bars.visible = false
	var p: Human = null
	if game.selected_human_id >= 0:
		p = sim.person(game.selected_human_id)
	if p != null and p.alive:
		info_bars.visible = true
		var s := "[b]%s[/b]  [color=#a09a88]%s · %s · age %d[/color]\n" % [p.name, "Male" if p.gender == "M" else "Female", p.stage(), int(p.age_years())]
		var pc := sim.col_of(p)
		if pc.civ_id != 0:
			s += "Tribe: [color=#%s]%s[/color] (AI-controlled)\n" % [pc.color.to_html(false), pc.name]
		if pc.leader_id == p.id:
			s += "[color=#ffd27a][b]%s of the %s[/b][/color]\n" % [pc.leader_title, pc.name]
		s += "Race: %s   Job: [b]%s[/b]\n" % [Config.race_name(p.race), Defs.JOB_NAMES.get(p.job, "Child")]
		if p.frail:
			s += "[color=#e0b080]Frail — born to close kin (works slower, illness is more dangerous)[/color]\n"
		if p.job == "soldier":
			s += "[color=#ffb070]%s%s[/color]\n" % [Military.kind_name(p.soldier_kind), " (hired)" if p.hired else ""]
		if p.weapon != "":
			s += "Armed with: %s (%d damage%s)\n" % [Defs.WEAPONS[p.weapon]["name"], int(HumanAI.strike_damage(sim, p, false)),
				", ranged" if float(Defs.WEAPONS[p.weapon]["range"]) > 2.0 else ""]
		s += "Doing: %s\n" % p.state
		if p.is_sick():
			s += "[color=#ff8a7a]Ill: %s (%.1f days left)\n%s chance of death within %s[/color]\n" % [Defs.ILLNESS[p.illness["type"]]["name"], float(p.illness["days"]),
				Survival.pct_text(Survival.death_risk(sim, p)), Defs.illness_window(p.illness["type"])]
		if p.pregnant_days >= 0.0:
			s += "[color=#9fe08a]Expecting a child (%d/%d days)[/color]\n" % [int(p.pregnant_days), int(Config.rule("pregnancy_days"))]
		var fam := PackedStringArray()
		var partner := sim.person(p.partner_id)
		if partner != null:
			fam.append("partner %s" % partner.name)
		var mom := sim.person(p.mother_id)
		var dad := sim.person(p.father_id)
		if mom != null or dad != null:
			fam.append("child of %s" % " & ".join(PackedStringArray([mom.name if mom != null else "?", dad.name if dad != null else "?"])))
		if not p.children.is_empty():
			fam.append("%d children" % p.children.size())
		if not fam.is_empty():
			s += "Family: %s\n" % ", ".join(fam)
		if p.carry_total() > 0:
			var items := PackedStringArray()
			for k in p.carrying.keys():
				items.append("%d %s" % [int(p.carrying[k]), Defs.item_name(k)])
			s += "Carrying: %s\n" % ", ".join(items)
		var sk := PackedStringArray()
		var keys: Array = p.skills.keys()
		keys.sort_custom(func(x, y): return float(p.skills[x]) > float(p.skills[y]))
		for k in keys.slice(0, 3):
			if float(p.skills[k]) >= 0.5:
				sk.append("%s %.1f" % [Defs.JOB_NAMES.get(k, k), float(p.skills[k])])
		if not sk.is_empty():
			s += "Skills: %s\n" % ", ".join(sk)
		info_text.text = s
		bar_nodes["Health"].value = p.health
		bar_nodes["Food"].value = p.hunger
		bar_nodes["Water"].value = p.thirst
		bar_nodes["Energy"].value = p.energy
		bar_nodes["Warmth"].value = p.warmth
		if game.selected_ids.size() > 1:
			info_text.text += "[color=#9fd8ff]%d people selected — right-click to move, Shift+right-click to attack.[/color]\n" % game.selected_ids.size()
		elif p.civ_id == 0:
			info_text.text += "[color=#a09a88]Right-click: move · Shift+right-click: attack · right-click a ship: board[/color]\n"
		var pacts: Array = []
		if p.civ_id == 0:
			pacts.append(["Rename", _start_rename.bind("person:%d" % p.id)])
			if p.job == "soldier":
				var other := "archer" if p.soldier_kind == "warrior" else "warrior"
				pacts.append(["Make %s" % Military.kind_name(other), _on_switch_kind.bind(p.id, other)])
				pacts.append(["Discharge", _on_discharge.bind(p.id)])
		_set_actions("p%d|%s|%s" % [p.id, p.job, p.soldier_kind], pacts)
		return
	if game.selected_ship_id >= 0:
		var sh: Ship = sim.ship(game.selected_ship_id)
		if sh != null:
			var c := sim.civ(sh.civ_id)
			var s := "[b]%s[/b]\n" % sh.label()
			s += "Passengers: %d / %d   Speed: %.1f\n" % [sh.passengers.size(), sim.ship_capacity(sh), sh.speed(c)]
			for pid in sh.passengers:
				var q := sim.person(int(pid))
				if q != null:
					s += "  • %s\n" % q.name
			s += "[color=#a09a88]Right-click water to sail, or a shore to land everyone there.\nTo board: select people, then right-click the ship.[/color]\n" if sh.civ_id == 0 else ""
			info_text.text = s
			_set_actions("s%d|%d" % [sh.id, sh.passengers.size()], [["Unload here", _on_unload.bind(sh.id)], ["Rename", _start_rename.bind("ship:%d" % sh.id)]] if sh.civ_id == 0 else [])
			return
	if game.selected_building_id >= 0:
		var b := sim.building(game.selected_building_id)
		if b != null:
			var d: Dictionary = b.def()
			var s := "[b]%s[/b]\n%s\n" % [b.display_name(), d["desc"]]
			if b.built and (b.cur_hp() < b.max_hp() or b.type in ["wall", "gate", "watchtower", "arrow_tower", "capitol"]):
				s += "Strength: %d / %d\n" % [int(b.cur_hp()), int(b.max_hp())]
			if b.civ_id != 0:
				var bc := sim.civ(b.civ_id)
				s += "Owned by [color=#%s]%s[/color]\n" % [bc.color.to_html(false), bc.name]
			if not b.built:
				var need := b.needs()
				if need.is_empty():
					s += "[color=#ffd27a]Blueprint — all materials here, building: %d%%[/color]\n" % int(100.0 * b.progress / float(d["work"]))
				else:
					var parts := PackedStringArray()
					var cost: Dictionary = b.cost()
					for k in cost.keys():
						parts.append("%s %d/%d" % [Defs.item_name(k), int(b.delivered.get(k, 0.0)), int(cost[k])])
					s += "[color=#9fd8ff]Blueprint — materials delivered: %s[/color]\n" % ", ".join(parts)
					s += "[color=#a09a88]Builders and laborers bring materials from storage; gatherers collect what's missing.[/color]\n"
			match b.type:
				"campfire":
					s += ("Burning — %.0f hours of firewood left\n" % b.fuel) if b.fuel > 0.0 else "[color=#ff8a7a]Out — needs wood[/color]\n"
				"shelter", "bedding":
					s += "Sleeping here: %d / %d\n" % [b.occupants.size(), int(d["housing"])]
				"farm":
					var st: String = ["Empty (plant in spring/summer)", "Growing %d%%" % int(b.crop_growth * 100.0), "Ready to harvest!"][b.crop_stage]
					s += "Crop: %s\n" % st
				"blacksmith":
					var bc2 := sim.civ(b.civ_id)
					if b.craft != "":
						s += "Forging: %s (%d%%)\n" % [Defs.WEAPONS[b.craft]["name"], int(100.0 * b.craft_progress / float(Defs.WEAPONS[b.craft]["hours"]))]
					else:
						s += "The forge is cold.\n"
					var smiths := 0
					for q in bc2.living():
						if q.job == "smith":
							smiths += 1
					s += "Blacksmiths: %d   Auto-forge for unarmed soldiers: %s\n" % [smiths, "on" if b.auto_craft else "off"]
					if not bc2.weapon_orders.is_empty():
						var qn := PackedStringArray()
						for w in bc2.weapon_orders:
							qn.append(str(Defs.WEAPONS[w]["name"]))
						s += "Queued: %s\n" % ", ".join(qn)
					if smiths == 0 and b.civ_id == 0:
						s += "[color=#ffd27a]Give someone the Blacksmith job to forge weapons.[/color]\n"
				"training_camp", "mercenary_hall":
					var tc := sim.civ(b.civ_id)
					var armed := 0
					for q in tc.soldiers():
						if q.weapon != "" and Defs.weapon_ranged(q.weapon) == (q.soldier_kind == "archer"):
							armed += 1
					s += "Warriors: %d   Archers: %d   (%d armed)\nWeapons in store: %d\n" % [tc.soldiers("warrior").size(), tc.soldiers("archer").size(), armed, tc.weapons_in_stock()]
					if b.civ_id == 0:
						s += "[color=#a09a88]Training turns one of your adults into a soldier; the Blacksmith forges their weapon. Warriors fight up close, Archers from range.[/color]\n"
						if b.type == "mercenary_hall":
							s += "[color=#a09a88]Hired soldiers are newcomers who arrive armed and join your tribe for good.[/color]\n"
				"map_table":
					s += "[color=#9fd8ff]The World Map (M) now has a Territory view.[/color]\n"
				"monolith":
					var mc := sim.civ(b.civ_id)
					s += "Knowledge: %s KP · %d KP per year skipped\n" % [_fmt_int(mc.knowledge), int(Config.rule("monolith_kp"))]
					s += "[color=#a09a88]Skipping moves the calendar forward. Nobody ages and nothing else changes.[/color]\n"
			var acts: Array = []
			if b.civ_id == 0:
				if b.type == "harbor" and b.built:
					if b.ship_order >= 0:
						s += "Building a %s: %d%%\n" % [Defs.SHIP_TYPES[b.ship_order]["name"], int(b.ship_progress * 100.0)]
					else:
						var best := sim.best_ship_kind(sim.colony)
						for k in best + 1:
							var st: Dictionary = Defs.SHIP_TYPES[k]
							acts.append(["Build %s (%s)" % [st["name"], Defs.cost_text(st["cost"])], _on_build_ship.bind(b.id, k)])
						if best < Defs.SHIP_TYPES.size() - 1:
							s += "[color=#a09a88]Research Sails / Galleys for bigger ships.[/color]\n"
				if b.type == "monolith" and b.built:
					var per := Config.rule("monolith_kp")
					for n in [1, 10]:
						acts.append(["Skip %d year%s (%s KP)" % [n, "" if n == 1 else "s", _fmt_int(n * per)], _on_skip_years.bind(n)])
					acts.append(["Skip 50 years (%s KP)" % _fmt_int(50 * per), _on_skip_years.bind(50)])
				if b.type in ["training_camp", "mercenary_hall"] and b.built:
					var tp := Military.train_problem(sim.colony)
					for kind in ["warrior", "archer"]:
						acts.append(["Train %s" % Military.kind_name(kind), _on_train_soldier.bind(kind)])
					if tp != "":
						s += "[color=#ff8a7a]%s[/color]\n" % tp
					if b.type == "mercenary_hall":
						for kind in ["warrior", "archer"]:
							acts.append(["Hire %s (%d %s)" % [Military.kind_name(kind), Military.hire_cost(sim.colony, kind), Defs.MONEY_NAME], _on_hire_soldier.bind(kind)])
				if b.type == "blacksmith" and b.built:
					for w in sim.colony.forgeable_weapons():
						var wd: Dictionary = Defs.WEAPONS[w]
						acts.append(["Forge %s (%s)" % [wd["name"], Defs.cost_text(wd["cost"])], _on_forge.bind(w)])
					acts.append(["Auto-forge: " + ("ON" if b.auto_craft else "OFF"), _on_toggle_auto_forge.bind(b.id)])
				acts.append(["Cancel blueprint" if not b.built else "Demolish", _on_demolish])
			var zt := Defs.zone_for(b.type)
			if zt > 0 and b.civ_id == 0:
				var zd: Dictionary = Defs.ZONES[zt]
				if b.zoned:
					s += "[color=#9fe08a]In a %s zone: %s[/color]\n" % [zd["name"], zd["desc"]]
				else:
					s += "[color=#a09a88]Belongs in a %s zone (Plan Town, Z) for: %s[/color]\n" % [zd["name"], zd["desc"]]
			info_text.text = s
			_set_actions("b%d|%s|%d|%s|%d|%d|%d" % [b.id, str(b.built), b.ship_order, str(b.auto_craft), sim.colony.era_i, int(sim.colony.money) / 10, sim.colony.soldiers().size()], acts)
			return
	if game.selected_civ_id >= 0:
		_info_civ(sim, sim.civ(game.selected_civ_id))
		return
	if game.selected_state >= 0:
		_info_state(sim, game.selected_state)
		return
	_set_actions("", [])
	# hovered tile
	var t: Vector2i = game.hover_tile
	if sim.world.inb(t):
		var i := sim.world.idx(t)
		var s := "[b]%s[/b]   %d°C\n" % [Defs.terrain_name(sim.world.terrain[i]) + (" (snow)" if sim.world.snowy[i] == 1 else ""), roundi(sim.temp_at(t))]
		var r := sim.world.res_type[i]
		if r != 0:
			s += "%s — %d left\n" % [Defs.RES[r]["name"], sim.world.res_amount[i]]
		if sim.world.is_water(t):
			s += "Fish: %d   %s\n" % [int(sim.world.fish[i]), "Fresh water" if sim.world.is_fresh(t) else "Salt water"]
		if game.picking:
			var wd := sim.water_distance(t, 20)
			var prob := sim.start_problem(t)
			if prob != "":
				s += "[color=#ff8a7a]%s[/color]\n" % prob
			elif wd < 0:
				s += "[color=#ffd27a]No fresh water nearby — risky![/color]\n"
			else:
				s += "[color=#9fe08a]Fresh water %d tiles away. Click to settle here.[/color]\n" % wd
		for oc in sim.colonies:
			if oc.civ_id != 0 and not oc.collapsed and sim.have_met(0, oc.civ_id) \
					and Vector2(t).distance_to(Vector2(oc.home)) < oc.territory():
				s += "Territory of the [color=#%s]%s[/color]\n" % [oc.color.to_html(false), oc.name]
				break
		info_text.text = s
	else:
		info_text.text = ""


# ================================================================ minimap / world map
func _build_minimap() -> void:
	var holder := PanelContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	holder.offset_left = 8
	holder.offset_bottom = -8
	holder.offset_top = -224
	holder.offset_right = 224
	root.add_child(holder)
	minimap = MapView.new()
	minimap.game = game
	minimap.custom_minimum_size = Vector2(200, 200)
	holder.add_child(minimap)


func _build_worldmap() -> void:
	worldmap_panel = PanelContainer.new()
	worldmap_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	worldmap_panel.custom_minimum_size = Vector2(700, 730)
	worldmap_panel.offset_left = -350
	worldmap_panel.offset_top = -365
	worldmap_panel.offset_right = 350
	worldmap_panel.offset_bottom = 365
	worldmap_panel.visible = false
	root.add_child(worldmap_panel)
	var v := VBoxContainer.new()
	worldmap_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("World Map — seed %d" % game.sim.world.seed_value, 17, Color(1.0, 0.85, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	terr_button = _button("Territory view", _on_territory_toggle, 130)
	terr_button.tooltip_text = "Political map of who holds which land. Needs a Map Table (research Cartography)."
	head.add_child(terr_button)
	head.add_child(_button("−", func(): worldmap.set_zoom(worldmap.map_zoom / 1.5), 28))
	head.add_child(_button("+", func(): worldmap.set_zoom(worldmap.map_zoom * 1.5), 28))
	head.add_child(_button("Fit", func(): worldmap.reset_view(), 40))
	head.add_child(_button("x", toggle_worldmap, 28))
	worldmap = MapView.new()
	worldmap.game = game
	worldmap.zoomable = true
	worldmap.tooltip_text = "Mouse wheel: zoom · right-drag: pan · left-click: go there"
	worldmap.show_animals = true
	worldmap.custom_minimum_size = Vector2(680, 680)
	v.add_child(worldmap)


func toggle_worldmap() -> void:
	worldmap_panel.visible = not worldmap_panel.visible
	var ok: bool = game.sim.colony.has_built("map_table")
	terr_button.disabled = not ok
	terr_button.text = "Territory view" if ok else "Territory (Map Table)"
	if not ok:
		worldmap.territory_mode = false


func _on_territory_toggle() -> void:
	worldmap.territory_mode = not worldmap.territory_mode
	terr_button.text = "Terrain view" if worldmap.territory_mode else "Territory view"


func rebuild_maps() -> void:
	minimap.build(game.sim.world)
	worldmap.build(game.sim.world)


# ================================================================ hint + pause
func _build_hint() -> void:
	hint_label = _label("", 15, Color(1.0, 0.9, 0.6))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_top = -70
	hint_label.offset_bottom = -44
	hint_label.offset_left = -400
	hint_label.offset_right = 400
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint_label.add_theme_constant_override("outline_size", 5)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_label)


func _build_pause_menu() -> void:
	pause_layer = ColorRect.new()
	(pause_layer as ColorRect).color = Color(0, 0, 0, 0.55)
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.visible = false
	root.add_child(pause_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	pause_box = VBoxContainer.new()
	pause_box.custom_minimum_size = Vector2(520, 0)
	pause_box.add_theme_constant_override("separation", 6)
	panel.add_child(pause_box)


func toggle_pause_menu() -> void:
	if pause_layer.visible:
		pause_layer.visible = false
		game.menu_paused = false
	else:
		_fill_pause_menu("")
		pause_layer.visible = true
		game.menu_paused = true


func _fill_pause_menu(message: String) -> void:
	for c in pause_box.get_children():
		pause_box.remove_child(c)
		c.queue_free()
	pause_box.add_child(_label("Game Menu", 22, Color(1.0, 0.85, 0.5)))
	if message != "":
		pause_box.add_child(_label(message, 14, Color(0.6, 0.95, 0.55)))
	pause_box.add_child(_button("Resume", toggle_pause_menu))
	pause_box.add_child(HSeparator.new())
	pause_box.add_child(_label("Save game", 15))
	for i in SaveSystem.SLOTS:
		var b := _button("Save to " + SaveSystem.describe(i), _on_save.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pause_box.add_child(b)
	pause_box.add_child(_label("Load game", 15))
	for i in SaveSystem.SLOTS:
		var b := _button("Load " + SaveSystem.describe(i), _on_load.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = SaveSystem.info(i).is_empty()
		pause_box.add_child(b)
	pause_box.add_child(HSeparator.new())
	pause_box.add_child(_button("Settings", _open_settings))
	pause_box.add_child(_button("Main Menu", Callable(game, "go_main_menu")))
	pause_box.add_child(_button("Quit Game", func(): game.get_tree().quit()))


func _on_save(slot: int) -> void:
	var ok: bool = game.save_slot(slot)
	_fill_pause_menu("Saved to slot %d." % (slot + 1) if ok else "Save failed!")


func _on_load(slot: int) -> void:
	game.load_slot(slot)


func show_game_over() -> void:
	if gameover_shown:
		return
	gameover_shown = true
	_fill_pause_menu("Your tribe has perished after %d days. Load a save or start a new world." % game.sim.time.day())
	pause_layer.visible = true
	game.menu_paused = true


# ================================================================ start picker
func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	picker.offset_top = 52
	picker.offset_left = -330
	picker.offset_right = 330
	picker.visible = false
	root.add_child(picker)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	picker.add_child(v)
	v.add_child(_label("Choose where your tribe begins", 20, Color(1.0, 0.85, 0.5)))
	var info := _label("Left-click anywhere on the land (or on the World Map) to settle there.\nGood spots: flat land near a river, lake or spring, with trees and berries nearby.\nHover a tile to see how far fresh water is.", 13, Color(0.85, 0.82, 0.74))
	v.add_child(info)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(_button("Use the suggested spot", Callable(game, "use_suggested_start")))
	h.add_child(_button("Open World Map  [M]", toggle_worldmap))


func show_picker(on: bool) -> void:
	picker.visible = on
	if on:
		feed.visible = false
	else:
		feed.visible = not side_panel.visible
		if worldmap_panel.visible:
			toggle_worldmap()


# ================================================================ per-frame refresh
func _process(delta: float) -> void:
	if game == null or game.sim == null:
		return
	# fade the event feed
	for n in feed.get_children():
		var l := n as Label
		var age: float = float(l.get_meta("age", 0.0)) + delta
		l.set_meta("age", age)
		l.modulate.a = clampf(1.0 - (age - 12.0) / 3.0, 0.0, 1.0)
		if age > 15.0:
			feed.remove_child(l)
			l.queue_free()
	feed_box.visible = feed.get_child_count() > 0
	if fps_label != null:
		fps_label.visible = Settings.show_fps
		if Settings.show_fps:
			fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	var mode: String = game.build_mode
	if planner != null and planner.visible:
		planner_hint.text = _planner_hint()
	if game.tool_mode == "clear":
		hint_label.text = "Clear land — drag a box over trees, bushes, stones or animals (Shift+drag to unmark). Right-click / Esc to stop."
	elif mode != "":
		var err: String = game.sim.can_place(game.sim.colony, mode, game.place_tile)
		hint_label.text = "Placing %s — left-click to place, right-click to cancel.  %s" % [Defs.BUILDINGS[mode]["name"], err]
	else:
		hint_label.text = ""
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = 0.25
	_refresh_top()
	_refresh_info()
	_refresh_passage()
	_refresh_deal()
	if game.sim.colony.gov_pending and not gov_layer.visible and game.sim.started and not game.sim.debug_log:
		_show_gov_dialog()
	if research_layer.visible:
		_refresh_research()
	if build_layer.visible and _build_signature() != _build_sig:
		refresh_build_window()
	if side_panel.visible:
		match current_panel:
			"build":
				_refresh_build_buttons()
			"jobs":
				if game.sim.colony.population() != jobs_pop:
					_rebuild_panel()
				else:
					for pid in job_status_labels.keys():
						var p: Human = game.sim.person(absi(pid))
						if p != null:
							job_status_labels[pid].text = p.state if pid > 0 else Defs.JOB_NAMES.get(p.job, p.job)
			"stock", "colony", "milestones":
				_rebuild_panel()
			"stock_dummy":
				pass


func _refresh_top() -> void:
	var sim: Sim = game.sim
	var c := sim.colony
	stat_labels["pop"].text = str(c.population())
	stat_labels["food"].text = "%d  (%.1fd)" % [int(c.food_units()), c.food_days()]
	stat_labels["water"].text = "%d/%d" % [int(c.count("water")), int(c.water_capacity())]
	stat_labels["wood"].text = str(int(c.count("wood")))
	stat_labels["stone"].text = str(int(c.count("stone")))
	stat_labels["sticks"].text = str(int(c.count("sticks")))
	stat_labels["health"].text = "%d%%" % int(c.health_pct())
	stat_labels["money"].text = "%d %s" % [int(c.money), Defs.MONEY_NAME]
	var season := sim.time.season()
	season_icon.texture = Art.icons[["spring", "summer", "fall", "winter"][season]]
	date_label.text = "%s · %s" % [sim.time.season_name(), sim.time.date_text()]
	clock_icon.texture = Art.icons["moon"] if sim.time.is_night() else Art.icons["sun"]
	clock_label.text = "%s %s" % [sim.time.clock_text(), sim.time.phase_name()]
	temp_label.text = "%d°C" % roundi(sim.temp_at(c.home))
	weather_label.text = sim.weather.label()
	for e in speed_buttons:
		var b: Button = e[0]
		var s: float = e[1]
		b.set_pressed_no_signal((game.paused and s == 0.0) or (not game.paused and s == game.speed))


# ================================================================ blacksmith actions
func _on_forge(w: String) -> void:
	var c: Colony = game.sim.colony
	c.weapon_orders.append(w)
	push_event("Queued at the blacksmith: %s. Smiths take the materials from storage when they start." % Defs.WEAPONS[w]["name"], "info")
	_actions_sig = ""


func _on_train_soldier(kind: String) -> void:
	var why := Military.train_problem(game.sim.colony)
	if why != "":
		push_event(why, "warn")
	else:
		Military.train(game.sim, game.sim.colony, kind)
	_actions_sig = ""


func _on_hire_soldier(kind: String) -> void:
	var why := Military.hire_problem(game.sim.colony, kind)
	if why != "":
		push_event(why, "warn")
	else:
		Military.hire(game.sim, game.sim.colony, kind)
	_actions_sig = ""


func _on_switch_kind(pid: int, kind: String) -> void:
	var p = game.sim.person(pid)
	if p != null:
		p.soldier_kind = kind
		p.drafted = true
		p.task = {}
		push_event("%s is now %s %s. They'll swap to a %s weapon from the stockpile." % [p.name, "an" if kind == "archer" else "a", Military.kind_name(kind), "ranged" if kind == "archer" else "close-combat"], "info")
	_actions_sig = ""


func _on_discharge(pid: int) -> void:
	var p = game.sim.person(pid)
	if p != null:
		Military.discharge(game.sim, p)
	_actions_sig = ""


func _on_toggle_auto_forge(bid: int) -> void:
	var b: Building = game.sim.building(bid)
	if b != null:
		b.auto_craft = not b.auto_craft
	_actions_sig = ""


# ================================================================ diplomacy (click a tribe's flag)
func _info_civ(sim: Sim, oc: Colony) -> void:
	var me: Colony = sim.colony
	var s := "[b][color=#%s]%s[/color][/b]\n" % [oc.color.to_html(false), oc.name]
	s += "%s · %s · %d people\n" % [Config.race_name(oc.race), oc.era, oc.population()]
	if oc.government != "":
		s += "Government: %s\n" % Defs.GOVERNMENTS[oc.government]["name"]
	s += _leader_text(sim, oc, false)
	var acts: Array = []
	if oc.civ_id == 0:
		s += "This is your tribe.  Talents: %d   Soldiers: %d\n" % [int(oc.money), oc.soldiers().size()]
		info_text.text = s
		_set_actions("civ0", [["Rename tribe", _start_rename.bind("tribe")]])
		return
	var met := sim.have_met(0, oc.civ_id)
	var war := sim.at_war(0, oc.civ_id)
	if not met:
		s += "[color=#a09a88]You haven't met this tribe yet.[/color]\n"
	else:
		var rel := sim.relation(0, oc.civ_id)
		s += "Relations: %s (%d)\n" % [Sim.relation_label(rel), int(rel)]
	s += "Strength: theirs %d · yours %d\n" % [int(sim.military_strength(oc)), int(sim.military_strength(me))]
	if war:
		var w: Dictionary = sim.wars[sim._key(0, oc.civ_id)]
		var dead: Dictionary = w["dead"]
		s += "[color=#ff8a7a][b]AT WAR[/b] for %d days — your dead %d, theirs %d[/color]\n" % [sim.time.day() - int(w["since"]), int(dead.get("0", 0)), int(dead.get(str(oc.civ_id), 0))]
		s += "Peace chance now: %d%%\n" % int(sim.peace_chance(0, oc.civ_id) * 100.0)
		acts.append(["Send soldiers to attack", _on_send_army.bind(oc.civ_id)])
		if sim.peace_offers.has(oc.civ_id):
			s += "[color=#9fe08a]They are offering peace.[/color]\n"
			acts.append(["Accept their peace", _on_accept_peace.bind(oc.civ_id)])
		acts.append(["Offer peace", _on_offer_peace.bind(oc.civ_id)])
	else:
		var why := sim.war_problem(0, oc.civ_id)
		if why == "":
			acts.append(["Declare war", _on_declare_war.bind(oc.civ_id)])
		else:
			s += "[color=#a09a88]%s[/color]\n" % why
		if met:
			acts.append(["Send gift (25 %s)" % Defs.MONEY_NAME, _on_gift.bind(oc.civ_id)])
			if Deals.allied(sim, 0, oc.civ_id):
				s += "[color=#9fe08a][b]Allied[/b] — you defend each other and may cross each other's land.[/color]\n"
				acts.append(["Break alliance", _on_deal_propose.bind(oc.civ_id, "break")])
			else:
				acts.append(["Propose alliance (%d%%)" % roundi(clampf(0.15 + sim.relation(0, oc.civ_id) / 100.0, 0.02, 0.9) * 100.0), _on_deal_propose.bind(oc.civ_id, "alliance")])
			acts.append(["Ask for a trade", _on_deal_propose.bind(oc.civ_id, "trade")])
			acts.append(["Demand tribute", _on_deal_propose.bind(oc.civ_id, "tribute")])
			if me.era_i >= 1:
				acts.append(["Demand land", _on_deal_propose.bind(oc.civ_id, "land")])
			var their_allies := Deals.allies_of(sim, oc.civ_id)
			if not their_allies.is_empty():
				s += "Allies: %s\n" % ", ".join(PackedStringArray(their_allies.map(func(a): return "you" if a.civ_id == 0 else a.name)))
		# right of passage, both ways
		var mine_left := Borders.access_years_left(sim, 0, oc.civ_id)
		var theirs_left := Borders.access_years_left(sim, oc.civ_id, 0)
		if mine_left > 0.0:
			s += "[color=#9fe08a]Your Billies may cross their land (%d more years).[/color]\n" % ceili(mine_left)
		else:
			s += "Your Billies may not cross their land. Caught there: %d%% chance of war.\n" % roundi(Borders.war_chance(sim, 0, oc.civ_id) * 100.0)
			if met:
				acts.append(["Ask for passage (%d%%)" % roundi(Borders.grant_chance(sim, 0, oc.civ_id) * 100.0), _on_ask_passage.bind(oc.civ_id)])
		if theirs_left > 0.0:
			s += "They may cross your land (%d more years).\n" % ceili(theirs_left)
			acts.append(["Revoke their passage", _on_revoke_passage.bind(oc.civ_id)])
	acts.append(["Go to their camp", func(): game.camera.position = sim.world.center_of(oc.home)])
	info_text.text = s
	_set_actions("civ%d|%s|%s|%s|%s|%d|%d" % [oc.civ_id, str(war), str(sim.peace_offers.has(oc.civ_id)), str(met), str(Deals.allied(sim, 0, oc.civ_id)),
		ceili(Borders.access_years_left(sim, 0, oc.civ_id)), ceili(Borders.access_years_left(sim, oc.civ_id, 0))], acts)


func _on_deal_propose(cid: int, kind: String) -> void:
	var sim: Sim = game.sim
	if kind == "break":
		Deals.break_alliance(sim, 0, cid)
	else:
		var why := Deals.player_propose(sim, cid, kind)
		if why != "":
			push_event(why, "warn")
	_actions_sig = ""


func _on_ask_passage(cid: int) -> void:
	Borders.request(game.sim, 0, cid, true)
	_actions_sig = ""


func _on_revoke_passage(cid: int) -> void:
	Borders.revoke(game.sim, cid, 0)
	push_event("The %s may no longer cross your land." % game.sim.civ(cid).name, "info")
	_actions_sig = ""


## The next election: who's standing, the forecast, and what the player can do about it.
func _election_text(sim: Sim, c: Colony) -> String:
	var cands := Elections.preview(sim, c)
	if cands.size() < 2:
		return ""
	var fc := Elections.forecast(sim, c)
	var s := "[b]Next election[/b] (%s) — click a name to back them:\n" % Elections.title_for(c)
	for cand in cands:
		var share := roundi(float(fc.get(cand.id, 0.0)) * 100.0)
		var mark := "[color=#ffd27a]★ [/color]" if c.backed_id == cand.id else "   "
		var camp := float(c.campaign.get(cand.id, 0.0))
		s += "%s[url=back:%d]%s[/url] [color=#a09a88](%d, %s)[/color] ~%d%%%s\n" % [mark, cand.id, cand.name, int(cand.age_years()),
			Defs.JOB_NAMES.get(cand.job, cand.job), share, (" [color=#9fd8ff]+%d campaign[/color]" % int(camp)) if camp > 0.0 else ""]
	var bk := sim.person(c.backed_id)
	if bk != null and bk.alive:
		s += "  [url=rally:%d][color=#ffd27a]Hold a rally for %s (%d %s)[/color][/url]\n" % [bk.id, bk.name, Elections.CAMPAIGN_COST, Defs.MONEY_NAME]
		s += "  [url=gift:%d][color=#ffd27a]Hand out gifts in their name (%d food)[/color][/url]\n" % [bk.id, Elections.GIFT_FOOD]
		if c.rigged:
			s += "  [color=#ff8a7a]The count is rigged for %s (%d%% chance it's discovered).[/color] [url=unrig][color=#ffd27a]Call it off[/color][/url]\n" % [bk.name, roundi(Elections.rig_catch_chance(c, c.living().size()) * 100.0)]
		else:
			s += "  [url=rig][color=#ff9f7a]Rig the count for %s[/color][/url] [color=#a09a88](%d%% risk of unrest)[/color]\n" % [bk.name, roundi(Elections.rig_catch_chance(c, c.living().size()) * 100.0)]
	if c.in_unrest():
		s += "[color=#ff8a7a]Unrest over a stolen election: work -15%%, fewer births (%d more years).[/color]\n" % ceili(c.unrest_until - sim.time.cal_years())
	return s


func _on_election_link(m: String) -> void:
	var sim: Sim = game.sim
	var c := sim.colony
	var why := ""
	if m.begins_with("back:"):
		var pid := int(m.substr(5))
		c.backed_id = -1 if c.backed_id == pid else pid
		if c.backed_id < 0:
			c.rigged = false
	elif m.begins_with("rally:"):
		if int(m.substr(6)) > 0:
			why = Elections.campaign_talents(sim, c, int(m.substr(6)))
			if why == "":
				push_event("A rally is held. Support grows.", "good")
	elif m.begins_with("gift:"):
		why = Elections.campaign_gifts(sim, c, int(m.substr(5)))
		if why == "":
			push_event("Gifts are handed out. Voters remember kindness.", "good")
	elif m == "rig":
		c.rigged = true
		push_event("The count will be rigged. Let's hope nobody notices.", "warn")
	elif m == "unrig":
		c.rigged = false
	if why != "":
		push_event(why, "warn")
	_rebuild_panel()


## Leader line(s) for the Colony panel and diplomacy panel.
func _leader_text(sim: Sim, c: Colony, detail: bool) -> String:
	var ld := Elections.leader(sim, c)
	if ld == null:
		return ""
	var s := "[b]%s:[/b] [color=#ffd27a]%s[/color]" % [c.leader_title, ld.name]
	if c.leader_terms > 1:
		s += " (term %d)" % c.leader_terms
	var yrs := ceili(c.next_election - sim.time.cal_years())
	s += " · next election in %d year%s\n" % [maxi(0, yrs), "" if yrs == 1 else "s"]
	if detail and not c.last_election.is_empty():
		var le: Dictionary = c.last_election
		var parts := PackedStringArray()
		for r in le.get("results", []):
			parts.append("%s %d" % [r[1], int(r[2])])
		if parts.size() > 1:
			s += "  [color=#a09a88]Year %d vote: %s[/color]\n" % [int(le.get("year", 0)), ", ".join(parts)]
		var fx := PackedStringArray()
		for k in c.leader_fx.keys():
			var key := str(k)
			if key == "work_all":
				fx.append("+%d%% all work" % roundi(float(c.leader_fx[k]) * 100.0))
			else:
				fx.append("+%d%% %s work" % [roundi(float(c.leader_fx[k]) * 100.0), Defs.JOB_NAMES.get(key.trim_prefix("work_"), key)])
		if not fx.is_empty():
			s += "  [color=#9fd8ff]Leader bonus: %s[/color]\n" % ", ".join(fx)
	return s


func _on_declare_war(cid: int) -> void:
	if game.sim.declare_war(0, cid):
		_actions_sig = ""


func _on_offer_peace(cid: int) -> void:
	game.sim.offer_peace(0, cid)
	_actions_sig = ""


func _on_accept_peace(cid: int) -> void:
	game.sim.make_peace(0, cid)
	_actions_sig = ""


func _on_gift(cid: int) -> void:
	var sim: Sim = game.sim
	if sim.colony.money < 25.0:
		push_event("You need 25 %s for a gift." % Defs.MONEY_NAME, "warn")
		return
	sim.colony.money -= 25.0
	sim.civ(cid).money += 25.0
	var k: String = sim._key(0, cid)
	sim.relations[k] = minf(100.0, float(sim.relations.get(k, 0.0)) + 10.0)
	push_event("The %s gladly accept your gift." % sim.civ(cid).name, "good")
	_actions_sig = ""


## Sends your soldiers (or the selected soldiers, if any) to raid an enemy tribe.
func _on_send_army(cid: int) -> void:
	var sim: Sim = game.sim
	var group: Array = []
	for pid in game.selected_ids:
		var q: Human = sim.person(int(pid))
		if q != null and q.alive and q.job == "soldier":
			group.append(q)
	if group.is_empty():
		group = sim.colony.soldiers()
	var n := 0
	for q in group:
		if HumanAI.order_raid(sim, q, cid):
			n += 1
	if n == 0:
		push_event("You have no soldiers to send. Build a Training Camp and give people the Soldier job.", "warn")
	else:
		push_event("%d soldiers march on the %s." % [n, sim.civ(cid).name], "warn")


# ================================================================ government choice
func _build_gov_dialog() -> void:
	gov_layer = ColorRect.new()
	(gov_layer as ColorRect).color = Color(0, 0, 0, 0.55)
	gov_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gov_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	gov_layer.visible = false
	root.add_child(gov_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gov_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	gov_box = VBoxContainer.new()
	gov_box.add_theme_constant_override("separation", 8)
	panel.add_child(gov_box)


func _show_gov_dialog() -> void:
	var c: Colony = game.sim.colony
	for ch in gov_box.get_children():
		ch.queue_free()
	gov_box.add_child(_label("Choose a Government", 22, Color(1.0, 0.85, 0.5)))
	gov_box.add_child(_label("Your tribe has entered the %s. Your people need to be ruled — how?" % c.era, 14))
	for g in Defs.governments_of_era(c.era_i):
		var gd: Dictionary = Defs.GOVERNMENTS[g]
		var fx := PackedStringArray()
		for k in gd["fx"].keys():
			fx.append(_fx_text(k, float(gd["fx"][k])))
		var b := Button.new()
		b.text = "%s\n%s\n%s" % [gd["name"], gd["desc"], " · ".join(fx)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(600, 64)
		b.pressed.connect(_on_gov_chosen.bind(g))
		gov_box.add_child(b)
	gov_box.add_child(_label("A Capitol (research Statecraft) makes your government's bonuses 50% stronger.", 12, Color(0.75, 0.72, 0.65)))
	gov_layer.visible = true
	game.set_speed(0.0)


func _fx_text(k: String, v: float) -> String:
	var names := {"fight": "+%d fighting", "work_all": "+%d%% all work", "defense": "+%d%% defence", "medicine": "+%d%% medicine",
		"heal": "+%d%% healing", "research": "+%d%% research", "trade": "+%d%% trade earnings", "storage": "+%d storage",
		"work_builder": "+%d%% building", "fertility": "%+d%% births", "work_hunter": "+%d%% hunting", "train": "+%d%% soldier training"}
	var pct := k != "fight" and k != "storage"
	return str(names.get(k, k + " %d")) % int(round(v * (100.0 if pct else 1.0)))


func _on_gov_chosen(g: String) -> void:
	var c: Colony = game.sim.colony
	c.government = g
	c.gov_pending = false
	c.invalidate_bonus()
	gov_layer.visible = false
	push_event("Your tribe is now a %s." % Defs.GOVERNMENTS[g]["name"], "good")
	game.set_speed(1.0)


# ================================================================ monolith
func _on_skip_years(n: int) -> void:
	var err: String = game.sim.skip_years(game.sim.colony, n)
	if err != "":
		push_event(err, "warn")
	_actions_sig = ""


# ================================================================ territory states
func _info_state(sim: Sim, st: int) -> void:
	var sm: StateMap = sim.states
	var ow := int(sm.owners[st])
	var s := "[b]%s[/b]\n%d tiles\n" % [sm.names[st], int(sm.sizes[st])]
	if ow >= 0:
		var oc := sim.civ(ow)
		s += "Held by the [color=#%s]%s[/color]%s\n" % [oc.color.to_html(false), oc.name, " (their homeland)" if st == sim.capital_state(oc) else ""]
	else:
		s += "Unclaimed land.\n"
	var acts: Array = []
	if ow != 0:
		var why := sim.claim_problem(0, st)
		if why == "":
			if ow < 0:
				s += "[color=#9fe08a]Send someone to raise your banner here.[/color]\n"
				acts.append(["Send a Billy to claim it", _on_claim_state.bind(st, false)])
			else:
				s += "[color=#ffd27a]At war: your soldiers must reach its centre and hold it.[/color]\n"
				acts.append(["Send soldiers to capture it", _on_claim_state.bind(st, true)])
		else:
			s += "[color=#a09a88]%s[/color]\n" % why
	acts.append(["Go there", func(): game.camera.position = sim.world.center_of(sm.centers[st])])
	info_text.text = s
	_set_actions("st%d|%d|%d" % [st, ow, sim.colony.population()], acts)


func _on_claim_state(st: int, soldiers: bool) -> void:
	var sim: Sim = game.sim
	var pool: Array = []
	for pid in game.selected_ids:
		var q: Human = sim.person(int(pid))
		if q != null and q.alive and q.civ_id == 0:
			pool.append(q)
	if pool.is_empty():
		for q in sim.colony.living():
			if q.is_adult() and (q.job == "soldier") == soldiers:
				pool.append(q)
	var target := sim.world.center_of(sim.states.centers[st])
	pool.sort_custom(func(a, b): return a.pos.distance_squared_to(target) < b.pos.distance_squared_to(target))
	var n := 0
	for q in pool.slice(0, 4 if soldiers else 1):
		if HumanAI.order_claim(sim, q, st):
			n += 1
	if n == 0:
		push_event("Nobody could set out for %s." % sim.states.names[st], "warn")
	else:
		push_event("%d of your people set out for %s." % [n, sim.states.names[st]], "info")


# ================================================================ settings
func _build_settings_layer() -> void:
	settings_layer = ColorRect.new()
	(settings_layer as ColorRect).color = Color(0, 0, 0, 0.5)
	settings_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_layer.visible = false
	root.add_child(settings_layer)


func _open_settings() -> void:
	for ch in settings_layer.get_children():
		ch.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(center)
	var sw := SettingsWindow.new()
	sw.closed.connect(func(): settings_layer.visible = false)
	center.add_child(sw)
	settings_layer.visible = true


# ================================================================ build window
# A window in the middle of the screen: one tab per age, structures grouped by kind.
func _build_build_window() -> void:
	build_layer = PanelContainer.new()
	build_layer.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	build_layer.custom_minimum_size = Vector2(1080, 640)
	build_layer.offset_left = -540
	build_layer.offset_right = 540
	build_layer.offset_top = -320
	build_layer.offset_bottom = 320
	build_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	build_layer.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.065, 0.06, 1.0)
	bg.border_color = Color(0.55, 0.45, 0.28)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(12)
	build_layer.add_theme_stylebox_override("panel", bg)
	root.add_child(build_layer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	build_layer.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("Build", 22, Color(1.0, 0.85, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label("Pick a structure, then left-click the map to lay its blueprint. Shift keeps placing. Right-click or Esc cancels.", 12, Color(0.75, 0.72, 0.65)))
	head.add_child(_button("Close  [B]", close_panel, 100))
	build_tabs = TabContainer.new()
	build_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(build_tabs)


func toggle_build_window() -> void:
	if build_layer.visible:
		close_panel()
		return
	side_panel.visible = false
	research_layer.visible = false
	current_panel = ""
	refresh_build_window()
	build_tabs.current_tab = clampi(game.sim.colony.era_i, 0, Defs.ERAS.size() - 1)
	build_layer.visible = true


func _build_signature() -> String:
	var c: Colony = game.sim.colony
	var sig := "%d|%s|" % [c.researched.size(), str(c.cheat)]
	for t in Defs.BUILD_ORDER:
		sig += "1" if c.has_cost(Defs.BUILDINGS[t]["cost"]) else "0"
	return sig


func refresh_build_window() -> void:
	_build_sig = _build_signature()
	var keep := build_tabs.current_tab
	for ch in build_tabs.get_children():
		build_tabs.remove_child(ch)
		ch.queue_free()
	var c: Colony = game.sim.colony
	for e in Defs.ERAS.size():
		var scroll := ScrollContainer.new()
		scroll.name = Defs.ERAS[e] + ("  ●" if e == c.era_i else "")
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		build_tabs.add_child(scroll)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 8)
		scroll.add_child(col)
		var any := false
		for cat in Defs.BUILD_CATEGORIES:
			var types: Array = []
			for t in cat[1]:
				if Defs.building_era(t) == e:
					types.append(t)
			if types.is_empty():
				continue
			any = true
			col.add_child(_label(cat[0], 16, Color(1.0, 0.82, 0.48)))
			var grid := HFlowContainer.new()
			grid.add_theme_constant_override("h_separation", 8)
			grid.add_theme_constant_override("v_separation", 8)
			col.add_child(grid)
			for t in types:
				grid.add_child(_build_card(t))
		if not any:
			col.add_child(_label("Nothing new to build in this age.", 13))
	build_tabs.current_tab = clampi(keep, 0, Defs.ERAS.size() - 1)


func _build_card(type: String) -> Control:
	var c: Colony = game.sim.colony
	var d: Dictionary = Defs.BUILDINGS[type]
	var unlocked := c.is_unlocked(type)
	var afford := c.has_cost(d["cost"]) or c.cheat
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 92)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 12)
	var cost := "Free (cheats)" if c.cheat else Defs.cost_text(d["cost"])
	var state := ""
	if not unlocked:
		var tech: Dictionary = Defs.TECHS[str(d["tech"])]
		state = "Locked — research %s" % tech["name"]
	elif not afford:
		state = "Gatherers will fetch what's missing"
	b.text = "%s  (%dx%d)\n%s\n%s" % [d["name"], d["size"].x, d["size"].y, cost, state if state != "" else str(d["desc"]).substr(0, 70)]
	b.tooltip_text = "%s\n%s\nCost: %s" % [d["name"], d["desc"], cost]
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.20, 0.17, 0.12) if unlocked else Color(0.12, 0.12, 0.12)
	st.border_color = (Color(0.95, 0.8, 0.4) if afford else Color(0.55, 0.45, 0.3)) if unlocked else Color(0.3, 0.3, 0.3)
	st.set_border_width_all(2)
	st.border_width_left = 6
	st.set_corner_radius_all(5)
	st.set_content_margin_all(8)
	var st2 := st.duplicate() as StyleBoxFlat
	st2.bg_color = st.bg_color.lightened(0.1)
	for sn in ["normal", "disabled"]:
		b.add_theme_stylebox_override(sn, st)
	b.add_theme_stylebox_override("hover", st2)
	b.add_theme_stylebox_override("pressed", st2)
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85) if unlocked else Color(0.55, 0.53, 0.5))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.53, 0.5))
	b.disabled = not unlocked
	b.pressed.connect(_on_build_card.bind(type))
	return b


func _on_build_card(type: String) -> void:
	close_panel()
	game.start_build(type)
