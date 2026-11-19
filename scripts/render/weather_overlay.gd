class_name WeatherOverlay
extends Control
## Screen-space rain, snow, storm darkening and lightning.

var game: Node
var drops: Array = []     # [Vector2 pos, float speed, float len]
var flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()


func _process(delta: float) -> void:
	if game == null or game.sim == null:
		return
	var sim: Sim = game.sim
	var st := sim.weather.state
	var want := 0
	match st:
		WeatherSystem.W.RAIN:
			want = 220
		WeatherSystem.W.STORM:
			want = 420
		WeatherSystem.W.SNOW:
			want = 260
	var sz := size
	while drops.size() < want:
		drops.append([Vector2(_rng.randf() * sz.x, _rng.randf() * sz.y), _rng.randf_range(0.7, 1.3), _rng.randf_range(6.0, 12.0)])
	while drops.size() > want:
		drops.pop_back()
	var snow := st == WeatherSystem.W.SNOW
	var spd: float = game.speed if not game.paused else 0.0
	var wind := 160.0 if st == WeatherSystem.W.STORM else 60.0
	for d in drops:
		var v: Vector2 = Vector2(wind * 0.25, 60.0) if snow else Vector2(wind, 700.0)
		var p: Vector2 = d[0] + v * float(d[1]) * delta * clampf(spd, 0.0, 2.0)
		if snow:
			p.x += sin(Time.get_ticks_msec() / 600.0 + float(d[2])) * 0.3
		if p.y > sz.y:
			p.y -= sz.y + 10.0
			p.x = _rng.randf() * sz.x
		if p.x > sz.x:
			p.x -= sz.x
		d[0] = p
	if st == WeatherSystem.W.STORM and spd > 0.0 and _rng.randf() < delta * 0.12:
		flash = 1.0
	flash = maxf(0.0, flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if game == null or game.sim == null:
		return
	var sim: Sim = game.sim
	var st := sim.weather.state
	var tint := 0.0
	match st:
		WeatherSystem.W.CLOUDY:
			tint = 0.06
		WeatherSystem.W.RAIN:
			tint = 0.12
		WeatherSystem.W.STORM:
			tint = 0.22
		WeatherSystem.W.SNOW:
			tint = 0.08
	if tint > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.28, 0.35, tint))
	var snow := st == WeatherSystem.W.SNOW
	for d in drops:
		var p: Vector2 = d[0]
		if snow:
			draw_circle(p, 1.4 * float(d[1]), Color(1, 1, 1, 0.85))
		else:
			draw_line(p, p + Vector2(-0.2, 1.0) * float(d[2]), Color(0.7, 0.8, 1.0, 0.45), 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.92, 1.0, flash * 0.5))
