class_name Colony
extends RefCounted
## A civilization: its people, buildings and shared stockpile.
## The player's tribe is civ 0; every AI civilization uses this same class and the same rules.

var civ_id := 0
var name := "Your Tribe"
var era_i := 0
var era := "Caveman Age"
var researched := {}         # tech id -> true
var research_points := 0.0   # RP: spent on techs
var knowledge := 0.0         # KP: earned at the research table, 1000 KP -> 1 RP
var research_share := 0.25   # share of incoming materials set aside for research
var research_stock := {}     # materials set aside for research (kept at the stockpile)
var money := 100.0           # Talents in this tribe's bank
var race := 0                # index into Config.races
var flag := {}               # FlagArt flag
var government := ""         # key of Defs.GOVERNMENTS ("" before the Bronze Age)
var gov_pending := false     # player: must pick a government
var clear_marks := {}        # tile index -> true: plants/stones the player wants cleared
var hunt_marks := {}         # animal id -> true: animals inside a clearing box
var wall_ring := 0           # radius of the planned defensive wall (0 = none yet)
var wall_tier := 0           # fortification level the walls are built at
var weapon_orders: Array = []   # player-queued weapons for the blacksmith
var era_start_year := 0.0    # calendar year (fractional) this tribe entered its current age
var bonus_years := 0.0       # years banked with a Monolith toward the next age
var bandit := false          # an outlaw band (Bandits): not a tribe, at war with everyone
var approval := 60.0         # political happiness 0..100 (Politics)
var approval_parts := {}     # what makes up the target approval (for the Colony panel)
var rob_msg_t := -10.0
var just_researched: Array = []   # techs the player unlocked since the last announcement
var recent_robbed := 0.0     # days the tribe remembers being robbed by bandits
var defect_year := 0         # calendar year of the last defection check
var trade_orders: Array = [] # the player's trade orders, carried out by traders (Trade)
var zones := {}              # tile index -> zone (Defs.ZONES)
var wreck_marks := {}        # tile index -> true: enemy roads to tear up (at war)
var auto_roads := true       # the tribe lays its own roads between its buildings
var road_plan_day := 0       # sim day the current road plan was made (AI drops stuck plans)
var road_tried := {}         # building id -> true: already given a road (not saved)
var road_marks := {}         # tile index -> true: roads the player has laid out, still to be built
var backed_id := -1          # the candidate the player backs at the next election
var campaign := {}           # candidate id -> campaign strength bought with Talents and gifts
var rigged := false          # the next election is rigged for the backed candidate
var unrest_until := -1.0     # calendar year when unrest from a rigged election ends
var milestones := {}         # milestone id -> calendar year reached
var enemy_kills := 0
var deals_made := 0
var elections_held := 0
var leader_id := -1          # elected Chief / President (human id)
var leader_title := ""
var leader_terms := 0
var leader_fx := {}          # work bonus from the leader's trade
var next_election := 0.0     # calendar year of the next election
var last_election := {}
var now_years := 0.0         # current calendar year (kept up to date by Sim)
var auto_convert := true     # researchers turn KP into RP automatically
var auto_research := true    # ... and spend it on the cheapest available tech
var victories := 0           # tribes conquered
var war_parties_sent := 0
var exile_asked := {}        # person id -> true: the tribe already raised sending them away
var exile_sorrow := 0.0      # days the tribe is still sad about someone it sent away
var dislike_share := 0.0     # share of adults who want the leader gone (civil war at 50%+)
var civil_war_after := 0.0   # calendar year before which no new civil war breaks out
var auto_advance := false    # move on to the next age as soon as it's paid for
var auto_expand := true      # send people to claim free neighbouring states
var cheat := false           # cheat mode: free, instant building and everything unlocked
var trade_log: Array = []    # recent trades (text), newest last
var _bonus_cache := {}
var people: Array = []       # Human (including the dead, flagged alive=false, kept for family trees)
var buildings: Array = []    # Building
var stock := {}              # item -> float
var home := Vector2i.ZERO
var job_priority := {}       # job -> 1..5 (higher = helped first when someone's own job has no work)
var births := 0
var deaths := 0
var color := Color(0.98, 0.84, 0.30)
var is_player := true
var auto_jobs := true        # tribe AI assigns jobs
var auto_build := true       # tribe AI plans buildings
var collapsed := false
var want_build := ""         # what the tribe AI is saving materials for
var _by_id := {}


func _init() -> void:
	for j in Defs.JOBS:
		job_priority[j] = 3
	job_priority["builder"] = 4
	job_priority["gatherer"] = 4


func register(p: Human) -> void:
	people.append(p)
	_by_id[p.id] = p


func unregister(p: Human) -> void:
	people.erase(p)
	_by_id.erase(p.id)


func person(pid: int) -> Human:
	return _by_id.get(pid, null)


func adults_count() -> int:
	var n := 0
	for p in people:
		if p.alive and p.age_years() >= 16.0:
			n += 1
	return n


func living() -> Array:
	var out: Array = []
	for p in people:
		if p.alive:
			out.append(p)
	return out


func population() -> int:
	var n := 0
	for p in people:
		if p.alive:
			n += 1
	return n


# ---------------------------------------------------------------- stockpile
func count(item: String) -> float:
	return float(stock.get(item, 0.0))


func add(item: String, amount: float) -> void:
	stock[item] = count(item) + amount


## Goods brought home by workers: the research share of materials goes to the research pile
## (only once a Research Table stands), the rest into the stockpile.
func deposit(item: String, amount: float) -> void:
	if research_share > 0.0 and Defs.KP_VALUE.has(item) and has_built("research_table"):
		var r := amount * research_share
		research_stock[item] = float(research_stock.get(item, 0.0)) + r
		amount -= r
	add(item, amount)


func research_pile_total() -> float:
	var t := 0.0
	for k in research_stock.keys():
		t += float(research_stock[k])
	return t


func research_pile_kp() -> float:
	var t := 0.0
	for k in research_stock.keys():
		t += float(research_stock[k]) * Defs.kp_value(k)
	return t


## Takes up to `n` whole units from the research pile, rarest first.
func take_research_load(n: int) -> Dictionary:
	var load := {}
	var left := n
	var keys: Array = research_stock.keys()
	keys.sort_custom(func(a, b): return int(Defs.KP_VALUE.get(a, 0)) > int(Defs.KP_VALUE.get(b, 0)))
	for k in keys:
		if left <= 0:
			break
		var amt := mini(floori(float(research_stock[k])), left)
		if amt <= 0:
			continue
		research_stock[k] = float(research_stock[k]) - amt
		load[k] = amt
		left -= amt
	return load


## Converts knowledge into research points (1000 KP each). Returns how many RP were made.
func convert_knowledge(max_rp := 1000000) -> int:
	var per := Defs.kp_per_rp()
	var n := mini(floori(knowledge / per), max_rp)
	if n <= 0:
		return 0
	knowledge -= n * per
	research_points += n
	return n


func take(item: String, amount: float) -> float:
	var have := count(item)
	var got := minf(have, amount)
	stock[item] = have - got
	return got


func has_cost(cost: Dictionary) -> bool:
	for k in cost.keys():
		if count(k) < float(cost[k]) - 0.001:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost.keys():
		take(k, float(cost[k]))


func food_nutrition() -> float:
	var total := 0.0
	for f in Defs.FOOD.keys():
		total += count(f) * float(Defs.FOOD[f]["nut"])
	return total


func food_units() -> float:
	var total := 0.0
	for f in Defs.FOOD.keys():
		total += count(f)
	return total


func food_days() -> float:
	var pop := maxi(1, population())
	return food_nutrition() / (pop * Defs.DAILY_FOOD)


func raw_food() -> float:
	return count("raw_meat") + count("fish")


func material_total() -> float:
	var total := 0.0
	for k in stock.keys():
		if k != "water" and not Defs.FOOD.has(k):
			total += count(k)
	return total


func storage_capacity() -> float:
	var cap := 120.0 + bonus("storage")
	for b in buildings:
		if b.built:
			cap += float(b.def().get("storage", 0))
	return cap


func water_capacity() -> float:
	var cap := 10.0 + 2.0 * population()
	for b in buildings:
		if b.built:
			cap += float(b.def().get("water_cap", 0))
	return cap


## Fraction by which food spoilage is reduced (storage buildings + research).
func preservation() -> float:
	var v := bonus("preserve")
	var best := 0.0
	for b in buildings:
		if b.built:
			best = maxf(best, float(b.def().get("preserve", 0.0)))
	return minf(0.75, v + best + (0.15 if count_type("granary", false) > 0 and count_type("storage", false) > 0 else 0.0))


func unbuilt_count() -> int:
	var n := 0
	for b in buildings:
		if not b.built:
			n += 1
	return n


func count_type(type: String, include_unbuilt := true) -> int:
	var n := 0
	for b in buildings:
		if b.type == type and (include_unbuilt or b.built):
			n += 1
	return n


## Radius (tiles) of land the tribe considers its own.
func territory() -> float:
	return minf(34.0, 9.0 + sqrt(float(population())) * 3.0 + buildings.size() * 0.4)


## How much of a material the tribe is short of for what it wants to build next.
## How much of a material is still missing for blueprints and the next planned building.
func shortfall(item: String) -> float:
	var need := 0.0
	for b in buildings:
		if not b.built:
			need += float(b.needs().get(item, 0.0))
	if want_build != "":
		need += float((Defs.BUILDINGS[want_build]["cost"] as Dictionary).get(item, 0))
	return maxf(0.0, need - count(item))


func has_storage() -> bool:
	return has_built("storage") or has_built("granary")


# ---------------------------------------------------------------- research & eras
## Sum of a bonus from researched techs and finished buildings (e.g. "work_all", "hunt_dmg").
func bonus(key: String) -> float:
	if _bonus_cache.has(key):
		return _bonus_cache[key]
	var v := 0.0
	for id in researched.keys():
		var fx: Dictionary = Defs.TECHS[id]["fx"]
		v += float(fx.get(key, 0.0))
	var once := key == "soldier" or key == "siege" or key == "defense"
	var seen := {}
	for b in buildings:
		if b.built:
			var cap := 1 if once else int(b.def().get("max", 99))
			if int(seen.get(b.type, 0)) >= cap:
				continue          # war structures count once each, bonus buildings at most twice
			seen[b.type] = int(seen.get(b.type, 0)) + 1
			v += float(b.def().get(key, 0.0)) * (1.25 if b.zoned else 1.0)
	if government != "":
		var gfx: Dictionary = Defs.GOVERNMENTS[government]["fx"]
		v += float(gfx.get(key, 0.0)) * (1.5 if has_built("capitol") else 1.0)
	v += float(leader_fx.get(key, 0.0))
	if key == "work_all" and in_unrest():
		v -= 0.15                    # a stolen election: people work grudgingly
	if key == "fertility" and in_unrest():
		v -= 0.5
	_bonus_cache[key] = v
	return v


## Fortification level the tribe's research allows (0 palisade, 1 stone, 2 fortified).
func best_wall_tier() -> int:
	return clampi(int(bonus("wall_tier")), 0, 2)


## Weapons this tribe can forge now (needs the age and a blacksmith).
func forgeable_weapons() -> Array:
	var out: Array = []
	for w in Defs.WEAPON_ORDER:
		if int(Defs.WEAPONS[w]["era"]) <= era_i:
			out.append(w)
	return out


## Best weapon in the stockpile (by damage), or "".
## Best weapon in the stockpile for a soldier kind: Archers only take ranged weapons, Warriors only close ones.
func best_stock_weapon(kind := "warrior") -> String:
	var ranged := kind == "archer"
	var best := ""
	var best_v := -1.0
	for w in Defs.WEAPON_ORDER:
		if count(w) >= 1.0 and Defs.weapon_ranged(w) == ranged:
			var wd: Dictionary = Defs.WEAPONS[w]
			var v := float(wd["dmg"]) + float(wd["range"]) * 0.5
			if v > best_v:
				best_v = v
				best = w
	return best


func weapons_in_stock() -> int:
	var n := 0
	for w in Defs.WEAPON_ORDER:
		n += int(count(w))
	return n


func soldiers(kind := "") -> Array:
	var out: Array = []
	for p in people:
		if p.alive and p.job == "soldier" and (kind == "" or p.soldier_kind == kind):
			out.append(p)
	return out


func job_allowed(job: String) -> bool:
	if job == "soldier":
		return has_built("training_camp") or has_built("mercenary_hall")
	return not Defs.JOB_NEEDS.has(job) or has_built(Defs.JOB_NEEDS[job])


func in_unrest() -> bool:
	return unrest_until > now_years


func invalidate_bonus() -> void:
	_bonus_cache.clear()


func work_bonus(job: String) -> float:
	return (1.0 + bonus("work_all") + bonus("work_" + job)) * Config.rule("work_speed")


func is_unlocked(type: String) -> bool:
	if cheat:
		return true
	var tech := str(Defs.BUILDINGS[type].get("tech", ""))
	return tech == "" or researched.has(tech)


## Researchable now: in the current era and its prerequisite is done.
func tech_available(id: String) -> bool:
	if researched.has(id) or int(Defs.TECHS[id]["era"]) != era_i:
		return false
	var pre := Defs.tech_prereq(id)
	return pre == "" or researched.has(pre)


func can_afford_tech(id: String) -> bool:
	if research_points < Defs.tech_rp(id) - 0.001:
		return false
	var mats := Defs.tech_materials(id)
	for k in mats.keys():
		if count(k) < float(mats[k]) - 0.001:
			return false
	return true


func research(id: String) -> bool:
	if not tech_available(id) or not can_afford_tech(id):
		return false
	research_points -= Defs.tech_rp(id)
	var mats := Defs.tech_materials(id)
	for k in mats.keys():
		take(k, float(mats[k]))
	researched[id] = true
	invalidate_bonus()
	if is_player:
		just_researched.append(id)
	return true


## Ores still needed for this era's research (item -> amount short).
func ore_needed() -> Dictionary:
	var out := {}
	for id in Defs.techs_of_era(era_i):
		if researched.has(id):
			continue
		var cost: Dictionary = Defs.TECHS[id]["cost"]
		for k in cost.keys():
			if str(k).ends_with("_ore") and count(k) < float(cost[k]):
				out[k] = maxf(float(out.get(k, 0.0)), float(cost[k]) - count(k))
	return out


func era_complete() -> bool:
	for id in Defs.techs_of_era(era_i):
		if not researched.has(id):
			return false
	return true


## Calendar years spent in the current age (plus any banked at a Monolith).
func years_in_era() -> float:
	return now_years - era_start_year + bonus_years


func years_needed() -> float:
	return 0.0        # ages no longer wait on the calendar (kept for old callers)


## Research points needed to enter the next age: double the RP of every tech in this age.
func era_advance_cost() -> int:
	var total := 0
	for id in Defs.techs_of_era(era_i):
		total += Defs.tech_rp(id)
	return int(round(total * Config.rule("era_cost_mult")))


func can_advance_era() -> bool:
	if era_i >= Defs.ERAS.size() - 1:
		return false
	if cheat:
		return true
	return era_complete() and research_points >= float(era_advance_cost())


func advance_era() -> bool:
	if not can_advance_era():
		return false
	if not cheat:
		research_points -= float(era_advance_cost())
	era_i += 1
	era = Defs.ERAS[era_i]
	era_start_year = now_years
	bonus_years = 0.0
	if not Defs.governments_of_era(era_i).is_empty():
		gov_pending = true        # the player picks (AI tribes pick in CivAI)
	invalidate_bonus()
	return true


# ---------------------------------------------------------------- buildings
func has_built(type: String) -> bool:
	for b in buildings:
		if b.built and b.type == type:
			return true
	return false


func building(bid: int) -> Building:
	for b in buildings:
		if b.id == bid:
			return b
	return null


func best_housing_type() -> String:
	for t in ["stone_house", "house", "stone_hut", "shelter"]:
		if is_unlocked(t):
			return t
	return "shelter"


func housing() -> int:
	var n := 0
	for b in buildings:
		var hn = b.housing()
		n += hn + (1 if hn > 0 and b.zoned else 0)
	return n


func nearest_building(from: Vector2, type: String, built_only := true) -> Building:
	var best: Building = null
	var best_d := 1e18
	for b in buildings:
		if b.type != type or (built_only and not b.built):
			continue
		var d := from.distance_squared_to(b.center())
		if d < best_d:
			best_d = d
			best = b
	return best


func lit_fires() -> Array:
	var out: Array = []
	for b in buildings:
		if b.is_lit():
			out.append(b)
	return out


## Where carried goods are dropped off / taken from.
func drop_point(from: Vector2, item := "") -> Vector2i:
	if item in ["raw_meat", "hides", "bones"]:
		var hc := nearest_building(from, "hunting_camp")
		if hc != null:
			return hc.center_tile()
	var st := nearest_building(from, "storage")
	if st != null:
		return st.center_tile()
	var fire := nearest_building(from, "campfire")
	if fire != null:
		return fire.tile + Vector2i(1, 0)
	return home


func health_pct() -> float:
	var alive := living()
	if alive.is_empty():
		return 0.0
	var total := 0.0
	for p in alive:
		total += p.health
	return total / alive.size()


func sick_count() -> int:
	var n := 0
	for p in living():
		if p.is_sick():
			n += 1
	return n


func to_dict() -> Dictionary:
	var ppl: Array = []
	for p in people:
		ppl.append(p.to_dict())
	var bl: Array = []
	for b in buildings:
		bl.append(b.to_dict())
	return {"civ": civ_id, "name": name, "era": era, "people": ppl, "buildings": bl, "stock": stock.duplicate(),
		"hx": home.x, "hy": home.y, "prio": job_priority.duplicate(), "births": births, "deaths": deaths,
		"era_i": era_i, "researched": researched.keys(), "rp": research_points, "kp": knowledge, "share": research_share,
		"rstock": research_stock.duplicate(), "money": money, "trade_log": trade_log.duplicate(),
		"color": color, "player": is_player, "auto_jobs": auto_jobs, "auto_build": auto_build, "collapsed": collapsed,
		"race": race, "flag": FlagArt.to_save(flag), "gov": government, "gov_pending": gov_pending, "clear": clear_marks.keys(),
		"wall_ring": wall_ring, "wall_tier": wall_tier, "weapon_orders": weapon_orders.duplicate(),
		"era_start": era_start_year, "bonus_years": bonus_years, "auto_convert": auto_convert, "auto_research": auto_research,
		"auto_expand": auto_expand, "auto_advance": auto_advance, "civil_after": civil_war_after, "victories": victories, "cheat": cheat,
		"leader": leader_id, "leader_title": leader_title, "leader_terms": leader_terms, "leader_fx": leader_fx.duplicate(),
		"next_election": next_election, "last_election": last_election.duplicate(true),
		"zones_i": zones.keys(), "zones_v": zones.values(), "roads": road_marks.keys(), "wreck": wreck_marks.keys(), "auto_roads": auto_roads, "backed": backed_id,
		"campaign": campaign.duplicate(), "rigged": rigged, "unrest": unrest_until, "milestones": milestones.duplicate(),
		"enemy_kills": enemy_kills, "deals": deals_made, "elections_held": elections_held,
		"bandit": bandit, "approval": approval, "defect_year": defect_year, "trade_orders": trade_orders.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	civ_id = int(d.get("civ", 0))
	name = str(d.get("name", name))
	people.clear()
	_by_id.clear()
	for pd in d["people"]:
		register(Human.from_dict(pd))
	buildings.clear()
	for bd in d["buildings"]:
		buildings.append(Building.from_dict(bd))
	stock = d.get("stock", {})
	home = Vector2i(int(d["hx"]), int(d["hy"]))
	var pr: Dictionary = d.get("prio", {})
	for k in pr.keys():
		job_priority[k] = int(pr[k])
	births = int(d.get("births", 0))
	deaths = int(d.get("deaths", 0))
	color = d.get("color", color)
	era_i = int(d.get("era_i", 0))
	era = Defs.ERAS[era_i]
	researched.clear()
	for id in d.get("researched", []):
		if Defs.TECHS.has(id):
			researched[id] = true
	research_points = float(d.get("rp", 0.0))
	knowledge = float(d.get("kp", 0.0))
	research_share = float(d.get("share", 0.25))
	research_stock = d.get("rstock", {})
	money = float(d.get("money", 100.0))
	race = int(d.get("race", 0))
	flag = FlagArt.from_save(d.get("flag", {}))
	government = str(d.get("gov", ""))
	gov_pending = bool(d.get("gov_pending", false))
	clear_marks.clear()
	for i in d.get("clear", []):
		clear_marks[int(i)] = true
	wall_ring = int(d.get("wall_ring", 0))
	wall_tier = int(d.get("wall_tier", 0))
	weapon_orders = d.get("weapon_orders", [])
	era_start_year = float(d.get("era_start", 0.0))
	bonus_years = float(d.get("bonus_years", 0.0))
	auto_convert = bool(d.get("auto_convert", false))
	auto_research = bool(d.get("auto_research", false))
	auto_expand = bool(d.get("auto_expand", civ_id != 0))
	auto_advance = bool(d.get("auto_advance", false))
	civil_war_after = float(d.get("civil_after", 0.0))
	victories = int(d.get("victories", 0))
	cheat = bool(d.get("cheat", false))
	leader_id = int(d.get("leader", -1))
	leader_title = str(d.get("leader_title", ""))
	leader_terms = int(d.get("leader_terms", 0))
	leader_fx = d.get("leader_fx", {})
	next_election = float(d.get("next_election", 0.0))
	last_election = d.get("last_election", {})
	zones.clear()
	var zi: Array = d.get("zones_i", [])
	var zv: Array = d.get("zones_v", [])
	for k in zi.size():
		zones[int(zi[k])] = int(zv[k])
	wreck_marks.clear()
	for i in d.get("wreck", []):
		wreck_marks[int(i)] = true
	auto_roads = bool(d.get("auto_roads", true))
	road_marks.clear()
	for i in d.get("roads", []):
		road_marks[int(i)] = true
	backed_id = int(d.get("backed", -1))
	campaign = {}
	var cd: Dictionary = d.get("campaign", {})
	for k in cd.keys():
		campaign[int(k)] = float(cd[k])
	rigged = bool(d.get("rigged", false))
	unrest_until = float(d.get("unrest", -1.0))
	milestones = d.get("milestones", {})
	enemy_kills = int(d.get("enemy_kills", 0))
	deals_made = int(d.get("deals", 0))
	elections_held = int(d.get("elections_held", 0))
	bandit = bool(d.get("bandit", false))
	approval = float(d.get("approval", 60.0))
	defect_year = int(d.get("defect_year", 0))
	trade_orders = d.get("trade_orders", [])
	Trade.load_orders(self)
	trade_log = d.get("trade_log", [])
	invalidate_bonus()
	is_player = bool(d.get("player", civ_id == 0))
	auto_jobs = bool(d.get("auto_jobs", true))
	auto_build = bool(d.get("auto_build", true))
	collapsed = bool(d.get("collapsed", false))
