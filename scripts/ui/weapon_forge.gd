class_name WeaponForge
extends Control
## The Weapons window (K): design your own weapons in pixel art — a blade (or spearhead) and a
## hilt/handle — pick the material of every pixel, then have your smiths forge them at the
## Weaponsmithing Bench. Weapon types and materials unlock with Weaponsmithing I-IV.

var hud
var game
var panel: PanelContainer
var level_label: Label
var type_buttons := {}
var mat_buttons: Array = []          # [Button, code]
var blade_grid: PixelGrid
var handle_grid: PixelGrid
var preview: TextureRect
var preview_small: TextureRect
var name_edit: LineEdit
var stats: RichTextLabel
var list_box: VBoxContainer
var save_btn: Button
var mirror_box: CheckBox
var erase_box: CheckBox
var cur_type := "knife"
var cur_code := 1
var design := {}
var editing_id := ""
var _sig := ""


## A grid of big pixels you paint with the mouse (left: paint, right: erase).
class PixelGrid:
	extends Control
	signal changed
	var cols := 7
	var rows := 9
	var data: Array = []
	var cell := 16.0
	var forge: WeaponForge
	var _painting := 0

	func setup(c: int, r: int, d: Array, cell_px: float) -> void:
		cols = c
		rows = r
		data = d
		cell = cell_px
		custom_minimum_size = Vector2(cols * cell, rows * cell)
		size = custom_minimum_size
		queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
				_painting = 1 if mb.button_index == MOUSE_BUTTON_LEFT else 2
				_paint(mb.position)
				accept_event()
			elif not mb.pressed:
				_painting = 0
		elif ev is InputEventMouseMotion and _painting > 0:
			_paint((ev as InputEventMouseMotion).position)
			accept_event()

	func _paint(at: Vector2) -> void:
		var x := int(at.x / cell)
		var y := int(at.y / cell)
		if x < 0 or y < 0 or x >= cols or y >= rows:
			return
		var v := 0 if (_painting == 2 or forge.erase_box.button_pressed) else forge.cur_code
		var xs := [x]
		if forge.mirror_box.button_pressed:
			xs.append(cols - 1 - x)
		var any := false
		for xx in xs:
			if int(data[y * cols + xx]) != v:
				data[y * cols + xx] = v
				any = true
		if any:
			queue_redraw()
			changed.emit()

	func _draw() -> void:
		for y in rows:
			for x in cols:
				var r := Rect2(Vector2(x, y) * cell, Vector2(cell, cell))
				var chk := (x + y) % 2 == 0
				draw_rect(r, Color(0.20, 0.18, 0.16) if chk else Color(0.24, 0.22, 0.19))
				var v := int(data[y * cols + x])
				if v > 0:
					draw_rect(r, Smithing.color_of(v))
		for x in cols + 1:
			draw_line(Vector2(x * cell, 0), Vector2(x * cell, rows * cell), Color(0, 0, 0, 0.25), 1.0)
		for y in rows + 1:
			draw_line(Vector2(0, y * cell), Vector2(cols * cell, y * cell), Color(0, 0, 0, 0.25), 1.0)
		draw_rect(Rect2(Vector2.ZERO, Vector2(cols, rows) * cell), Color(0.85, 0.7, 0.4, 0.6), false, 1.5)


func setup(h, g) -> void:
	hud = h
	game = g
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -620
	panel.offset_right = 620
	panel.offset_top = -370
	panel.offset_bottom = 370
	add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(hud._label("Weaponsmithing", 22, Color(1.0, 0.85, 0.5)))
	level_label = hud._label("", 13, Color(0.8, 0.78, 0.7))
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(level_label)
	head.add_child(hud._button("Close  [K]", toggle, 100))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# --- left: weapon type, materials, tools
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	left.add_child(hud._label("Weapon type", 15, Color(1.0, 0.85, 0.5)))
	var tg := GridContainer.new()
	tg.columns = 2
	left.add_child(tg)
	for t in Smithing.TYPE_ORDER:
		var b: Button = hud._button(Smithing.TYPES[t]["name"], _on_type.bind(t), 120)
		b.toggle_mode = true
		tg.add_child(b)
		type_buttons[t] = b
	left.add_child(hud._label("Materials (left-click paints, right-click erases)", 12, Color(0.8, 0.78, 0.7)))
	var ms := ScrollContainer.new()
	ms.custom_minimum_size = Vector2(250, 300)
	ms.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(ms)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 2)
	ms.add_child(mv)
	for mi in Smithing.MATERIALS.size():
		var m: Dictionary = Smithing.MATERIALS[mi]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		mv.add_child(row)
		for sh in 3:
			var sb := Button.new()
			sb.custom_minimum_size = Vector2(26, 22)
			sb.focus_mode = Control.FOCUS_NONE
			sb.toggle_mode = true
			var st := StyleBoxFlat.new()
			st.bg_color = m["shades"][sh]
			st.set_border_width_all(1)
			st.border_color = Color(0, 0, 0, 0.5)
			sb.add_theme_stylebox_override("normal", st)
			var st2 := st.duplicate()
			st2.border_color = Color(1, 0.9, 0.4)
			st2.set_border_width_all(3)
			sb.add_theme_stylebox_override("pressed", st2)
			sb.add_theme_stylebox_override("hover", st)
			var st3 := st.duplicate()
			st3.bg_color = (m["shades"][sh] as Color).darkened(0.7)
			sb.add_theme_stylebox_override("disabled", st3)
			sb.pressed.connect(_on_mat.bind(Smithing.code(mi, sh)))
			row.add_child(sb)
			mat_buttons.append([sb, Smithing.code(mi, sh), mi])
		var ml: Control = hud._label(m["name"], 12)
		ml.name = "mat_label_%d" % mi
		row.add_child(ml)
	var tools := HBoxContainer.new()
	left.add_child(tools)
	mirror_box = CheckBox.new()
	mirror_box.text = "Mirror"
	mirror_box.button_pressed = true
	mirror_box.focus_mode = Control.FOCUS_NONE
	mirror_box.tooltip_text = "Paint both halves at once (symmetric weapons)."
	tools.add_child(mirror_box)
	erase_box = CheckBox.new()
	erase_box.text = "Eraser"
	erase_box.focus_mode = Control.FOCUS_NONE
	tools.add_child(erase_box)
	var tools2 := HBoxContainer.new()
	left.add_child(tools2)
	tools2.add_child(hud._button("Clear blade", _on_clear.bind("blade")))
	tools2.add_child(hud._button("Clear handle", _on_clear.bind("handle")))
	left.add_child(hud._button("Start from a simple template", _on_template))

	# --- middle: the two parts and the preview
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", 18)
	parts.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(parts)
	var bv := VBoxContainer.new()
	parts.add_child(bv)
	bv.add_child(hud._label("Blade / head", 14, Color(1.0, 0.85, 0.5)))
	blade_grid = PixelGrid.new()
	blade_grid.forge = self
	blade_grid.changed.connect(_on_changed)
	bv.add_child(blade_grid)
	var hv := VBoxContainer.new()
	parts.add_child(hv)
	hv.add_child(hud._label("Hilt / handle", 14, Color(1.0, 0.85, 0.5)))
	handle_grid = PixelGrid.new()
	handle_grid.forge = self
	handle_grid.changed.connect(_on_changed)
	hv.add_child(handle_grid)
	var pv := VBoxContainer.new()
	parts.add_child(pv)
	pv.add_child(hud._label("Finished weapon", 14, Color(1.0, 0.85, 0.5)))
	preview = TextureRect.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(120, 470)
	pv.add_child(preview)
	pv.add_child(hud._label("Actual size:", 12, Color(0.8, 0.78, 0.7)))
	preview_small = TextureRect.new()
	preview_small.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_small.stretch_mode = TextureRect.STRETCH_KEEP
	pv.add_child(preview_small)

	# --- right: name, stats, forging, saved designs
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	right.add_theme_constant_override("separation", 5)
	body.add_child(right)
	right.add_child(hud._label("Name", 14, Color(1.0, 0.85, 0.5)))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "(named after its material)"
	name_edit.max_length = 28
	right.add_child(name_edit)
	stats = RichTextLabel.new()
	stats.bbcode_enabled = true
	stats.fit_content = true
	stats.scroll_active = false
	stats.custom_minimum_size = Vector2(330, 150)
	right.add_child(stats)
	var bh := HBoxContainer.new()
	right.add_child(bh)
	save_btn = hud._button("Save design", _on_save)
	bh.add_child(save_btn)
	bh.add_child(hud._button("Save as new", _on_save_new))
	bh.add_child(hud._button("New", _on_new))
	right.add_child(HSeparator.new())
	right.add_child(hud._label("Your designs", 15, Color(1.0, 0.85, 0.5)))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.custom_minimum_size = Vector2(330, 260)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(ls)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	ls.add_child(list_box)
	_new_design("knife")


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_locks()
		_refresh_list()
		_update_stats()


func _process(_d: float) -> void:
	if not visible:
		return
	var c: Colony = game.sim.colony
	var sig := "%d|%d|%d" % [Smithing.level(c), c.weapon_orders.size(), c.weapons_in_stock()]
	if sig != _sig:
		_sig = sig
		_refresh_locks()
		_refresh_list()
		_update_stats()


func _level() -> int:
	return Smithing.level(game.sim.colony)


func _refresh_locks() -> void:
	var lv := _level()
	if lv == 0:
		level_label.text = "   Research the Weaponsmithing Bench (Caveman Age, Military row) to start designing weapons."
	else:
		level_label.text = "   %s — custom weapons are used in fights between people, not for hunting." % Smithing.LEVEL_NAMES[lv - 1]
	for t in type_buttons.keys():
		var tl := int(Smithing.TYPES[t]["level"])
		var b: Button = type_buttons[t]
		b.disabled = tl > lv
		b.tooltip_text = Smithing.TYPES[t]["desc"] + ("" if tl <= lv else "\nNeeds %s." % Smithing.LEVEL_NAMES[tl - 1])
		b.set_pressed_no_signal(t == cur_type)
	for e in mat_buttons:
		var m: Dictionary = Smithing.MATERIALS[int(e[2])]
		var ml := int(m["level"])
		var b2: Button = e[0]
		b2.disabled = ml > lv
		b2.tooltip_text = "%s%s" % [m["name"], "" if ml <= lv else " — needs %s" % Smithing.LEVEL_NAMES[ml - 1]]
		b2.set_pressed_no_signal(int(e[1]) == cur_code)


func _new_design(t: String) -> void:
	cur_type = t
	var ty: Dictionary = Smithing.TYPES[t]
	design = {"name": "", "type": t, "blade": Smithing.empty_part(ty["blade"]), "handle": Smithing.empty_part(ty["handle"])}
	editing_id = ""
	name_edit.text = ""
	_bind_grids()


func _bind_grids() -> void:
	var ty: Dictionary = Smithing.TYPES[design["type"]]
	var bs: Vector2i = ty["blade"]
	var hs: Vector2i = ty["handle"]
	var cell := clampf(440.0 / maxf(bs.y, hs.y), 12.0, 26.0)
	blade_grid.setup(bs.x, bs.y, design["blade"], cell)
	handle_grid.setup(hs.x, hs.y, design["handle"], cell)
	save_btn.text = "Save changes" if editing_id != "" else "Save design"
	_on_changed()


func _on_type(t: String) -> void:
	if t == cur_type and editing_id == "":
		_refresh_locks()
		return
	_new_design(t)
	_refresh_locks()


func _on_mat(code_v: int) -> void:
	cur_code = code_v
	erase_box.button_pressed = false
	_refresh_locks()


func _on_clear(part: String) -> void:
	var arr: Array = design[part]
	arr.fill(0)
	blade_grid.queue_redraw()
	handle_grid.queue_redraw()
	_on_changed()


func _on_template() -> void:
	var nm := name_edit.text
	var st := Smithing.starter(cur_type)
	var lv := _level()
	# keep the template inside what this level may use
	for part in ["blade", "handle"]:
		var arr: Array = st[part]
		for i in arr.size():
			var v := int(arr[i])
			if v > 0 and int(Smithing.mat_of(v)["level"]) > maxi(1, lv):
				arr[i] = Smithing.code(0, (v - 1) % 3)
	design["blade"] = st["blade"]
	design["handle"] = st["handle"]
	name_edit.text = nm
	_bind_grids()


func _on_changed() -> void:
	var img := Smithing.image_of(design)
	var tex := ImageTexture.create_from_image(img)
	preview.texture = tex
	preview_small.texture = tex
	_update_stats()


func _update_stats() -> void:
	if stats == null or design.is_empty():
		return
	var ev := Smithing.evaluate(design)
	var c: Colony = game.sim.colony
	var s := "[b]%s[/b]\n" % Smithing.TYPES[design["type"]]["name"]
	s += "Damage: [color=#ffd27a]%.1f[/color]   Reach: %.2f tiles\n" % [float(ev["dmg"]), float(ev["range"])]
	s += "Forging time: %.1f hours\n" % float(ev["hours"])
	s += "Materials: %s\n" % (Defs.cost_text(ev["cost"]) if not ev["cost"].is_empty() else "none")
	var lv := _level()
	if int(ev["level"]) > lv:
		s += "[color=#ff8a7a]Needs %s.[/color]\n" % Smithing.LEVEL_NAMES[int(ev["level"]) - 1]
	if not ev["ok"]:
		s += "[color=#ff8a7a]%s[/color]\n" % ev["why"]
	var best := Defs.best_weapon_for("warrior", c.era_i)
	if best != "":
		s += "[color=#a09a88]For comparison: %s, %.0f damage.[/color]\n" % [Defs.weapon(best)["name"], float(Defs.weapon(best)["dmg"])]
	stats.text = s


func _can_save(ev: Dictionary) -> String:
	if _level() == 0:
		return "Research the Weaponsmithing Bench first."
	if not ev["ok"]:
		return str(ev["why"])
	if int(ev["level"]) > _level():
		return "This design needs %s." % Smithing.LEVEL_NAMES[int(ev["level"]) - 1]
	return ""


func _on_save() -> void:
	_save(editing_id)


func _on_save_new() -> void:
	_save("")


func _save(id: String) -> void:
	var ev := Smithing.evaluate(design)
	var why := _can_save(ev)
	if why != "":
		hud.push_event(why, "warn")
		return
	design["name"] = name_edit.text
	var nid := Smithing.save_design(game.sim, design, id)
	editing_id = nid
	design = (game.sim.custom_weapons[nid] as Dictionary).duplicate(true)
	name_edit.text = design["name"]
	_bind_grids()
	_refresh_list()
	hud.push_event("Saved the design \"%s\". Press Forge to have your smiths make it." % design["name"], "good")


func _on_new() -> void:
	_new_design(cur_type)
	_refresh_locks()


func _on_edit(id: String) -> void:
	design = (game.sim.custom_weapons[id] as Dictionary).duplicate(true)
	editing_id = id
	cur_type = design["type"]
	name_edit.text = design["name"]
	_bind_grids()
	_refresh_locks()


func _on_forge(id: String, n: int) -> void:
	var c: Colony = game.sim.colony
	for k in n:
		c.weapon_orders.append(id)
	var where := ""
	if not (c.has_built("smithing_bench") or c.has_built("blacksmith")):
		where = " Build a Weaponsmithing Bench first."
	elif c.living().filter(func(q): return q.job == "smith").is_empty():
		where = " Someone needs the Smith job (Jobs, J)."
	hud.push_event("Queued %d × %s.%s" % [n, Defs.weapon(id)["name"], where], "info")
	_refresh_list()


func _on_delete(id: String) -> void:
	Smithing.delete_design(game.sim, id)
	if editing_id == id:
		editing_id = ""
		save_btn.text = "Save design"
	_refresh_list()


func _refresh_list() -> void:
	if list_box == null:
		return
	for ch in list_box.get_children():
		list_box.remove_child(ch)
		ch.queue_free()
	var sim: Sim = game.sim
	var c: Colony = sim.colony
	if sim.custom_weapons.is_empty():
		list_box.add_child(hud._label("No designs yet. Draw a blade and a handle, then press Save design.", 12, Color(0.75, 0.72, 0.62)))
		return
	for id in sim.custom_weapons.keys():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		list_box.add_child(row)
		var tr := TextureRect.new()
		tr.texture = Smithing.texture(sim, id)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(22, 56)
		row.add_child(tr)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var wd: Dictionary = Defs.weapon(id)
		var queued := c.weapon_orders.filter(func(w): return str(w) == id).size()
		info.add_child(hud._label("%s  (%.0f dmg)" % [wd["name"], float(wd["dmg"])], 13))
		info.add_child(hud._label("In stock %d · queued %d · %s" % [int(c.count(id)), queued, Defs.cost_text(wd["cost"])], 11, Color(0.75, 0.72, 0.62)))
		var bb := HBoxContainer.new()
		info.add_child(bb)
		bb.add_child(hud._button("Edit", _on_edit.bind(id)))
		bb.add_child(hud._button("Forge 1", _on_forge.bind(id, 1)))
		bb.add_child(hud._button("Forge 5", _on_forge.bind(id, 5)))
		bb.add_child(hud._button("Delete", _on_delete.bind(id)))
