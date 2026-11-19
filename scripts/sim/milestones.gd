class_name Milestones
extends RefCounted
## Goals for the player's tribe. Each pays a reward (Talents, knowledge, research points) once reached.
## Checked every game hour; shown in the Milestones panel (key G).

## id, name, description, reward {money, kp, rp}, group
const LIST := [
	["first_fire", "First Fire", "Build a campfire.", {"money": 10, "kp": 200}, "Survival"],
	["roof", "A Roof Overhead", "Finish a shelter or hut.", {"money": 10, "kp": 200}, "Survival"],
	["first_child", "The Next Generation", "A child is born in your tribe.", {"money": 15, "kp": 300}, "Survival"],
	["well_fed", "Well Fed", "Store enough food to feed everyone for 10 days.", {"money": 20, "kp": 400}, "Survival"],
	["first_winter", "Winter Survivors", "Live to see Year 2.", {"money": 25, "kp": 600}, "Survival"],
	["elder", "Wisdom of Age", "Someone in your tribe reaches 60 years old.", {"money": 20, "kp": 500}, "Survival"],
	["village", "A Proper Village", "Grow to 10 people.", {"money": 30, "kp": 600}, "Growth"],
	["town", "Thriving Town", "Grow to 25 people.", {"money": 60, "kp": 1500, "rp": 2}, "Growth"],
	["city", "City of the Ancients", "Grow to 50 people.", {"money": 150, "kp": 4000, "rp": 5}, "Growth"],
	["planner", "Town Planner", "Have 6 buildings standing in zones that suit them.", {"money": 40, "kp": 800}, "Growth"],
	["roads", "All Roads Lead Home", "Lay 40 tiles of road.", {"money": 40, "kp": 800}, "Growth"],
	["first_lesson", "First Lesson", "Research your first tech.", {"money": 10, "kp": 300}, "Knowledge"],
	["scholars", "House of Scholars", "Research 25 techs.", {"money": 50, "rp": 3}, "Knowledge"],
	["stone_age", "Age of Stone", "Enter the Stone Age.", {"money": 40, "kp": 1000}, "Knowledge"],
	["bronze_age", "Age of Bronze", "Enter the Bronze Age.", {"money": 80, "kp": 2500, "rp": 3}, "Knowledge"],
	["iron_age", "Age of Iron", "Enter the Iron Age.", {"money": 150, "kp": 5000, "rp": 6}, "Knowledge"],
	["monolith", "Stone That Counts the Years", "Raise a Monolith.", {"money": 40, "kp": 1000}, "Knowledge"],
	["contact", "We Are Not Alone", "Meet another tribe.", {"money": 15, "kp": 300}, "Diplomacy"],
	["merchants", "Merchant Tribe", "Hold 500 Talents in your bank.", {"kp": 1500, "rp": 2}, "Diplomacy"],
	["deal_maker", "Deal Maker", "Complete 5 deals with other tribes.", {"money": 50, "kp": 1000}, "Diplomacy"],
	["alliance", "Bound by Oath", "Form an alliance.", {"money": 40, "kp": 800}, "Diplomacy"],
	["elections", "The People's Choice", "Hold 3 elections.", {"money": 30, "kp": 800}, "Diplomacy"],
	["capitol", "Seat of Power", "Build a Capitol.", {"money": 60, "kp": 1500}, "Diplomacy"],
	["army", "Shield and Bow", "Field 5 Warriors and 3 Archers.", {"money": 50, "kp": 1000}, "War"],
	["first_blood", "First Blood", "Defeat an enemy warrior in battle.", {"money": 25, "kp": 500}, "War"],
	["realm", "A Realm of Many Lands", "Hold 6 states.", {"money": 80, "kp": 2000, "rp": 2}, "War"],
	["seafarers", "Seafarers", "Launch a ship.", {"money": 30, "kp": 800}, "War"],
]


## [current, goal] progress toward a milestone.
static func progress(sim: Sim, c: Colony, id: String) -> Array:
	match id:
		"first_fire":
			return [1 if c.has_built("campfire") else 0, 1]
		"roof":
			return [1 if c.housing() > 0 else 0, 1]
		"first_child":
			return [mini(c.births, 1), 1]
		"well_fed":
			return [int(c.food_days()), 10]
		"first_winter":
			return [mini(sim.time.year() - 1, 1), 1]
		"elder":
			var oldest := 0
			for p in c.living():
				oldest = maxi(oldest, int(p.age_years()))
			return [oldest, 60]
		"village":
			return [c.population(), 10]
		"town":
			return [c.population(), 25]
		"city":
			return [c.population(), 50]
		"planner":
			var n := 0
			for b in c.buildings:
				if b.built and b.zoned:
					n += 1
			return [n, 6]
		"roads":
			return [sim.road_tiles.size(), 40]
		"first_lesson":
			return [mini(c.researched.size(), 1), 1]
		"scholars":
			return [c.researched.size(), 25]
		"stone_age":
			return [mini(c.era_i, 1), 1]
		"bronze_age":
			return [mini(c.era_i, 2), 2]
		"iron_age":
			return [mini(c.era_i, 3), 3]
		"monolith":
			return [1 if c.has_built("monolith") else 0, 1]
		"contact":
			var met := 0
			for o in sim.colonies:
				if o.civ_id != 0 and sim.have_met(0, o.civ_id):
					met = 1
			return [met, 1]
		"merchants":
			return [int(c.money), 500]
		"deal_maker":
			return [c.deals_made, 5]
		"alliance":
			return [mini(Deals.allies_of(sim, 0).size(), 1), 1]
		"elections":
			return [c.elections_held, 3]
		"capitol":
			return [1 if c.has_built("capitol") else 0, 1]
		"army":
			return [mini(c.soldiers("warrior").size(), 5) + mini(c.soldiers("archer").size(), 3), 8]
		"first_blood":
			return [mini(c.enemy_kills, 1), 1]
		"realm":
			return [sim.states.owned_by(0).size(), 6]
		"seafarers":
			var ships := 0
			for sh in sim.ships:
				if sh.civ_id == 0:
					ships += 1
			return [mini(ships, 1), 1]
	return [0, 1]


static func reward_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if r.has("money"):
		parts.append("%d %s" % [int(r["money"]), Defs.MONEY_NAME])
	if r.has("kp"):
		parts.append("%d KP" % int(r["kp"]))
	if r.has("rp"):
		parts.append("%d RP" % int(r["rp"]))
	return ", ".join(parts)


## Hourly: awards any milestone the player's tribe has just reached.
static func check(sim: Sim) -> void:
	var c := sim.colony
	if c == null or c.collapsed or not sim.started:
		return
	for m in LIST:
		var id := str(m[0])
		if c.milestones.has(id):
			continue
		var pr := progress(sim, c, id)
		if int(pr[0]) < int(pr[1]):
			continue
		c.milestones[id] = sim.time.cal_years()
		var r: Dictionary = m[3]
		c.money += float(r.get("money", 0))
		c.knowledge += float(r.get("kp", 0))
		c.research_points += float(r.get("rp", 0))
		sim.emit_signal("event", "Milestone reached: %s! Reward: %s." % [m[1], reward_text(r)], "good")
		sim.emit_signal("milestone", id)


static func count_done(c: Colony) -> int:
	return c.milestones.size()
