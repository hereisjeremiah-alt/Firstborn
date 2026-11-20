extends Node
## Carries settings from the menus into the game scene: world, custom rules, races and the
## player's flag. Everything here is also written into save files.

var seed_value := 0
var world_size := 384
var load_slot := -1      # >= 0 means "load this save slot instead of starting a new world"
var tribe_name := "Your Tribe"
var ai_tribes := 4      # rival AI civilizations
var fog_of_war := false
var earth_mode := false # play on a map of today's Earth (EarthGen) # the map starts hidden; your Billies uncover it

# ---------------------------------------------------------------- custom rules
## [key, label, min, max, step, default, format, group, help]
## format: "x" = multiplier, "%" = percent (stored 0..1), "d" = plain number, "b" = on/off
const RULES := [
	["calendar_speed", "Calendar speed (days per work-day)", 1.0, 30.0, 0.5, 5.0, "x", "Time", "How fast dates, seasons, years and the visible time of day move compared with daily life. Billies still walk and work at the same pace. Aging and the seasons follow the calendar."],
	["birth_chance", "Chance of conceiving", 0.1, 4.0, 0.1, 1.0, "x", "People", "How often couples have children."],
	["pregnancy_days", "Pregnancy length (days)", 10.0, 120.0, 5.0, 45.0, "d", "People", "Days from expecting to birth."],
	["twin_chance", "Twin chance", 0.0, 0.5, 0.01, 0.12, "%", "People", "Chance a birth brings twins."],
	["birth_recovery", "Rest between children (days)", 0.0, 90.0, 5.0, 20.0, "d", "People", "Days before a mother can conceive again."],
	["aging_speed", "Aging speed (adults)", 0.25, 4.0, 0.05, 1.0, "x", "People", "How fast adults grow old. 1x = one life year every 40 days."],
	["child_growth", "Child growth speed", 1.0, 8.0, 0.5, 3.0, "x", "People", "How much faster children age than adults."],
	["consent_age", "Age of consent (partners & children)", 18.0, 21.0, 1.0, 18.0, "d", "People", "The youngest age at which Billies may become partners and have children (18 to 21)."],
	["easy_birth", "Easy Birth", 0.0, 1.0, 1.0, 1.0, "b", "People", "Every woman gives birth at least twice before 45 (once, when her tribe has more than 100 people). Doesn't apply while the tribe lacks housing. Keeps young tribes from dying out."],
	["allow_kin", "Partners within the family", 0.0, 1.0, 1.0, 1.0, "b", "People", "Lets close relatives (siblings, parent and child) become partners. Unrelated partners are still preferred."],
	["kin_frailty", "Frailty of children of close kin", 0.0, 1.0, 0.05, 0.3, "%", "People", "Chance a child of close relatives is born frail: weaker at work and likelier to die of illness."],
	["work_age", "Age children start working", 3.0, 16.0, 1.0, 6.0, "d", "People", "Life years before children take jobs."],
	["start_people", "Starting people per tribe", 2.0, 10.0, 1.0, 2.0, "d", "People", "Founders in every tribe."],
	["hunger_rate", "Hunger & thirst speed", 0.25, 3.0, 0.05, 1.0, "x", "Survival", "How fast people get hungry and thirsty."],
	["spoilage", "Food spoilage", 0.0, 3.0, 0.05, 1.0, "x", "Survival", "How fast stored food rots."],
	["illness_freq", "Illness frequency", 0.0, 4.0, 0.05, 1.0, "x", "Illness", "How often people fall ill (0 = never)."],
	["illness_lethality", "Illness lethality", 0.0, 4.0, 0.05, 1.0, "x", "Illness", "Chance that an illness kills."],
	["contagion", "Contagion", 0.0, 4.0, 0.05, 1.0, "x", "Illness", "How easily illness spreads between people."],
	["child_risk", "Extra risk for children", 1.0, 4.0, 0.1, 1.5, "x", "Illness", "How much more likely children under 6 are to die of an illness."],
	["kp_per_rp", "Knowledge points per research point", 100.0, 5000.0, 100.0, 1000.0, "d", "Research", "KP converted into 1 RP."],
	["kp_value", "Knowledge from materials", 0.25, 4.0, 0.05, 1.0, "x", "Research", "KP each material is worth at the research table."],
	["tech_cost", "Tech cost", 0.25, 4.0, 0.05, 1.0, "x", "Research", "RP price of every tech."],
	["research_share", "Default share for research", 0.0, 1.0, 0.05, 0.25, "%", "Research", "Share of incoming materials set aside for research."],
	["era_cost_mult", "Next-age cost (× age's tech RP)", 0.5, 5.0, 0.25, 2.0, "x", "Research", "Entering the next age costs this many times the total RP of every tech in the current age (after all of them are researched)."],
	["monolith_kp", "Monolith: knowledge per year skipped", 0.0, 10000.0, 100.0, 1000.0, "d", "Research", "KP the Monolith costs to skip one calendar year."],
	["work_speed", "Work speed", 0.25, 4.0, 0.05, 1.0, "x", "World", "How fast everyone gathers, builds and crafts."],
	["animal_density", "Wildlife", 0.1, 3.0, 0.05, 1.0, "x", "World", "How many animals live in the world."],
	["start_money", "Starting Talents", 0.0, 1000.0, 10.0, 100.0, "d", "World", "Money in every tribe's bank at the start."],
	["shell_income", "Daily Talents per person", 0.0, 2.0, 0.05, 0.25, "d", "World", "Talents each tribe gathers per person per day."],
	["ai_aggression", "Rival aggression", 0.0, 3.0, 0.1, 1.0, "x", "World", "How readily AI tribes go to war."],
	["tree_regrow_days", "Days for a felled tree to grow back", 3.0, 120.0, 1.0, 25.0, "d", "World", "Work-days before a felled tree grows back (in spring and summer), unless a structure or road stands on the spot."],
	["bandit_camps", "Bandit camps", 0.0, 10.0, 1.0, 3.0, "d", "World", "Outlaw camps placed in the wilds at the start of a new game. Bandits rob villages and ambush traders."],
	["trespass_war", "War chance when caught trespassing", 0.0, 1.0, 0.05, 0.3, "%", "World", "Chance a tribe goes to war when it catches a foreign Billy on its land without permission. +10% for every age after the Caveman Age."],
	["defect_below", "Unhappiness that splits a tribe", 0.0, 0.6, 0.05, 0.2, "%", "World", "When a tribe's political happiness falls below this, a group of its people may leave."],
	["trade_range", "Trading distance (tiles)", 30.0, 800.0, 10.0, 250.0, "", "World", "How far traders will walk or sail to another tribe, home to home."],
	["wagon_trade_bonus", "Extra distance with Trade Wagons", 0.0, 800.0, 10.0, 200.0, "", "World", "How much further traders reach once Trade Wagons (Stone Age) are researched."],
	["kill_war_chance", "War chance when someone is killed", 0.0, 1.0, 0.05, 0.6, "%", "World", "Chance that a tribe declares war when one of its people is killed by another tribe."],
	["leader_kill_war_chance", "War chance when a leader is killed", 0.0, 1.0, 0.05, 0.9, "%", "World", "Chance of war when another tribe kills a tribe's leader. Killing an enemy leader (or burning their Capitol) during a war conquers the whole tribe."],
	["war_parties", "Monthly war parties", 0.0, 1.0, 1.0, 1.0, "b", "World", "Tribes at war send an attack party against each other once a month, in every age."],
	["civil_war_chance", "Yearly chance of civil war", 0.0, 1.0, 0.05, 0.3, "%", "World", "When half or more of a tribe's adults dislike their leader, the chance each calendar year that the tribe splits in a civil war."],
	["defect_chance", "Yearly chance of a split", 0.0, 1.0, 0.05, 0.4, "%", "World", "Chance each calendar year that an unhappy tribe splits: a group leaves to join another tribe (if allowed) or to found their own."],
	["election_years", "Years between elections", 1.0, 30.0, 1.0, 4.0, "d", "World", "Calendar years a Chief or President serves before the next election."],
]
var rules := {}

# ---------------------------------------------------------------- races
const DEFAULT_RACES := [
	{"name": "Humans", "skin": Color(0.87, 0.67, 0.50)},
	{"name": "Ashborn", "skin": Color(0.62, 0.62, 0.66)},
	{"name": "Verdani", "skin": Color(0.45, 0.68, 0.40)},
	{"name": "Azurai", "skin": Color(0.40, 0.58, 0.85)},
	{"name": "Emberkin", "skin": Color(0.86, 0.42, 0.28)},
	{"name": "Duskari", "skin": Color(0.55, 0.42, 0.70)},
]
var races: Array = []
var player_race := 0
var mixed_races := true      # rival tribes get random races (else everyone is the player's race)

# ---------------------------------------------------------------- flag
var flag := {}


func _ready() -> void:
	reset_rules()
	reset_races()
	flag = FlagArt.default_flag()


func reset_rules() -> void:
	rules.clear()
	for r in RULES:
		rules[r[0]] = float(r[5])


## Random but playable rules: each slider lands somewhere between half and nearly double its
## default (within its range); on/off rules flip a coin.
func randomize_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for r in RULES:
		var key: String = r[0]
		var lo: float = r[2]
		var hi: float = r[3]
		var step: float = r[4]
		var def: float = r[5]
		var v: float
		if r[6] == "b":
			v = 1.0 if rng.randf() < 0.5 else 0.0
		elif def <= 0.0:
			v = rng.randf_range(lo, lo + (hi - lo) * 0.3)
		else:
			v = def * rng.randf_range(0.5, 1.8)
		v = clampf(snappedf(v, step), lo, hi)
		rules[key] = v


## Ready-made sets of rules for the new-world screen. Each starts from the defaults and scales
## a few sliders (multipliers on the default value).
const PRESETS := {
	"Easy": {"hunger_rate": 0.75, "spoilage": 0.7, "illness_freq": 0.6, "illness_lethality": 0.6, "contagion": 0.7, "child_risk": 0.6,
		"ai_aggression": 0.5, "bandit_camps": 0.34, "start_people": 2.0, "start_money": 2.0, "work_speed": 1.2, "tech_cost": 0.8,
		"trespass_war": 0.5, "defect_chance": 0.5, "civil_war_chance": 0.5, "kill_war_chance": 0.6, "leader_kill_war_chance": 0.75},
	"Medium": {},
	"Hard": {"hunger_rate": 1.3, "spoilage": 1.3, "illness_freq": 1.4, "illness_lethality": 1.4, "contagion": 1.3, "child_risk": 1.3,
		"ai_aggression": 1.8, "bandit_camps": 1.67, "start_money": 0.5, "work_speed": 0.85, "tech_cost": 1.25,
		"trespass_war": 1.5, "defect_chance": 1.5, "civil_war_chance": 1.5},
	"Fast-paced": {"calendar_speed": 2.0, "aging_speed": 1.5, "child_growth": 1.5, "work_speed": 1.4, "tech_cost": 0.7, "birth_chance": 1.3,
		"pregnancy_days": 0.7, "election_years": 0.6, "tree_regrow_days": 0.5, "era_cost_mult": 0.75},
	"Slow-paced": {"calendar_speed": 0.5, "aging_speed": 0.7, "child_growth": 0.7, "work_speed": 0.8, "tech_cost": 1.4,
		"pregnancy_days": 1.2, "election_years": 1.5, "tree_regrow_days": 1.5, "era_cost_mult": 1.25},
}
const PRESET_DESC := {
	"Easy": "Less hunger, sickness and danger; more Talents, people and faster work.",
	"Medium": "The standard rules.",
	"Hard": "Hungrier, sicker people, aggressive rivals, more bandits and slower progress.",
	"Fast-paced": "Time, growth, building and research all move faster.",
	"Slow-paced": "A long, slow game: everything takes more time.",
}


func apply_preset(name: String) -> void:
	reset_rules()
	var p: Dictionary = PRESETS.get(name, {})
	for r in RULES:
		var key: String = r[0]
		if not p.has(key):
			continue
		var v: float = float(r[5]) * float(p[key])
		if key == "start_people":
			v = float(r[5]) + float(p[key])       # extra founders, not a multiple
		rules[key] = clampf(snappedf(v, float(r[4])), float(r[2]), float(r[3]))


func reset_races() -> void:
	races.clear()
	for r in DEFAULT_RACES:
		races.append(r.duplicate())
	player_race = 0


## Current value of a custom rule.
func rule(key: String) -> float:
	return float(rules.get(key, _default(key)))


func _default(key: String) -> float:
	for r in RULES:
		if r[0] == key:
			return float(r[5])
	return 1.0


func race_name(i: int) -> String:
	if i < 0 or i >= races.size():
		return "Humans"
	return str(races[i]["name"])


func race_skin(i: int) -> Color:
	if i < 0 or i >= races.size():
		return Color(0.87, 0.67, 0.50)
	return races[i]["skin"]


func new_game(s: int, size: int) -> void:
	seed_value = s
	world_size = size
	load_slot = -1


func load_game(slot: int) -> void:
	load_slot = slot


## Settings that travel with a save file.
func to_dict() -> Dictionary:
	var rs: Array = []
	for r in races:
		rs.append({"name": r["name"], "skin": (r["skin"] as Color).to_html()})
	return {"rules": rules.duplicate(), "races": rs, "player_race": player_race, "flag": FlagArt.to_save(flag)}


func from_dict(d: Dictionary) -> void:
	reset_rules()
	var rd: Dictionary = d.get("rules", {})
	for k in rd.keys():
		rules[k] = float(rd[k])
	if d.has("races"):
		races.clear()
		for r in d["races"]:
			races.append({"name": str(r["name"]), "skin": Color.html(str(r["skin"]))})
	if races.is_empty():
		reset_races()
	player_race = int(d.get("player_race", 0))
	if d.has("flag"):
		flag = FlagArt.from_save(d["flag"])


## Turns any text into a seed. Numbers are used directly, words are hashed.
static func seed_from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		return randi()
	if t.is_valid_int():
		return int(t.to_int() & 0x7fffffff)
	return int(t.hash() & 0x7fffffff)
