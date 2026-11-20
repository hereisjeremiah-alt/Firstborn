extends Node
## Player settings (not tied to a save): audio volumes, the day/night cycle and accessibility.
## Stored in user://settings.cfg.

const PATH := "user://settings.cfg"

var master_volume := 0.8
var music_volume := 0.6
var sfx_volume := 0.8
var day_night := true            # show the day/night cycle at all
var freeze_zoomed := true        # hide the day/night cycle when zoomed in (eases flashing)
var freeze_zoom_pct := 85.0      # ... beyond this zoom (100% = normal pixel size)
var derender_speed := 16.0       # at this game speed or faster, people and animals aren't drawn
var ui_sounds := true
var show_fps := false
var vsync := false               # cap the frame rate at the monitor's refresh rate
var max_fps := 0                 # 0 = unlimited
var sim_budget_ms := 10.0        # (old fixed budget; target_fps decides it now)
var target_fps := 60             # frame rate the game protects at high speed
var threads := 4                 # worker threads (cores) for the simulation


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master_volume = float(cf.get_value("audio", "master", master_volume))
	music_volume = float(cf.get_value("audio", "music", music_volume))
	sfx_volume = float(cf.get_value("audio", "sfx", sfx_volume))
	ui_sounds = bool(cf.get_value("audio", "ui_sounds", ui_sounds))
	day_night = bool(cf.get_value("game", "day_night", day_night))
	derender_speed = float(cf.get_value("game", "derender_speed", derender_speed))
	show_fps = bool(cf.get_value("game", "show_fps", show_fps))
	vsync = bool(cf.get_value("perf", "vsync", vsync))
	max_fps = int(cf.get_value("perf", "max_fps", max_fps))
	sim_budget_ms = float(cf.get_value("perf", "sim_budget_ms", sim_budget_ms))
	threads = int(cf.get_value("perf", "threads", threads))
	target_fps = int(cf.get_value("perf", "target_fps", target_fps))
	freeze_zoomed = bool(cf.get_value("access", "freeze_zoomed", freeze_zoomed))
	freeze_zoom_pct = float(cf.get_value("access", "freeze_zoom_pct", freeze_zoom_pct))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("audio", "ui_sounds", ui_sounds)
	cf.set_value("game", "day_night", day_night)
	cf.set_value("game", "derender_speed", derender_speed)
	cf.set_value("game", "show_fps", show_fps)
	cf.set_value("perf", "vsync", vsync)
	cf.set_value("perf", "max_fps", max_fps)
	cf.set_value("perf", "sim_budget_ms", sim_budget_ms)
	cf.set_value("perf", "threads", threads)
	cf.set_value("perf", "target_fps", target_fps)
	cf.set_value("access", "freeze_zoomed", freeze_zoomed)
	cf.set_value("access", "freeze_zoom_pct", freeze_zoom_pct)
	cf.save(PATH)


## Pushes volumes into the audio buses (Master, Music, SFX).
func apply() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	_bus("Master", master_volume)
	_bus(Sound.MUSIC_BUS, music_volume)
	_bus(Sound.SFX_BUS, sfx_volume)


func _bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, v)))
	AudioServer.set_bus_mute(i, v <= 0.001)


## True if the day/night lighting should be frozen at daylight right now.
## Steady daylight when the cycle is off, at 8x speed or faster (any zoom), or when zoomed in close.
func hide_day_night(zoom: float, speed := 1.0) -> bool:
	if not day_night or speed >= 8.0:
		return true
	return freeze_zoomed and zoom * 100.0 > freeze_zoom_pct
