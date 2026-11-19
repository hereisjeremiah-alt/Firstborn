class_name FlagArt
extends RefCounted
## Tribe flags: a background, a pattern in a second colour and an emblem. Drawn with plain
## canvas calls so the same flag shows up in the flag designer, on the camp's flagpole and on the
## world map. `wave` bends the cloth for flags flying on a pole.

const PATTERNS := ["Plain", "Horizontal band", "Vertical half", "Cross", "Diagonal", "Quartered", "Border", "Stripes", "Chevron"]
const EMBLEMS := ["None", "Sun", "Star", "Crescent", "Mountain", "Diamond", "Spear", "Tree", "Eye", "Wave", "Skull"]


static func default_flag() -> Dictionary:
	return {"bg": Color(0.80, 0.22, 0.18), "fg": Color(0.98, 0.84, 0.30), "pattern": 1, "emblem": 1, "em": Color(0.98, 0.95, 0.85)}


static func random_flag(rng: RandomNumberGenerator, base: Color) -> Dictionary:
	var fg := Color.from_hsv(fmod(base.h + rng.randf_range(0.3, 0.7), 1.0), rng.randf_range(0.2, 0.7), rng.randf_range(0.7, 1.0))
	if rng.randf() < 0.3:
		fg = Color(0.95, 0.93, 0.88) if base.get_luminance() < 0.6 else Color(0.12, 0.10, 0.10)
	var em := Color(0.97, 0.95, 0.9) if base.get_luminance() < 0.55 else Color(0.1, 0.08, 0.08)
	return {"bg": base, "fg": fg, "pattern": rng.randi_range(0, PATTERNS.size() - 1), "emblem": rng.randi_range(1, EMBLEMS.size() - 1), "em": em}


static func to_save(f: Dictionary) -> Dictionary:
	return {"bg": (f["bg"] as Color).to_html(), "fg": (f["fg"] as Color).to_html(), "pattern": int(f["pattern"]), "emblem": int(f["emblem"]), "em": (f["em"] as Color).to_html()}


static func from_save(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return default_flag()
	return {"bg": Color.html(str(d["bg"])), "fg": Color.html(str(d["fg"])), "pattern": int(d["pattern"]), "emblem": int(d["emblem"]), "em": Color.html(str(d["em"]))}


## Maps a point on the flat flag (0..1, 0..1) into the canvas, with optional waving.
static func _pt(r: Rect2, u: float, v: float, wave: float, t: float) -> Vector2:
	var off := sin(t * 4.0 + u * 5.0) * wave * u
	return r.position + Vector2(u * r.size.x, v * r.size.y + off)


static func _poly(ci: CanvasItem, r: Rect2, uv: Array, col: Color, wave: float, t: float) -> void:
	var pts := PackedVector2Array()
	for p in uv:
		pts.append(_pt(r, p.x, p.y, wave, t))
	# quads and triangles go straight to the GPU (no triangulation, so slivers never fail)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	ci.draw_primitive(pts, cols, PackedVector2Array())


## A rectangle on the flag split into strips so it bends with the wave.
static func _quad(ci: CanvasItem, r: Rect2, u0: float, v0: float, u1: float, v1: float, col: Color, wave: float, t: float) -> void:
	var steps := maxi(1, int(ceil((u1 - u0) * 8.0))) if wave > 0.0 else 1
	for i in steps:
		var a := u0 + (u1 - u0) * i / steps
		var b := u0 + (u1 - u0) * (i + 1) / steps
		_poly(ci, r, [Vector2(a, v0), Vector2(b, v0), Vector2(b, v1), Vector2(a, v1)], col, wave, t)


static func draw(ci: CanvasItem, r: Rect2, f: Dictionary, wave := 0.0, t := 0.0) -> void:
	var bg: Color = f.get("bg", Color.RED)
	var fg: Color = f.get("fg", Color.YELLOW)
	var em: Color = f.get("em", Color.WHITE)
	_quad(ci, r, 0, 0, 1, 1, bg, wave, t)
	match int(f.get("pattern", 0)):
		1:
			_quad(ci, r, 0, 0.36, 1, 0.64, fg, wave, t)
		2:
			_quad(ci, r, 0.5, 0, 1, 1, fg, wave, t)
		3:
			_quad(ci, r, 0, 0.4, 1, 0.6, fg, wave, t)
			_quad(ci, r, 0.3, 0, 0.42, 1, fg, wave, t)
		4:
			_poly(ci, r, [Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)], fg, wave, t)
		5:
			_quad(ci, r, 0.5, 0, 1, 0.5, fg, wave, t)
			_quad(ci, r, 0, 0.5, 0.5, 1, fg, wave, t)
		6:
			_quad(ci, r, 0, 0, 1, 0.12, fg, wave, t)
			_quad(ci, r, 0, 0.88, 1, 1, fg, wave, t)
			_quad(ci, r, 0, 0, 0.08, 1, fg, wave, t)
			_quad(ci, r, 0.92, 0, 1, 1, fg, wave, t)
		7:
			for k in 3:
				_quad(ci, r, 0, 0.1 + k * 0.3, 1, 0.25 + k * 0.3, fg, wave, t)
		8:
			_poly(ci, r, [Vector2(0, 0), Vector2(0.45, 0.5), Vector2(0, 1)], fg, wave, t)
	_emblem(ci, r, int(f.get("emblem", 0)), em, wave, t)
	var outline := PackedVector2Array([_pt(r, 0, 0, wave, t), _pt(r, 1, 0, wave, t), _pt(r, 1, 1, wave, t), _pt(r, 0, 1, wave, t), _pt(r, 0, 0, wave, t)])
	ci.draw_polyline(outline, bg.darkened(0.55), maxf(1.0, r.size.y * 0.05))


static func _emblem(ci: CanvasItem, r: Rect2, kind: int, col: Color, wave: float, t: float) -> void:
	var c := _pt(r, 0.5, 0.5, wave, t)
	var s := r.size.y * 0.28
	match kind:
		1:      # sun
			ci.draw_circle(c, s * 0.6, col)
			for k in 8:
				var a := k * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.75, c + Vector2(cos(a), sin(a)) * s * 1.1, col, maxf(1.0, s * 0.18))
		2:      # star
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI / 2.0 + k * TAU / 10.0
				var rad := s if k % 2 == 0 else s * 0.42
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			ci.draw_colored_polygon(pts, col)
		3:      # crescent
			var pts := PackedVector2Array()
			for k in 17:
				var a := PI * 0.5 + k * PI / 16.0
				pts.append(c + Vector2(cos(a), sin(a)) * s)
			for k in 17:
				var a := PI * 1.5 - k * PI / 16.0
				pts.append(c + Vector2(-s * 0.35, 0) + Vector2(cos(a) * 0.55, sin(a)) * s * 0.85)
			ci.draw_colored_polygon(pts, col)
		4:      # mountain
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.2, s * 0.8), c + Vector2(-s * 0.2, -s * 0.9), c + Vector2(s * 0.3, 0), c + Vector2(s * 0.6, -s * 0.4), c + Vector2(s * 1.2, s * 0.8)]), col)
		5:      # diamond
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)]), col)
		6:      # spear
			var w := maxf(1.0, s * 0.18)
			ci.draw_line(c + Vector2(-s * 0.8, s * 0.9), c + Vector2(s * 0.5, -s * 0.5), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.95, -s * 0.95), c + Vector2(s * 0.25, -s * 0.55), c + Vector2(s * 0.55, -s * 0.25)]), col)
		7:      # tree
			ci.draw_rect(Rect2(c + Vector2(-s * 0.12, 0), Vector2(s * 0.24, s * 0.9)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.75, s * 0.3), c + Vector2(-s * 0.75, s * 0.3)]), col)
		8:      # eye
			var pts := PackedVector2Array()
			for k in 13:
				var a := k * PI / 12.0
				pts.append(c + Vector2(-cos(a) * s, -sin(a) * s * 0.55))
			for k in 13:
				var a := k * PI / 12.0
				pts.append(c + Vector2(cos(a) * s, sin(a) * s * 0.55))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, s * 0.3, col.darkened(0.7) if col.get_luminance() > 0.4 else col.lightened(0.7))
		9:      # wave
			var w2 := maxf(1.0, s * 0.2)
			for row in 2:
				var pts := PackedVector2Array()
				for k in 13:
					var u := float(k) / 12.0
					pts.append(c + Vector2((u - 0.5) * s * 2.2, (row - 0.5) * s * 0.8 + sin(u * TAU * 1.5) * s * 0.2))
				ci.draw_polyline(pts, col, w2)
		10:     # skull
			ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.65, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.35, s * 0.25), Vector2(s * 0.7, s * 0.45)), col)
			var hole := col.darkened(0.75) if col.get_luminance() > 0.4 else col.lightened(0.75)
			ci.draw_circle(c + Vector2(-s * 0.25, -s * 0.15), s * 0.16, hole)
			ci.draw_circle(c + Vector2(s * 0.25, -s * 0.15), s * 0.16, hole)
