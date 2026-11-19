class_name Deals
extends RefCounted
## Diplomacy beyond war and peace: trade offers, alliances, tribute and land demands.
##  - AI tribes propose deals to the player (a card at the top of the screen) and to each other.
##  - The player can accept, decline or counter-offer; AI tribes weigh counters by relations and strength.
##  - The player can also propose alliances, ask for a trade, and demand tribute or land.
## Alliances are defensive: when someone attacks your ally, you join the war (and they do for you),
## and allies may always cross each other's land.

const OFFER_LIFE := 1.5            # sim days an offer stays open
const MAX_QUEUE := 3


static func _k(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func allied(sim: Sim, a: int, b: int) -> bool:
	return a != b and sim.alliances.has(_k(a, b))


static func allies_of(sim: Sim, a: int) -> Array:
	var out: Array = []
	for c in sim.colonies:
		if not c.collapsed and allied(sim, a, c.civ_id):
			out.append(c)
	return out


static func make_alliance(sim: Sim, a: int, b: int) -> void:
	sim.alliances[_k(a, b)] = sim.time.cal_years()
	var key := sim._key(a, b)
	sim.contacts[key] = true
	sim.relations[key] = maxf(sim.relation(a, b), 30.0)
	var ca := sim.civ(a)
	var cb := sim.civ(b)
	ca.deals_made += 1
	cb.deals_made += 1
	if a == 0 or b == 0:
		sim.emit_signal("event", "You are now allied with the %s. Each of you will defend the other, and your Billies may cross each other's land." % (cb.name if a == 0 else ca.name), "major_good")
	elif sim.have_met(0, a) or sim.have_met(0, b):
		sim.emit_signal("event", "The %s and the %s have formed an alliance." % [ca.name, cb.name], "major")


static func break_alliance(sim: Sim, a: int, b: int) -> void:
	if not sim.alliances.erase(_k(a, b)):
		return
	var key := sim._key(a, b)
	sim.relations[key] = sim.relation(a, b) - 25.0
	if a == 0 or b == 0:
		sim.emit_signal("event", "The alliance with the %s is over." % sim.civ(b if a == 0 else a).name, "major_bad")


## Called when `attacker` declares war on `defender`: the defender's allies join in.
static func call_allies(sim: Sim, attacker: int, defender: int) -> void:
	for ally in allies_of(sim, defender):
		if ally.civ_id == attacker or sim.at_war(ally.civ_id, attacker):
			continue
		if allied(sim, ally.civ_id, attacker):
			break_alliance(sim, ally.civ_id, attacker)     # can't stand on both sides
		if ally.civ_id == 0:
			sim.emit_signal("event", "Your ally the %s was attacked by the %s — you join the war at their side." % [sim.civ(defender).name, sim.civ(attacker).name], "major_bad")
		elif defender == 0:
			sim.emit_signal("event", "Your ally the %s join the war on your side!" % ally.name, "major_good")
		elif attacker == 0:
			sim.emit_signal("event", "The %s honour their alliance with the %s and declare war on you!" % [ally.name, sim.civ(defender).name], "major_bad")
		elif sim.have_met(0, ally.civ_id):
			sim.emit_signal("event", "The %s join the war on the side of the %s." % [ally.name, sim.civ(defender).name], "major")
		sim.declare_war(ally.civ_id, attacker, true)


# ---------------------------------------------------------------- offer making
## Value of goods at base prices.
static func value_of(goods: Dictionary) -> float:
	var v := 0.0
	for k in goods.keys():
		v += float(Defs.BASE_PRICE.get(k, 1.0)) * float(goods[k])
	return v


static func goods_text(goods: Dictionary, talents: int) -> String:
	var parts := PackedStringArray()
	for k in goods.keys():
		parts.append("%d %s" % [int(goods[k]), Defs.item_name(k)])
	if talents > 0:
		parts.append("%d %s" % [talents, Defs.MONEY_NAME])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## A trade `from` would offer `to`: their best surplus for Talents or something they need.
static func make_trade(sim: Sim, from: Colony, to: Colony) -> Dictionary:
	var best := ""
	var best_v := 0.0
	for item in Defs.BASE_PRICE.keys():
		var spare := from.count(item) - (40.0 if not Defs.FOOD.has(item) else maxf(20.0, from.population() * 6.0))
		if spare >= 8.0 and spare * float(Defs.BASE_PRICE[item]) > best_v:
			best_v = spare * float(Defs.BASE_PRICE[item])
			best = item
	if best == "":
		return {}
	var n := int(clampf(floorf((from.count(best) - 30.0) * 0.4), 6.0, 40.0))
	var give := {best: n}
	var worth := value_of(give)
	# what they want back: an item they're short of that the other side has plenty of, else Talents
	var want := {}
	var talents := 0
	for item in ["copper_ore", "tin_ore", "iron_ore", "hides", "stone", "wood", "dried_meat", "crops"]:
		if item == best:
			continue
		var need := from.shortfall(item) > 0.0 or from.count(item) < 10.0
		if need and to.count(item) >= 15.0:
			want[item] = maxi(1, int(ceilf(worth * 0.95 / float(Defs.BASE_PRICE[item]))))
			break
	if want.is_empty():
		talents = maxi(5, int(roundf(worth * 0.9)))
	return {"type": "trade", "give": give, "want": want, "talents": talents}


static func pick_demand_state(sim: Sim, from: Colony, to: Colony) -> int:
	var home_s := sim.states.at(to.home)
	for s in sim.states.owned_by(to.civ_id):
		if s == home_s or not sim.states.borders_civ(s, from.civ_id):
			continue
		var has_building := false
		for b in to.buildings:
			if sim.states.at(b.center_tile()) == s:
				has_building = true
				break
		if not has_building:
			return s
	return -1


## Queues an offer to the player.
static func offer_player(sim: Sim, o: Dictionary) -> void:
	for e in sim.deal_offers:
		if int(e["from"]) == int(o["from"]):
			return
	if sim.deal_offers.size() >= MAX_QUEUE:
		return
	o["id"] = sim.next_deal_id
	sim.next_deal_id += 1
	o["until"] = sim.time.t + OFFER_LIFE
	sim.deal_offers.append(o)
	sim.emit_signal("event", "The %s send an envoy: %s" % [sim.civ(int(o["from"])).name, describe(sim, o)], "info")
	if sim.debug_log:
		answer(sim, o, "accept" if sim.rng.randf() < 0.5 else ("counter" if sim.rng.randf() < 0.5 else "decline"))


## One line describing an offer from the player's point of view.
static func describe(sim: Sim, o: Dictionary) -> String:
	var from := sim.civ(int(o["from"]))
	match str(o["type"]):
		"trade":
			return "they offer %s for %s." % [goods_text(o["give"], 0), goods_text(o["want"], int(o["talents"]))]
		"alliance":
			return "they propose an alliance%s." % ((" and add %d %s as a gift" % [int(o.get("talents", 0)), Defs.MONEY_NAME]) if int(o.get("talents", 0)) > 0 else "")
		"tribute":
			return "they demand tribute of %s, or else." % goods_text(o.get("want", {}), int(o["talents"]))
		"land":
			return "they demand you hand over %s, or else." % sim.states.names[int(o["state"])]
	return "?"


## Counter-offer text for the player's button.
static func counter_text(sim: Sim, o: Dictionary) -> String:
	match str(o["type"]):
		"trade":
			return "Ask for 30% more"
		"alliance":
			return "Only with a %d %s gift" % [ally_gift(sim, o), Defs.MONEY_NAME]
		"tribute":
			return "Offer half (%d)" % maxi(1, int(o["talents"]) / 2)
		"land":
			return "Offer %d %s instead" % [land_price(sim, o), Defs.MONEY_NAME]
	return "Counter"


static func ally_gift(sim: Sim, o: Dictionary) -> int:
	return 40 + 20 * sim.civ(int(o["from"])).era_i


static func land_price(sim: Sim, o: Dictionary) -> int:
	return 80 + 40 * sim.civ(int(o["from"])).era_i


# ---------------------------------------------------------------- answering
## The player's answer: "accept", "decline" or "counter".
static func answer(sim: Sim, o: Dictionary, how: String) -> void:
	sim.deal_offers.erase(o)
	var from := sim.civ(int(o["from"]))
	var me := sim.colony
	if from == null or from.collapsed:
		return
	var key := sim._key(0, from.civ_id)
	var ty := str(o["type"])
	if how == "counter":
		var ch := counter_chance(sim, o)
		if sim.rng.randf() < ch:
			sim.emit_signal("event", "The %s accept your counter-offer." % from.name, "good")
			_apply(sim, _countered(sim, o), true)
		else:
			sim.emit_signal("event", "The %s reject your counter-offer." % from.name, "warn")
			sim.relations[key] = sim.relation(0, from.civ_id) - 3.0
			if ty == "tribute" or ty == "land":
				_refused_demand(sim, o)
		return
	if how == "accept":
		var why := _cant_afford(sim, me, o)
		if why != "":
			sim.emit_signal("event", why, "warn")
			return
		_apply(sim, o, true)
		return
	# declined
	match ty:
		"trade", "alliance":
			sim.emit_signal("event", "You turned down the %s's %s." % [from.name, "trade" if ty == "trade" else "alliance"], "info")
			sim.relations[key] = sim.relation(0, from.civ_id) - (1.0 if ty == "trade" else 4.0)
		_:
			_refused_demand(sim, o)


static func counter_chance(sim: Sim, o: Dictionary) -> float:
	var from := sim.civ(int(o["from"]))
	var rel := sim.relation(0, from.civ_id)
	var ratio := sim.military_strength(from) / maxf(1.0, sim.military_strength(sim.colony))
	match str(o["type"]):
		"trade":
			return clampf(0.45 + rel / 200.0, 0.1, 0.85)
		"alliance":
			return clampf(0.35 + rel / 150.0 + (0.1 if from.money > 150.0 else -0.1), 0.05, 0.85)
		"tribute":
			return clampf(0.65 - (ratio - 1.0) * 0.2, 0.15, 0.9)
		"land":
			return clampf(0.55 - (ratio - 1.0) * 0.2 + (0.15 if from.money < 100.0 else 0.0), 0.1, 0.85)
	return 0.3


static func _countered(sim: Sim, o: Dictionary) -> Dictionary:
	var c := o.duplicate(true)
	match str(o["type"]):
		"trade":
			for k in c["give"].keys():
				c["give"][k] = int(ceilf(float(c["give"][k]) * 1.3))
		"alliance":
			c["talents"] = ally_gift(sim, o)
		"tribute":
			c["talents"] = maxi(1, int(o["talents"]) / 2)
			c["want"] = {}
		"land":
			c["type"] = "tribute"
			c["talents"] = land_price(sim, o)
			c["want"] = {}
	return c


static func _cant_afford(sim: Sim, me: Colony, o: Dictionary) -> String:
	match str(o["type"]):
		"trade", "tribute":
			if me.money < int(o["talents"]):
				return "You don't have %d %s." % [int(o["talents"]), Defs.MONEY_NAME]
			for k in (o.get("want", {}) as Dictionary).keys():
				if me.count(k) < float(o["want"][k]):
					return "You don't have %d %s." % [int(o["want"][k]), Defs.item_name(k)]
		"land":
			if int(sim.states.owners[int(o["state"])]) != 0:
				return "That state is no longer yours."
	return ""


## Carries out a deal between the player and an AI tribe.
static func _apply(sim: Sim, o: Dictionary, to_player: bool) -> void:
	var from := sim.civ(int(o["from"]))
	var me := sim.colony
	var key := sim._key(0, from.civ_id)
	match str(o["type"]):
		"trade":
			if _cant_afford(sim, me, o) != "":
				sim.emit_signal("event", "The trade with the %s fell through: %s" % [from.name, _cant_afford(sim, me, o)], "warn")
				return
			# goods don't fly: your traders walk over with payment and bring the goods back
			Trade.deal_order(sim, from.civ_id, o["give"], o["want"], int(o["talents"]))
			sim.relations[key] = sim.relation(0, from.civ_id) + 4.0
			from.deals_made += 1
			var note := "" if not sim.colony.living().filter(func(q): return q.job == "trader").is_empty() else " Give someone the Trader job (Jobs panel) to carry it out."
			sim.emit_signal("event", "Deal agreed with the %s: %s for %s. Your traders will carry it out.%s" % [from.name, goods_text(o["give"], 0), goods_text(o["want"], int(o["talents"])), note], "good")
		"alliance":
			make_alliance(sim, from.civ_id, 0)
			if int(o.get("talents", 0)) > 0:
				var g := mini(int(o["talents"]), int(from.money))
				from.money -= g
				me.money += g
		"tribute":
			var pay := mini(int(o["talents"]), int(me.money))
			me.money -= pay
			from.money += pay
			for k in (o.get("want", {}) as Dictionary).keys():
				from.add(k, me.take(k, float(o["want"][k])))
			sim.relations[key] = sim.relation(0, from.civ_id) + 6.0
			me.deals_made += 1
			sim.emit_signal("event", "You paid the %s %d %s in tribute. They are satisfied — for now." % [from.name, pay, Defs.MONEY_NAME], "warn")
		"land":
			var s := int(o["state"])
			sim.states.set_owner(s, from.civ_id)
			sim.relations[key] = sim.relation(0, from.civ_id) + 10.0
			me.deals_made += 1
			sim.emit_signal("event", "You handed %s over to the %s." % [sim.states.names[s], from.name], "warn")


## A refused demand: relations sour and a strong tribe may go to war over it.
static func _refused_demand(sim: Sim, o: Dictionary) -> void:
	var from := sim.civ(int(o["from"]))
	var key := sim._key(0, from.civ_id)
	sim.relations[key] = sim.relation(0, from.civ_id) - 15.0
	var ratio := sim.military_strength(from) / maxf(1.0, sim.military_strength(sim.colony))
	var ch := clampf(0.15 + (ratio - 1.0) * 0.3 + (0.15 if str(o["type"]) == "land" else 0.0), 0.05, 0.75)
	if sim.rng.randf() < ch and sim.declare_war(from.civ_id, 0, true):
		return
	sim.emit_signal("event", "The %s are furious that you refused their demand." % from.name, "warn")


# ---------------------------------------------------------------- the player proposes
## "" on success, or why it failed. kind: alliance / trade / tribute / land
static func player_propose(sim: Sim, cid: int, kind: String) -> String:
	var o := sim.civ(cid)
	var me := sim.colony
	var key := sim._key(0, cid)
	var rel := sim.relation(0, cid)
	var ratio := sim.military_strength(me) / maxf(1.0, sim.military_strength(o))
	match kind:
		"alliance":
			if allied(sim, 0, cid):
				return "You are already allied."
			var ch := clampf(0.15 + rel / 100.0, 0.02, 0.9)
			if sim.rng.randf() < ch:
				make_alliance(sim, 0, cid)
				return ""
			sim.relations[key] = rel - 2.0
			return "The %s aren't ready for an alliance (relations must improve)." % o.name
		"trade":
			var t := make_trade(sim, o, me)
			if t.is_empty():
				return "The %s have nothing to spare right now." % o.name
			t["from"] = cid
			offer_player(sim, t)
			return ""
		"tribute":
			var amount := int(clampf(o.money * 0.3, 10.0, 200.0))
			var ch := clampf(0.1 + (ratio - 1.0) * 0.35, 0.03, 0.85)
			if sim.rng.randf() < ch:
				o.money -= amount
				me.money += amount
				sim.relations[key] = rel - 10.0
				me.deals_made += 1
				sim.emit_signal("event", "Cowed by your strength, the %s pay you %d %s." % [o.name, amount, Defs.MONEY_NAME], "good")
				return ""
			sim.relations[key] = rel - 12.0
			return "The %s laugh at your demand for tribute." % o.name
		"land":
			var s := pick_demand_state(sim, me, o)
			if s < 0:
				return "The %s have no border state without buildings to give up." % o.name
			var ch := clampf(0.05 + (ratio - 1.2) * 0.3, 0.02, 0.7)
			if sim.rng.randf() < ch:
				sim.states.set_owner(s, 0)
				sim.relations[key] = rel - 20.0
				me.deals_made += 1
				sim.emit_signal("event", "The %s hand %s over to you rather than fight." % [o.name, sim.states.names[s]], "good")
				return ""
			sim.relations[key] = rel - 18.0
			if sim.rng.randf() < 0.25:
				sim.declare_war(cid, 0, true)
			return "The %s refuse to give up %s." % [o.name, sim.states.names[s]]
	return "?"


# ---------------------------------------------------------------- AI turn
## Hourly for each AI tribe: now and then it proposes something to the player or another tribe.
static func ai_turn(sim: Sim, c: Colony) -> void:
	if sim.rng.randf() > 0.005 or c.era_i < 1 and sim.rng.randf() < 0.5:
		return
	var others: Array = []
	for o in sim.colonies:
		if o != c and not o.collapsed and o.population() > 0 and sim.have_met(c.civ_id, o.civ_id) and not sim.at_war(c.civ_id, o.civ_id):
			others.append(o)
	if others.is_empty():
		return
	var o: Colony = others[sim.rng.randi() % others.size()]
	var rel := sim.relation(c.civ_id, o.civ_id)
	var ratio := sim.military_strength(c) / maxf(1.0, sim.military_strength(o))
	var deal := {}
	if not allied(sim, c.civ_id, o.civ_id) and rel > 35.0 and sim.rng.randf() < 0.5:
		deal = {"type": "alliance", "talents": 0}
	elif ratio > 1.6 and rel < 10.0 and c.era_i >= 1 and sim.rng.randf() < 0.45:
		var s := pick_demand_state(sim, c, o) if c.era_i >= 2 else -1
		if s >= 0 and sim.rng.randf() < 0.4:
			deal = {"type": "land", "state": s}
		else:
			deal = {"type": "tribute", "talents": int(clampf(o.money * 0.25, 15.0, 150.0)), "want": {}}
	else:
		deal = make_trade(sim, c, o)
	if deal.is_empty():
		return
	deal["from"] = c.civ_id
	if o.civ_id == 0:
		offer_player(sim, deal)
		return
	# between two AI tribes: settled on the spot
	var ok := false
	match str(deal["type"]):
		"alliance":
			ok = sim.rng.randf() < clampf(0.2 + rel / 100.0, 0.05, 0.9)
			if ok:
				make_alliance(sim, c.civ_id, o.civ_id)
		"trade":
			ok = sim.rng.randf() < 0.6 and o.money >= int(deal["talents"])
			if ok:
				for k in (deal["give"] as Dictionary).keys():
					o.add(k, c.take(k, float(deal["give"][k])))
				for k in (deal["want"] as Dictionary).keys():
					c.add(k, o.take(k, float(deal["want"][k])))
				o.money -= int(deal["talents"])
				c.money += int(deal["talents"])
				sim.relations[sim._key(c.civ_id, o.civ_id)] = rel + 3.0
		"tribute":
			ok = sim.rng.randf() < clampf(0.3 + (ratio - 1.0) * 0.2, 0.1, 0.8)
			if ok:
				var pay := mini(int(deal["talents"]), int(o.money))
				o.money -= pay
				c.money += pay
			else:
				sim.relations[sim._key(c.civ_id, o.civ_id)] = rel - 15.0
		"land":
			ok = sim.rng.randf() < clampf(0.2 + (ratio - 1.5) * 0.2, 0.05, 0.6)
			if ok:
				sim.states.set_owner(int(deal["state"]), c.civ_id)
				if sim.have_met(0, c.civ_id):
					sim.emit_signal("event", "The %s handed %s to the %s under threat." % [o.name, sim.states.names[int(deal["state"])], c.name], "info")
			else:
				sim.relations[sim._key(c.civ_id, o.civ_id)] = rel - 20.0
	if ok:
		c.deals_made += 1


## Offers to the player that nobody answered in time: demands count as refused.
static func expire(sim: Sim) -> void:
	for o in sim.deal_offers.duplicate():
		if sim.time.t > float(o["until"]):
			sim.deal_offers.erase(o)
			var ty := str(o["type"])
			if ty == "tribute" or ty == "land":
				sim.emit_signal("event", "You ignored the %s's demand." % sim.civ(int(o["from"])).name, "warn")
				_refused_demand(sim, o)


# ---------------------------------------------------------------- save
static func to_dict(sim: Sim) -> Dictionary:
	return {"alliances": sim.alliances.duplicate(), "offers": sim.deal_offers.duplicate(true), "next": sim.next_deal_id}


static func from_dict(sim: Sim, d: Dictionary) -> void:
	sim.alliances = d.get("alliances", {})
	sim.deal_offers = d.get("offers", [])
	sim.next_deal_id = int(d.get("next", 1))
