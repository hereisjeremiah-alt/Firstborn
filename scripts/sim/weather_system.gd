class_name WeatherSystem
extends RefCounted
## Regional weather that changes over time with seasonal probabilities.

enum W { CLEAR, CLOUDY, RAIN, STORM, SNOW }
const NAMES := ["Clear", "Cloudy", "Rain", "Storm", "Snow"]

var state := W.CLEAR
var hours_left := 10.0
var rng := RandomNumberGenerator.new()


func setup(s: int) -> void:
	rng.seed = s + 777


## dt_hours: game hours passed. cold: whether precipitation would fall as snow.
## Returns true if the weather changed.
func update(dt_hours: float, season: int, cold: bool) -> bool:
	hours_left -= dt_hours
	if hours_left > 0.0:
		# rain turns to snow (and back) as temperatures change
		if state == W.RAIN and cold:
			state = W.SNOW
			return true
		if state == W.SNOW and not cold:
			state = W.RAIN
			return true
		return false
	_roll(season, cold)
	return true


func _roll(season: int, cold: bool) -> void:
	var r := rng.randf()
	var rain_p: float = [0.30, 0.14, 0.28, 0.30][season]
	var storm_p: float = [0.07, 0.10, 0.07, 0.06][season]
	var cloud_p: float = [0.22, 0.15, 0.28, 0.25][season]
	if r < storm_p:
		state = W.STORM
		hours_left = rng.randf_range(3.0, 9.0)
	elif r < storm_p + rain_p:
		state = W.SNOW if cold else W.RAIN
		hours_left = rng.randf_range(4.0, 16.0)
	elif r < storm_p + rain_p + cloud_p:
		state = W.CLOUDY
		hours_left = rng.randf_range(4.0, 14.0)
	else:
		state = W.CLEAR
		hours_left = rng.randf_range(6.0, 24.0)


func temp_offset() -> float:
	match state:
		W.CLOUDY:
			return -1.5
		W.RAIN:
			return -3.0
		W.STORM:
			return -5.0
		W.SNOW:
			return -4.0
	return 0.0


func is_wet() -> bool:
	return state == W.RAIN or state == W.STORM or state == W.SNOW


func label() -> String:
	return NAMES[state]


func to_dict() -> Dictionary:
	return {"state": state, "hours_left": hours_left, "rng": rng.state}


func from_dict(d: Dictionary) -> void:
	state = int(d.get("state", 0))
	hours_left = float(d.get("hours_left", 10.0))
	rng.state = int(d.get("rng", rng.state))
