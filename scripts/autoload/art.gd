extends Node
## Procedural pixel-art generator. Every texture in the game is drawn here at startup,
## so the project has no external art dependencies (swap in real sprites later if you like).

var res_tex := {}          # key (int R or String) -> Texture2D
var trees := {}            # kind -> Array of top-down tree textures (variants)
var icons := {}            # name -> Texture2D
var light_tex: Texture2D
var _rng := RandomNumberGenerator.new()

const VARIANTS := 4


func _ready() -> void:
	_rng.seed = 1337
	_make_resources()
	_make_trees()
	_make_icons()
	light_tex = _make_light()


# ------------------------------------------------------------------ helpers
func _img(w: int, h: int) -> Image:
	var im := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im


func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		if c.a >= 1.0:
			im.set_pixel(x, y, c)
		else:
			im.set_pixel(x, y, im.get_pixel(x, y).blend(c))


func _circle(im: Image, cx: float, cy: float, r: float, c: Color, shade := 0.0) -> void:
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			if dx * dx + dy * dy <= r * r:
				var col := c
				if shade != 0.0:
					# light from top-left
					var k := clampf((dx + dy) / (r * 2.0), -0.5, 0.5)
					col = c.darkened(k * shade) if k > 0.0 else c.lightened(-k * shade)
				_px(im, x, y, col)


func _rect(im: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(im, x, y, c)


func _line(im: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		_px(im, roundi(p.x), roundi(p.y), c)


func _tex(im: Image) -> ImageTexture:
	return ImageTexture.create_from_image(im)


# ------------------------------------------------------------------ resources
func _make_resources() -> void:
	res_tex[Defs.R.TREE] = _tree(Color(0.20, 0.52, 0.20), false)
	res_tex["tree_bare"] = _tree(Color(0.0, 0.0, 0.0, 0.0), true)
	res_tex["tree_fall"] = _tree(Color(0.78, 0.45, 0.16), false)
	res_tex[Defs.R.PINE] = _pine(Color(0.13, 0.40, 0.24), false)
	res_tex[Defs.R.SNOW_PINE] = _pine(Color(0.13, 0.36, 0.26), true)
	res_tex["pine_snow"] = res_tex[Defs.R.SNOW_PINE]
	res_tex[Defs.R.PALM] = _palm()
	res_tex[Defs.R.JUNGLE_TREE] = _jungle()
	res_tex[Defs.R.BERRY_BUSH] = _bush(Color(0.24, 0.50, 0.22), Color(0.80, 0.12, 0.22))
	res_tex["bush_empty"] = _bush(Color(0.30, 0.46, 0.22), Color(0, 0, 0, 0))
	res_tex[Defs.R.FRUIT_BUSH] = _bush(Color(0.12, 0.48, 0.24), Color(1.0, 0.62, 0.10))
	res_tex["fruit_empty"] = _bush(Color(0.14, 0.44, 0.24), Color(0, 0, 0, 0))
	res_tex[Defs.R.MUSHROOM] = _mushroom()
	res_tex[Defs.R.STICKS] = _sticks()
	res_tex[Defs.R.SMALL_STONES] = _stones()
	res_tex[Defs.R.LARGE_STONE] = _rock(5.0, Color(0.55, 0.55, 0.56), Color(0, 0, 0, 0))
	res_tex[Defs.R.BOULDER] = _rock(7.0, Color(0.50, 0.49, 0.48), Color(0, 0, 0, 0))
	res_tex[Defs.R.GRASS] = _grass()
	res_tex[Defs.R.COPPER_ORE] = _rock(6.0, Color(0.48, 0.45, 0.42), Color(0.86, 0.48, 0.22))
	res_tex[Defs.R.TIN_ORE] = _rock(6.0, Color(0.48, 0.47, 0.46), Color(0.78, 0.82, 0.88))
	res_tex[Defs.R.CACTUS] = _cactus()
	res_tex[Defs.R.SHRUB] = _shrub()
	res_tex[Defs.R.REEDS] = _reeds()
	res_tex[Defs.R.IRON_ORE] = _rock(6.0, Color(0.45, 0.42, 0.40), Color(0.62, 0.26, 0.20))


func _tree(leaf: Color, bare: bool) -> ImageTexture:
	var im := _img(16, 24)
	var trunk := Color(0.40, 0.27, 0.16)
	_rect(im, 7, 13, 3, 10, trunk)
	_px(im, 6, 22, trunk)
	_px(im, 10, 22, trunk)
	if bare:
		_line(im, Vector2(8, 14), Vector2(3, 7), trunk)
		_line(im, Vector2(8, 13), Vector2(13, 6), trunk)
		_line(im, Vector2(8, 12), Vector2(8, 3), trunk)
		_line(im, Vector2(5, 10), Vector2(2, 9), trunk)
		return _tex(im)
	_circle(im, 5.5, 10.0, 4.5, leaf.darkened(0.12), 0.5)
	_circle(im, 11.0, 10.0, 4.5, leaf.darkened(0.08), 0.5)
	_circle(im, 8.0, 6.0, 5.5, leaf, 0.6)
	for k in 5:
		_px(im, _rng.randi_range(4, 12), _rng.randi_range(3, 12), leaf.lightened(0.25))
	return _tex(im)


func _pine(leaf: Color, snow: bool) -> ImageTexture:
	var im := _img(16, 24)
	_rect(im, 7, 18, 2, 5, Color(0.36, 0.24, 0.14))
	for layer in 4:
		var top := 2 + layer * 4
		var half := 2 + layer * 1.6
		for y in range(top, top + 6):
			var wdt := lerpf(0.5, half, float(y - top) / 5.0)
			for x in range(floori(8.0 - wdt), ceili(8.0 + wdt)):
				var c := leaf.darkened(0.15) if x >= 8 else leaf
				_px(im, x, y, c)
		if snow:
			for x in range(floori(8.0 - half * 0.7), ceili(8.0 + half * 0.5)):
				_px(im, x, top + 2 + (x % 2), Color(0.95, 0.97, 1.0))
	if snow:
		_px(im, 8, 2, Color(0.95, 0.97, 1.0))
		_px(im, 7, 3, Color(0.95, 0.97, 1.0))
	return _tex(im)


func _palm() -> ImageTexture:
	var im := _img(16, 24)
	var trunk := Color(0.55, 0.40, 0.24)
	for y in range(8, 23):
		var x := 8 + int(sin(y * 0.25) * 1.5)
		_px(im, x, y, trunk)
		_px(im, x + 1, y, trunk.darkened(0.2))
	var leaf := Color(0.20, 0.58, 0.22)
	for a in [-2.6, -2.0, -1.2, -0.6, 0.0]:
		var dir := Vector2(cos(a), sin(a) * 0.6)
		_line(im, Vector2(8, 8), Vector2(8, 8) + dir * 7.0 + Vector2(0, 2), leaf)
		_line(im, Vector2(8, 8), Vector2(8, 8) + Vector2(-dir.x, dir.y) * 7.0 + Vector2(0, 2), leaf.darkened(0.1))
	_circle(im, 8, 9, 1.5, Color(0.45, 0.30, 0.12))
	return _tex(im)


func _jungle() -> ImageTexture:
	var im := _img(16, 24)
	_rect(im, 7, 12, 3, 11, Color(0.33, 0.24, 0.15))
	var leaf := Color(0.08, 0.40, 0.18)
	_circle(im, 4.0, 9.0, 4.5, leaf.darkened(0.15), 0.5)
	_circle(im, 12.0, 9.0, 4.5, leaf.darkened(0.1), 0.5)
	_circle(im, 8.0, 5.5, 5.5, leaf, 0.6)
	_line(im, Vector2(4, 12), Vector2(4, 17), Color(0.2, 0.5, 0.2))
	_line(im, Vector2(12, 12), Vector2(12, 16), Color(0.2, 0.5, 0.2))
	for k in 4:
		_px(im, _rng.randi_range(3, 13), _rng.randi_range(2, 11), Color(0.9, 0.3, 0.5))
	return _tex(im)


func _bush(leaf: Color, berry: Color) -> ImageTexture:
	var im := _img(16, 16)
	_circle(im, 5.0, 10.0, 4.0, leaf.darkened(0.1), 0.5)
	_circle(im, 11.0, 10.0, 4.0, leaf.darkened(0.05), 0.5)
	_circle(im, 8.0, 7.5, 4.5, leaf, 0.6)
	if berry.a > 0.0:
		for p in [Vector2(5, 8), Vector2(9, 6), Vector2(11, 10), Vector2(7, 11), Vector2(12, 7), Vector2(4, 11)]:
			_px(im, int(p.x), int(p.y), berry)
			_px(im, int(p.x) + 1, int(p.y), berry.darkened(0.2))
	return _tex(im)


func _mushroom() -> ImageTexture:
	var im := _img(16, 16)
	for p in [Vector2(5, 10), Vector2(10, 12), Vector2(11, 7)]:
		_rect(im, int(p.x) - 1, int(p.y), 2, 3, Color(0.92, 0.88, 0.78))
		_circle(im, p.x, p.y, 2.6, Color(0.78, 0.18, 0.14), 0.4)
		_px(im, int(p.x) - 1, int(p.y) - 1, Color(1, 1, 1))
	return _tex(im)


func _cactus() -> ImageTexture:
	var im := _img(16, 16)
	var g := Color(0.36, 0.56, 0.30)
	_circle(im, 9, 13, 3.0, Color(0, 0, 0, 0.2))
	_circle(im, 8, 8, 4.0, g, 0.5)
	_circle(im, 4, 6, 2.5, g.darkened(0.1), 0.5)
	_circle(im, 12, 5, 2.5, g.lightened(0.05), 0.5)
	for p in [Vector2(4, 4), Vector2(12, 3), Vector2(8, 5)]:
		_px(im, int(p.x), int(p.y), Color(0.9, 0.3, 0.45))
	for k in 6:
		_px(im, _rng.randi_range(5, 11), _rng.randi_range(5, 11), Color(0.9, 0.9, 0.75))
	return _tex(im)


func _shrub() -> ImageTexture:
	var im := _img(16, 16)
	var c := Color(0.52, 0.48, 0.30)
	_circle(im, 9, 11, 4.5, Color(0, 0, 0, 0.18))
	for k in 5:
		_circle(im, _rng.randf_range(5, 11), _rng.randf_range(6, 10), _rng.randf_range(2.0, 3.0), c.darkened(_rng.randf_range(0.0, 0.25)))
	for k in 5:
		_line(im, Vector2(8, 9), Vector2(_rng.randi_range(3, 13), _rng.randi_range(4, 13)), Color(0.40, 0.30, 0.18))
	return _tex(im)


func _reeds() -> ImageTexture:
	var im := _img(16, 16)
	for k in 9:
		var x := _rng.randi_range(2, 13)
		var c := Color(0.42, 0.55, 0.28).darkened(_rng.randf_range(0.0, 0.25))
		_line(im, Vector2(x, 15), Vector2(x + _rng.randi_range(-2, 2), _rng.randi_range(3, 8)), c)
		if k % 3 == 0:
			_rect(im, x, _rng.randi_range(3, 6), 1, 3, Color(0.45, 0.30, 0.18))
	return _tex(im)


func _sticks() -> ImageTexture:
	var im := _img(16, 16)
	var c := Color(0.48, 0.33, 0.18)
	_line(im, Vector2(3, 11), Vector2(12, 8), c)
	_line(im, Vector2(4, 7), Vector2(11, 12), c.darkened(0.15))
	_line(im, Vector2(6, 13), Vector2(13, 12), c.lightened(0.1))
	_px(im, 8, 9, Color(0.3, 0.55, 0.2))
	return _tex(im)


func _stones() -> ImageTexture:
	var im := _img(16, 16)
	_circle(im, 5, 10, 2.0, Color(0.58, 0.58, 0.58), 0.5)
	_circle(im, 10, 11, 2.4, Color(0.50, 0.50, 0.52), 0.5)
	_circle(im, 9, 6, 1.6, Color(0.62, 0.60, 0.58), 0.5)
	return _tex(im)


func _rock(r: float, c: Color, ore: Color) -> ImageTexture:
	var im := _img(16, 16)
	_circle(im, 8.0, 15.0 - r, r, c, 0.7)
	_circle(im, 8.0 + r * 0.3, 15.0 - r * 0.6, r * 0.7, c.darkened(0.08), 0.6)
	if ore.a > 0.0:
		for k in 6:
			_px(im, _rng.randi_range(int(8 - r * 0.6), int(8 + r * 0.6)), _rng.randi_range(int(15 - r * 1.6), 13), ore)
	return _tex(im)


func _grass() -> ImageTexture:
	var im := _img(16, 16)
	var c := Color(0.48, 0.70, 0.28)
	for k in 7:
		var x := _rng.randi_range(2, 13)
		var hgt := _rng.randi_range(4, 8)
		_line(im, Vector2(x, 14), Vector2(x + _rng.randi_range(-2, 2), 14 - hgt), c.darkened(_rng.randf_range(0.0, 0.25)))
	return _tex(im)


# ------------------------------------------------------------------ top-down trees
func _make_trees() -> void:
	trees["oak"] = []
	trees["oak_fall"] = []
	trees["oak_bare"] = []
	trees["pine"] = []
	trees["pine_snow"] = []
	trees["palm"] = []
	trees["jungle"] = []
	trees["acacia"] = []
	trees["juniper"] = []
	for v in 4:
		var seed_v := 100 + v
		trees["oak"].append(_canopy(Color(0.22, 0.48, 0.20), seed_v, 26, false))
		trees["oak_fall"].append(_canopy([Color(0.80, 0.46, 0.14), Color(0.74, 0.30, 0.12), Color(0.86, 0.62, 0.18), Color(0.62, 0.40, 0.14)][v], seed_v, 26, false))
		trees["oak_bare"].append(_bare_top(seed_v))
		trees["pine"].append(_conifer(Color(0.12, 0.36, 0.22), seed_v, false))
		trees["pine_snow"].append(_conifer(Color(0.12, 0.33, 0.24), seed_v, true))
		trees["palm"].append(_palm_top(seed_v))
		trees["jungle"].append(_canopy(Color(0.10, 0.40, 0.18), seed_v + 50, 30, true))
		trees["acacia"].append(_acacia(seed_v))
		trees["juniper"].append(_conifer(Color(0.24, 0.36, 0.26), seed_v + 9, false))


## Round leafy crown seen from above, with a soft shadow to the lower right.
func _canopy(leaf: Color, seed_v: int, size: int, jungle: bool) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var im := _img(size, size)
	var c := size * 0.5 - 1.5
	var rad := size * 0.30
	_circle(im, c + 2.5, c + 3.0, rad + 1.0, Color(0, 0, 0, 0.28))
	var blobs: Array = []
	for k in (6 if jungle else 5):
		var ang := r.randf() * TAU
		var dist := r.randf_range(0.0, rad * 0.55)
		blobs.append([c + cos(ang) * dist, c + sin(ang) * dist, rad * r.randf_range(0.55, 0.8)])
	for b in blobs:
		_circle(im, b[0], b[1], b[2] + 0.8, leaf.darkened(0.35))
	for b in blobs:
		_circle(im, b[0], b[1], b[2], leaf, 0.7)
	# leafy texture and sunlit tops
	for k in size * 2:
		var x := r.randi_range(2, size - 3)
		var y := r.randi_range(2, size - 3)
		if im.get_pixel(x, y).a > 0.9 and im.get_pixel(x, y) != Color(0, 0, 0, 0.28):
			var lit := (x + y) < size
			_px(im, x, y, leaf.lightened(0.22) if lit else leaf.darkened(0.18))
	if jungle:
		for k in 5:
			var x := r.randi_range(4, size - 5)
			var y := r.randi_range(4, size - 5)
			if im.get_pixel(x, y).a > 0.9:
				_px(im, x, y, [Color(0.95, 0.35, 0.55), Color(1.0, 0.8, 0.2)][k % 2])
	return _tex(im)


## Flat-topped savanna tree: a wide, thin, olive crown.
func _acacia(seed_v: int) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var im := _img(30, 30)
	var leaf := Color(0.48, 0.56, 0.24)
	_circle(im, 17.5, 18.0, 9.0, Color(0, 0, 0, 0.22))
	for k in 7:
		var ang := r.randf() * TAU
		var d := r.randf_range(2.0, 8.0)
		_circle(im, 14.5 + cos(ang) * d, 14.5 + sin(ang) * d * 0.8, r.randf_range(3.5, 5.0), leaf.darkened(0.3))
	for k in 7:
		var ang := r.randf() * TAU
		var d := r.randf_range(1.0, 7.0)
		_circle(im, 14.0 + cos(ang) * d, 14.0 + sin(ang) * d * 0.8, r.randf_range(3.0, 4.5), leaf, 0.5)
	for k in 30:
		var x := r.randi_range(4, 25)
		var y := r.randi_range(4, 25)
		if im.get_pixel(x, y).a > 0.9:
			_px(im, x, y, leaf.lightened(0.2) if (x + y) < 28 else leaf.darkened(0.15))
	return _tex(im)


## Leafless winter tree: branches spreading from the trunk.
func _bare_top(seed_v: int) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var im := _img(26, 26)
	var c := Vector2(12.5, 12.5)
	var wood := Color(0.36, 0.25, 0.16)
	_circle(im, 15, 16, 6.0, Color(0, 0, 0, 0.18))
	for k in 7:
		var ang := k * TAU / 7.0 + r.randf_range(-0.3, 0.3)
		var len := r.randf_range(6.0, 10.0)
		var end := c + Vector2(cos(ang), sin(ang)) * len
		_line(im, c, end, wood)
		var mid := c + Vector2(cos(ang), sin(ang)) * len * 0.6
		_line(im, mid, mid + Vector2(cos(ang + 0.7), sin(ang + 0.7)) * 3.0, wood.lightened(0.1))
	_circle(im, c.x, c.y, 2.0, wood.darkened(0.2))
	return _tex(im)


## Conifer from above: a dark star of layered needles.
func _conifer(leaf: Color, seed_v: int, snow: bool) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var im := _img(22, 22)
	var c := Vector2(10.5, 10.5)
	_circle(im, c.x + 2.5, c.y + 3.0, 8.0, Color(0, 0, 0, 0.28))
	var layers := [[9.0, leaf.darkened(0.25)], [6.5, leaf], [4.0, leaf.lightened(0.12)], [1.8, leaf.lightened(0.25)]]
	for L in layers:
		var rad: float = L[0]
		var col: Color = L[1]
		var spikes := 9
		var off := r.randf() * TAU
		for y in 22:
			for x in 22:
				var d := Vector2(x + 0.5, y + 0.5) - c
				var ang := atan2(d.y, d.x) + off
				var edge := rad * (0.78 + 0.22 * absf(cos(ang * spikes * 0.5)))
				if d.length() <= edge:
					_px(im, x, y, col)
	if snow:
		for k in 26:
			var a := r.randf() * TAU
			var dd := r.randf_range(0.0, 8.0)
			_px(im, int(c.x + cos(a) * dd), int(c.y + sin(a) * dd), Color(0.95, 0.97, 1.0))
	return _tex(im)


## Palm from above: a star of fronds.
func _palm_top(seed_v: int) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var im := _img(24, 24)
	var c := Vector2(11.5, 11.5)
	_circle(im, c.x + 3, c.y + 3, 6.0, Color(0, 0, 0, 0.2))
	var leaf := Color(0.24, 0.58, 0.24)
	for k in 7:
		var ang := k * TAU / 7.0 + r.randf_range(-0.2, 0.2)
		var dir := Vector2(cos(ang), sin(ang))
		for st in 10:
			var p := c + dir * float(st)
			_px(im, int(p.x), int(p.y), leaf.darkened(0.15))
			var side := Vector2(-dir.y, dir.x) * (1.5 if st > 2 else 0.0)
			_px(im, int(p.x + side.x), int(p.y + side.y), leaf)
			_px(im, int(p.x - side.x), int(p.y - side.y), leaf.lightened(0.1))
	_circle(im, c.x, c.y, 1.8, Color(0.45, 0.32, 0.15))
	return _tex(im)


# ------------------------------------------------------------------ icons
func _make_icons() -> void:
	var im := _img(16, 16)
	_circle(im, 8, 5, 3.0, Color(0.95, 0.80, 0.62))
	_circle(im, 8, 14, 5.0, Color(0.55, 0.38, 0.22))
	icons["pop"] = _tex(im)
	# Talents (money): a stamped gold coin with a square hole
	im = _img(16, 16)
	_circle(im, 8.5, 9.0, 6.6, Color(0.45, 0.30, 0.05))
	_circle(im, 8.0, 8.0, 6.5, Color(0.80, 0.60, 0.15), 0.5)
	_circle(im, 7.6, 7.6, 5.4, Color(0.98, 0.80, 0.30), 0.5)
	_circle(im, 6.6, 6.4, 2.2, Color(1.0, 0.94, 0.62), 0.5)
	_rect(im, 7, 7, 2, 2, Color(0.40, 0.26, 0.05))
	for p in [Vector2i(8, 3), Vector2i(12, 8), Vector2i(8, 12), Vector2i(3, 8)]:
		_px(im, p.x, p.y, Color(0.70, 0.50, 0.10))
	icons["money"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 6, 9, 3.2, Color(0.82, 0.14, 0.22), 0.4)
	_circle(im, 10.5, 10, 3.2, Color(0.70, 0.10, 0.20), 0.4)
	_line(im, Vector2(8, 3), Vector2(8, 7), Color(0.3, 0.55, 0.2))
	icons["food"] = _tex(im)
	im = _img(16, 16)
	for y in range(2, 15):
		var wdt := 0.0 if y < 5 else minf(5.0, (y - 4) * 1.4)
		if y > 11:
			wdt = 5.0 - (y - 11) * 1.3
		for x in range(floori(8 - wdt), ceili(8 + wdt) + 1):
			_px(im, x, y, Color(0.30, 0.62, 0.95))
	_px(im, 8, 2, Color(0.3, 0.62, 0.95))
	_px(im, 6, 9, Color(0.8, 0.9, 1.0))
	icons["water"] = _tex(im)
	im = _img(16, 16)
	_rect(im, 2, 6, 12, 5, Color(0.55, 0.36, 0.18))
	_circle(im, 13, 8.5, 2.5, Color(0.80, 0.62, 0.38))
	icons["wood"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 9, 5.0, Color(0.60, 0.60, 0.62), 0.7)
	icons["stone"] = _tex(im)
	im = _img(16, 16)
	_rect(im, 7, 2, 3, 10, Color(0.9, 0.9, 0.9))
	_circle(im, 8.5, 12.5, 3.0, Color(0.9, 0.25, 0.2))
	_rect(im, 8, 6, 1, 6, Color(0.9, 0.25, 0.2))
	icons["temp"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 5.5, 6.5, 3.2, Color(0.9, 0.2, 0.3))
	_circle(im, 10.5, 6.5, 3.2, Color(0.9, 0.2, 0.3))
	for y in range(7, 14):
		var wdt := 7.0 - (y - 7) * 1.1
		for x in range(floori(8 - wdt), ceili(8 + wdt)):
			_px(im, x, y, Color(0.9, 0.2, 0.3))
	icons["health"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 8, 6.0, Color(0.98, 0.85, 0.30))
	icons["sun"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 8, 6.0, Color(0.90, 0.92, 1.0))
	_circle(im, 10.5, 6.5, 5.0, Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var dx := x - 10.5
			var dy := y - 6.5
			if dx * dx + dy * dy < 22.0:
				im.set_pixel(x, y, Color(0, 0, 0, 0))
	icons["moon"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 8, 5.0, Color(0.35, 0.72, 0.30), 0.4)
	_line(im, Vector2(4, 12), Vector2(12, 4), Color(0.2, 0.45, 0.18))
	icons["spring"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 8, 4.0, Color(1.0, 0.75, 0.2))
	for a in 8:
		var d := Vector2(cos(a * PI / 4.0), sin(a * PI / 4.0))
		_line(im, Vector2(8, 8) + d * 5.0, Vector2(8, 8) + d * 7.0, Color(1.0, 0.75, 0.2))
	icons["summer"] = _tex(im)
	im = _img(16, 16)
	_circle(im, 8, 8, 5.0, Color(0.85, 0.42, 0.12), 0.4)
	_line(im, Vector2(4, 12), Vector2(12, 4), Color(0.5, 0.25, 0.1))
	icons["fall"] = _tex(im)
	im = _img(16, 16)
	for a in 3:
		var d := Vector2(cos(a * PI / 3.0), sin(a * PI / 3.0)) * 6.0
		_line(im, Vector2(8, 8) - d, Vector2(8, 8) + d, Color(0.75, 0.88, 1.0))
	icons["winter"] = _tex(im)
	im = _img(16, 16)
	_line(im, Vector2(3, 12), Vector2(12, 4), Color(0.5, 0.34, 0.18))
	_line(im, Vector2(4, 13), Vector2(13, 6), Color(0.45, 0.30, 0.15))
	icons["sticks"] = _tex(im)


func _make_light() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt
