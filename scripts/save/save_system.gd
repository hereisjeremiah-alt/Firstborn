class_name SaveSystem
extends RefCounted
## Multiple save slots in user://saves. The world is regenerated from its seed on load,
## then every changed piece of state (resources, people, buildings, animals, time, weather) is restored.

const SLOTS := 6
const DIR := "user://saves"


static func _path(slot: int) -> String:
	return "%s/slot_%d.sav" % [DIR, slot]


static func _meta_path(slot: int) -> String:
	return "%s/slot_%d.meta" % [DIR, slot]


static func save(slot: int, sim: Sim, cam_pos: Vector2, cam_zoom: float) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := sim.to_dict()
	data["camera"] = [cam_pos.x, cam_pos.y, cam_zoom]
	var meta := {
		"date": sim.time.date_text(), "season": sim.time.season_name(), "year": sim.time.year(),
		"pop": sim.colony.population(), "seed": sim.world.seed_value, "size": sim.world.w,
		"saved_at": Time.get_datetime_string_from_system(false, true), "tribe": sim.colony.name,
	}
	data["meta"] = meta
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	var mf := FileAccess.open(_meta_path(slot), FileAccess.WRITE)
	if mf != null:
		mf.store_var(meta)
		mf.close()
	return true


static func load_data(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return v


static func info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_meta_path(slot)):
		return {}
	var f := FileAccess.open(_meta_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	f.close()
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func describe(slot: int) -> String:
	var m := info(slot)
	if m.is_empty():
		return "Slot %d — empty" % (slot + 1)
	return "Slot %d — %s, %s (%s) · pop %d · %s" % [slot + 1, m.get("tribe", "Tribe"), m.get("date", "Year %d" % int(m.get("year", 1))),
		m.get("season", "?"), int(m.get("pop", 0)), m.get("saved_at", "")]
