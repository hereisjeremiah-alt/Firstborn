class_name Human
extends RefCounted
## One colonist (or member of any civilization). Pure data; behaviour lives in HumanAI / Survival.

var id := 0
var civ_id := 0
var name := ""
var gender := "M"
var age_days := 0.0
var health := 100.0
var hunger := 100.0    # 100 = full, 0 = starving
var thirst := 100.0    # 100 = hydrated, 0 = dehydrated
var energy := 100.0
var warmth := 100.0    # body heat comfort; low = freezing
var skills := {}
var job := "laborer"
var partner_id := -1
var father_id := -1
var mother_id := -1
var children: Array = []
var illness := {}      # {"type": String, "days": float, "treated": float}
var conditions := {}   # chronic: "dementia" / "obesity" / "diabetes" -> age when it began (see Conditions)
var immune_days := 0.0
var immunities: Array = []
var race := 0             # index into Config.races
var weapon := ""          # soldiers: weapon item carried (Defs.WEAPONS)   # lifelong immunities (e.g. measles survivors)
var pregnant_days := -1.0
var alive := true
var cause := ""
var soldier_kind := "warrior"   # soldiers: "warrior" (close combat) or "archer" (ranged)
var drafted := false            # made a soldier on purpose (trained or hired): auto-jobs leave them be
var hired := false              # came from a Mercenary Hall
var frail := false     # child of close relatives
var clothed := false   # wears hide clothing (warmer)
var aboard := -1       # ship id while at sea
var pos := Vector2.ZERO

# transient (not saved)
var task_memory := {}   # small per-person scratch data for job planning (e.g. next trade time)
var path: Array = []
var task := {}
var carrying := {}
var state := "Idle"
var sleeping := false
var bed_id := -1
var facing := 1.0
var anim := 0.0
var wet := false
var think_t := 0.0
var attack_cd := 0.0
var danger_t := 0.0
var offset := Vector2.ZERO
var lod_acc := 0.0
var strike_at := -10.0    # combat visuals (real time of the last strike / hit)
var strike_dir := Vector2.RIGHT
var hurt_at := -10.0
var hurt_dir := Vector2.LEFT


func age_years() -> float:
	return age_days / Defs.AGE_YEAR_DAYS


func stage() -> String:
	var a := age_years()
	if a < 3.0:
		return "Infant"
	if a < 12.0:
		return "Child"
	if a < 16.0:
		return "Youth"
	if a < 55.0:
		return "Adult"
	return "Elder"


func can_work() -> bool:
	return age_years() >= Config.rule("work_age") and not dementia_harmful()


## How far dementia has gone: 0 (none) .. 1 (at 70, when it does more harm than good).
func dementia_level() -> float:
	if not conditions.has("dementia"):
		return 0.0
	return clampf(0.15 + (age_years() - 45.0) / 25.0 * 0.85, 0.15, 1.0)


func dementia_harmful() -> bool:
	return conditions.has("dementia") and age_years() >= 70.0


## True while away on a trading voyage (at sea, not drawn on the map).
func at_sea() -> bool:
	return aboard >= 0 or task.get("type", "") == "voyage"


func is_adult() -> bool:
	return age_years() >= 16.0


func carry_total() -> int:
	var n := 0
	for k in carrying.keys():
		n += int(carrying[k])
	return n


func carry_capacity() -> int:
	var a := age_years()
	if a < 12.0:
		return 4
	if a > 60.0:
		return 8
	return 12


func add_carry(item: String, amount: int) -> void:
	carrying[item] = int(carrying.get(item, 0)) + amount


func skill(job_name: String) -> float:
	return float(skills.get(job_name, 0.0))


func gain_skill(job_name: String, amount: float) -> void:
	skills[job_name] = minf(20.0, skill(job_name) + amount)


func is_sick() -> bool:
	return not illness.is_empty()


## Multiplier for work speed: health, illness, age and skill.
func work_mult(job_name: String) -> float:
	var m := 0.5 + 0.5 * clampf(health / 100.0, 0.0, 1.0)
	if is_sick():
		m *= float(Defs.ILLNESS[illness["type"]]["work"])
	if energy < 20.0:
		m *= 0.7
	var a := age_years()
	if a < 14.0:
		m *= 0.6
	elif a > 60.0:
		m *= 0.75
	if frail:
		m *= 0.85
	if not conditions.is_empty():
		m *= 1.0 - 0.55 * dementia_level()
		if conditions.has("obesity"):
			m *= 0.9
		if conditions.has("diabetes"):
			m *= 0.9
	return m * (1.0 + skill(job_name) * 0.05)


func speed_mult() -> float:
	var m := 1.0
	if health < 40.0:
		m *= 0.7
	if is_sick():
		m *= 0.8
	var a := age_years()
	if a < 6.0:
		m *= 0.75
	elif a > 62.0:
		m *= 0.8
	if conditions.has("obesity"):
		m *= 0.85
	return m


func to_dict() -> Dictionary:
	return {
		"id": id, "civ": civ_id, "name": name, "gender": gender, "age": age_days, "health": health,
		"hunger": hunger, "thirst": thirst, "energy": energy, "warmth": warmth, "skills": skills.duplicate(),
		"job": job, "partner": partner_id, "father": father_id, "mother": mother_id,
		"children": children.duplicate(), "illness": illness.duplicate(), "cond": conditions.duplicate(), "immune": immune_days, "immunities": immunities.duplicate(), "race": race, "weapon": weapon,
		"pregnant": pregnant_days, "alive": alive, "cause": cause, "x": pos.x, "y": pos.y,
		"carrying": carrying.duplicate(), "bed": bed_id, "clothed": clothed, "aboard": aboard, "frail": frail, "skind": soldier_kind, "hired": hired, "drafted": drafted,
	}


static func from_dict(d: Dictionary) -> Human:
	var p := Human.new()
	p.id = int(d["id"])
	p.civ_id = int(d.get("civ", 0))
	p.name = str(d["name"])
	p.gender = str(d["gender"])
	p.age_days = float(d["age"])
	p.health = float(d["health"])
	p.hunger = float(d["hunger"])
	p.thirst = float(d["thirst"])
	p.energy = float(d["energy"])
	p.warmth = float(d["warmth"])
	p.skills = d.get("skills", {})
	p.job = str(d["job"])
	p.partner_id = int(d["partner"])
	p.father_id = int(d["father"])
	p.mother_id = int(d["mother"])
	p.children = d.get("children", [])
	p.illness = d.get("illness", {})
	p.conditions = d.get("cond", {})
	p.immune_days = float(d.get("immune", 0.0))
	p.immunities = d.get("immunities", [])
	p.race = int(d.get("race", 0))
	p.weapon = str(d.get("weapon", ""))
	p.pregnant_days = float(d.get("pregnant", -1.0))
	p.alive = bool(d.get("alive", true))
	p.cause = str(d.get("cause", ""))
	p.pos = Vector2(float(d["x"]), float(d["y"]))
	p.carrying = d.get("carrying", {})
	p.bed_id = int(d.get("bed", -1))
	p.clothed = bool(d.get("clothed", false))
	p.aboard = int(d.get("aboard", -1))
	p.frail = bool(d.get("frail", false))
	p.hired = bool(d.get("hired", false))
	p.drafted = bool(d.get("drafted", false))
	p.soldier_kind = str(d.get("skind", "archer" if Defs.weapon_ranged(p.weapon) else "warrior"))
	return p
