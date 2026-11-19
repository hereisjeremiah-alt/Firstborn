extends Node
## Music and UI sounds. Ten soundtrack pieces play in a shuffled order and crossfade smoothly
## into each other. Every button in the game gets a clean click automatically.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const FADE := 5.0                      # seconds of crossfade between tracks
const TRACKS := [
	["res://audio/music/01_first_fire.ogg", "First Fire"],
	["res://audio/music/02_river_dawn.ogg", "River Dawn"],
	["res://audio/music/03_long_winter.ogg", "Long Winter"],
	["res://audio/music/04_stone_circle.ogg", "Stone Circle"],
	["res://audio/music/05_bronze_market.ogg", "Bronze Market"],
	["res://audio/music/06_wandering_herds.ogg", "Wandering Herds"],
	["res://audio/music/07_night_drums.ogg", "Night Drums"],
	["res://audio/music/08_iron_rain.ogg", "Iron Rain"],
	["res://audio/music/09_harvest_song.ogg", "Harvest Song"],
	["res://audio/music/10_distant_shores.ogg", "Distant Shores"],
]

var _players: Array = []      # two AudioStreamPlayers for crossfading
var _active := 0
var _order: Array = []
var _pos := -1
var _fading := 0.0
var _sfx := {}
var _sfx_players: Array = []
var current_title := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus(MUSIC_BUS)
	_make_bus(SFX_BUS)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	for i in 4:
		var s := AudioStreamPlayer.new()
		s.bus = SFX_BUS
		add_child(s)
		_sfx_players.append(s)
	for k in ["click", "toggle", "hover", "confirm", "fanfare"]:
		var path := "res://audio/sfx/%s.wav" % k
		if ResourceLoader.exists(path):
			_sfx[k] = load(path)
	get_tree().node_added.connect(_on_node_added)
	if DisplayServer.get_name() != "headless":
		_next_track()


func _make_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "Master")


func _shuffle() -> void:
	_order = range(TRACKS.size())
	_order.shuffle()
	_pos = -1


func _next_track() -> void:
	if _order.is_empty() or _pos >= _order.size() - 1:
		var last: int = _order[_pos] if not _order.is_empty() and _pos >= 0 else -1
		_shuffle()
		if _order[0] == last and _order.size() > 1:
			_order.append(_order.pop_front())     # never the same piece twice in a row
	_pos += 1
	var tr: Array = TRACKS[_order[_pos]]
	if not ResourceLoader.exists(tr[0]):
		return
	var stream: AudioStream = load(tr[0])
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	p.stream = stream
	p.volume_db = -60.0
	p.play()
	_fading = FADE
	current_title = tr[1]


func skip_track() -> void:
	_next_track()


func _process(delta: float) -> void:
	if _players.is_empty():
		return
	var cur: AudioStreamPlayer = _players[_active]
	var old: AudioStreamPlayer = _players[1 - _active]
	if _fading > 0.0:
		_fading = maxf(0.0, _fading - delta)
		var k := 1.0 - _fading / FADE
		cur.volume_db = linear_to_db(maxf(0.0001, k))
		old.volume_db = linear_to_db(maxf(0.0001, 1.0 - k))
		if _fading <= 0.0:
			old.stop()
	# start the next piece a little before this one ends, so they overlap
	if cur.playing and cur.stream != null:
		var left := cur.stream.get_length() - cur.get_playback_position()
		if left < FADE and _fading <= 0.0:
			_next_track()
	elif not cur.playing and _fading <= 0.0 and DisplayServer.get_name() != "headless":
		_next_track()


func play(name: String) -> void:
	if not Settings.ui_sounds or not _sfx.has(name):
		return
	for s in _sfx_players:
		var sp: AudioStreamPlayer = s
		if not sp.playing:
			sp.stream = _sfx[name]
			sp.pitch_scale = randf_range(0.97, 1.03)
			sp.play()
			return


## A musical sting (e.g. the fanfare for a new leader): plays even with click sounds off.
func play_jingle(name: String) -> void:
	if not _sfx.has(name):
		return
	for s in _sfx_players:
		var sp: AudioStreamPlayer = s
		if not sp.playing:
			sp.stream = _sfx[name]
			sp.pitch_scale = 1.0
			sp.play()
			return


## Every button made anywhere gets click sounds.
func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		var b := n as BaseButton
		if b.toggle_mode or b is CheckBox or b is CheckButton:
			b.toggled.connect(func(_on): play("toggle"))
		else:
			b.pressed.connect(func(): play("click"))
	elif n is Slider:
		(n as Slider).drag_ended.connect(func(_changed): play("toggle"))
	elif n is OptionButton:
		pass
