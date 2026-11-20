class_name Trade
extends RefCounted
## The player's trading. Click another tribe's flag → Trade: buy their goods or people for
## Talents, or sell them your goods. Nothing moves by magic: a Billy with the Trader job walks
## to their camp carrying the goods to sell and the Talents to pay, makes the exchange, and walks
## back with what was bought (bought people walk home on their own). Big orders take several
## trips. With Trade Wagons (Stone Age) a trader carries four times as much.
## Bandits ambush traders who pass near their camps and steal everything they carry.
## (AI tribes still trade with each other and with you the old way, through their own traders.)

const BASE_LOAD := 30          # goods a trader carries per trip (10 Talents count as 1)
const WAGON_LOAD := 120
const MONEY_PER_LOAD := 10.0


static func capacity(c: Colony) -> int:
	return WAGON_LOAD if c.researched.has("pack_carts") or c.cheat else BASE_LOAD


static func has_wagon(c: Colony) -> bool:
	return c.researched.has("pack_carts") or c.cheat


## How far (in tiles, home to home) this tribe's traders will go. Trade Wagons reach further.
## Both distances are world settings (Game Rules → Trade).
static func max_range(c: Colony) -> float:
	return Config.rule("trade_range") + (Config.rule("wagon_trade_bonus") if has_wagon(c) else 0.0)


static func distance(a: Colony, b: Colony) -> float:
	return Vector2(a.home).distance_to(Vector2(b.home))


static func in_range(a: Colony, b: Colony) -> bool:
	return distance(a, b) <= max_range(a)


## "" if the player can trade with this tribe at all.
static func problem(sim: Sim, cid: int) -> String:
	var o := sim.civ(cid)
	if o == null or o.collapsed or o.bandit:
		return "There's no one there to trade with."
	if not sim.have_met(0, cid):
		return "You haven't met them yet."
	if sim.at_war(0, cid):
		return "You're at war with them."
	if sim.relation(0, cid) <= -40.0:
		return "They're too hostile to trade."
	if not sim.land_reachable(sim.colony, o) and not sim.colony.has_built("harbor"):
		return "You can't reach them over land (build a Harbor)."
	if not in_range(sim.colony, o):
		var more := "" if has_wagon(sim.colony) else " Trade Wagons (Stone Age) let them go %d tiles further." % int(Config.rule("wagon_trade_bonus"))
		return "They're too far away: %d tiles, and your traders go at most %d.%s" % [int(distance(sim.colony, o)), int(max_range(sim.colony)), more]
	return ""


static func _reserve(o: Colony, item: String) -> float:
	if Defs.FOOD.has(item):
		return maxf(15.0, o.population() * 5.0)
	return 25.0 + o.shortfall(item)


## Price per unit when the player buys from tribe `o`.
static func buy_price(sim: Sim, o: Colony, item: String) -> float:
	var rel := sim.relation(0, o.civ_id)
	return snappedf(float(Defs.BASE_PRICE.get(item, 1.0)) * clampf(1.35 - rel / 400.0, 1.1, 1.6), 0.1)


## Price per unit tribe `o` pays the player.
static func sell_price(sim: Sim, o: Colony, item: String) -> float:
	var rel := sim.relation(0, o.civ_id)
	var need := 1.3 if o.count(item) < 10.0 else (0.8 if o.count(item) > 80.0 else 1.0)
	return snappedf(float(Defs.BASE_PRICE.get(item, 1.0)) * clampf(0.8 + rel / 400.0, 0.55, 0.95) * need * (1.0 + sim.colony.bonus("trade")), 0.1)


static func available(o: Colony, item: String) -> int:
	return maxi(0, floori(o.count(item) - _reserve(o, item)))


static func person_price(o: Colony, p: Human) -> int:
	var base := 30.0 if p.age_years() < 14.0 else 60.0
	if p.skills.size() > 0:
		var best := 0.0
		for k in p.skills.keys():
			best = maxf(best, float(p.skills[k]))
		base += best * 3.0
	return int(base * (1.0 + 0.4 * o.era_i))


## People a tribe is willing to part with: a man, a woman and a child at most.
static func people_for_sale(sim: Sim, o: Colony) -> Array:
	if o.population() < 6 or sim.relation(0, o.civ_id) < -20.0:
		return []
	var man: Human = null
	var woman: Human = null
	var child: Human = null
	for p in o.living():
		if p.id == o.leader_id or p.job == "soldier" or p.at_sea() or p.pregnant_days >= 0.0:
			continue
		var a = p.age_years()
		if a >= 16.0 and a <= 45.0:
			if p.gender == "M" and man == null:
				man = p
			elif p.gender == "F" and woman == null:
				woman = p
		elif a >= 3.0 and a < 14.0 and child == null:
			child = p
	return [man, woman, child].filter(func(x): return x != null)


# ---------------------------------------------------------------- orders
## Places a trade order. buy/sell: item -> amount. people: ids to buy. Returns "" or a problem.
static func place_order(sim: Sim, cid: int, buy: Dictionary, sell: Dictionary, people: Array) -> String:
	var why := problem(sim, cid)
	if why != "":
		return why
	var c := sim.colony
	var o := sim.civ(cid)
	var prices := {"buy": {}, "sell": {}, "people": {}}
	var cost := 0.0
	for k in buy.keys():
		if int(buy[k]) <= 0:
			buy.erase(k)
			continue
		prices["buy"][k] = buy_price(sim, o, k)
		cost += float(prices["buy"][k]) * int(buy[k])
	for k in sell.keys():
		if int(sell[k]) <= 0:
			sell.erase(k)
			continue
		if c.count(k) < float(sell[k]):
			return "You only have %d %s." % [int(c.count(k)), Defs.item_name(k)]
		prices["sell"][k] = sell_price(sim, o, k)
	for pid in people:
		var q := sim.person(int(pid))
		if q != null:
			prices["people"][int(pid)] = person_price(o, q)
			cost += float(prices["people"][int(pid)])
	if buy.is_empty() and sell.is_empty() and people.is_empty():
		return "Choose something to buy or sell."
	var income := 0.0
	for k in sell.keys():
		income += float(prices["sell"][k]) * int(sell[k])
	if cost - income > c.money + 0.01:
		return "That costs %d %s more than you'll earn — you have %d." % [int(cost - income), Defs.MONEY_NAME, int(c.money)]
	var order := {"id": sim.next_deal_id, "civ": cid, "buy": buy.duplicate(), "sell": sell.duplicate(), "people": people.duplicate(),
		"prices": prices, "trader": -1, "got": {}, "gave": {}, "spent": 0.0, "earned": 0.0}
	sim.next_deal_id += 1
	c.trade_orders.append(order)
	return ""


## An order made from an accepted envoy deal: fixed total payment for their goods.
static func deal_order(sim: Sim, cid: int, give: Dictionary, want: Dictionary, talents: int) -> void:
	var units := 0
	for k in give.keys():
		units += int(give[k])
	var prices := {"buy": {}, "sell": {}, "people": {}}
	for k in give.keys():
		prices["buy"][k] = float(talents) / maxf(1.0, units)
	for k in want.keys():
		prices["sell"][k] = 0.0
	sim.colony.trade_orders.append({"id": sim.next_deal_id, "civ": cid, "buy": give.duplicate(), "sell": want.duplicate(), "people": [],
		"prices": prices, "trader": -1, "got": {}, "gave": {}, "spent": 0.0, "earned": 0.0, "deal": true})
	sim.next_deal_id += 1


static func order_by_id(c: Colony, oid: int) -> Dictionary:
	for o in c.trade_orders:
		if int(o["id"]) == oid:
			return o
	return {}


static func cancel(sim: Sim, oid: int) -> void:
	var c := sim.colony
	var o := order_by_id(c, oid)
	if o.is_empty():
		return
	c.trade_orders.erase(o)


static func order_left(o: Dictionary) -> bool:
	for k in o["buy"].keys():
		if int(o["buy"][k]) > 0:
			return true
	for k in o["sell"].keys():
		if int(o["sell"][k]) > 0:
			return true
	return not (o["people"] as Array).is_empty()


static func describe(sim: Sim, o: Dictionary) -> String:
	var parts := PackedStringArray()
	var b := PackedStringArray()
	for k in o["buy"].keys():
		if int(o["buy"][k]) > 0:
			b.append("%d %s" % [int(o["buy"][k]), Defs.item_name(k)])
	for pid in o["people"]:
		var q := sim.person(int(pid))
		if q != null:
			b.append(q.name)
	if not b.is_empty():
		parts.append("buy " + ", ".join(b))
	var sl := PackedStringArray()
	for k in o["sell"].keys():
		if int(o["sell"][k]) > 0:
			sl.append("%d %s" % [int(o["sell"][k]), Defs.item_name(k)])
	if not sl.is_empty():
		parts.append("sell " + ", ".join(sl))
	return "; ".join(parts) if not parts.is_empty() else "done"


# ---------------------------------------------------------------- the trader's trips
## Called from the trader's planning: start the next trip of an open order. True if under way.
static func plan_trip(sim: Sim, p: Human) -> bool:
	var c := sim.col_of(p)
	var order := {}
	for o in c.trade_orders:
		var tr := sim.person(int(o["trader"]))
		if int(o["trader"]) == p.id or tr == null or not tr.alive or tr.job != "trader":
			order = o
			break
	if order.is_empty():
		return false
	var partner := sim.civ(int(order["civ"]))
	if problem(sim, partner.civ_id) != "":
		sim.emit_signal("event", "The trade order with the %s was cancelled: %s" % [partner.name, problem(sim, partner.civ_id)], "warn")
		c.trade_orders.erase(order)
		return false
	order["trader"] = p.id
	var cap := capacity(c)
	# outbound: goods to sell
	var load := 0
	var pack := {}
	for k in order["sell"].keys():
		var n := mini(int(order["sell"][k]), cap - load)
		n = mini(n, int(c.count(k)))
		if n > 0:
			c.take(k, n)
			pack[k] = n
			load += n
	var income := 0.0
	for k in pack.keys():
		income += float(order["prices"]["sell"][k]) * int(pack[k])
	# what to buy this trip: as much as fits on the way back and the bank can pay for
	var trip_buy := {}
	var back := 0
	var cost := 0.0
	for k in order["buy"].keys():
		var n := mini(int(order["buy"][k]), cap - back)
		var price := float(order["prices"]["buy"][k])
		while n > 0 and cost + n * price - income > c.money:
			n -= 1
		if n > 0:
			trip_buy[k] = n
			back += n
			cost += n * price
	var trip_people: Array = []
	for pid in order["people"]:
		var price := float(order["prices"]["people"].get(int(pid), 0))
		if cost + price - income <= c.money:
			trip_people.append(int(pid))
			cost += price
	var money := maxf(0.0, cost - income)
	# Talents take room too
	while money > 0.0 and load + ceili(money / MONEY_PER_LOAD) > cap and not trip_buy.is_empty():
		var k: String = trip_buy.keys()[0]
		trip_buy[k] = int(trip_buy[k]) - 1
		cost -= float(order["prices"]["buy"][k])
		if int(trip_buy[k]) <= 0:
			trip_buy.erase(k)
		money = maxf(0.0, cost - income)
	if pack.is_empty() and trip_buy.is_empty() and trip_people.is_empty():
		for k in pack.keys():
			c.add(k, float(pack[k]))
		return false
	money = minf(money, c.money)
	c.money -= money
	p.carrying = pack
	p.task_memory["order"] = int(order["id"])
	p.task_memory["trade_money"] = money
	p.task_memory["trip_buy"] = trip_buy
	p.task_memory["trip_people"] = trip_people
	p.task_memory["trade_civ"] = partner.civ_id
	p.task_memory["trade_until"] = sim.time.t + maxf(6.0, max_range(c) / 30.0)
	if HumanAI._start_trade_trip(sim, p, c, partner):
		return true
	# couldn't set off: put everything back
	_unpack(sim, p, c)
	return false


static func _unpack(sim: Sim, p: Human, c: Colony) -> void:
	for k in p.carrying.keys():
		c.add(str(k), float(p.carrying[k]))
	p.carrying = {}
	c.money += float(p.task_memory.get("trade_money", 0.0))
	for key in ["order", "trade_money", "trip_buy", "trip_people", "trade_civ"]:
		p.task_memory.erase(key)


## At the other tribe's camp: sell, pay, buy, and set off home.
static func exchange(sim: Sim, p: Human, c: Colony, o: Colony) -> void:
	var order := order_by_id(c, int(p.task_memory.get("order", -1)))
	var money := float(p.task_memory.get("trade_money", 0.0))
	var got := PackedStringArray()
	var gave := PackedStringArray()
	if order.is_empty():
		# the order was cancelled on the way: just come home
		p.task_memory.erase("order")
		return
	# sell what we carried, as far as they can pay
	for k in p.carrying.keys():
		var n := int(p.carrying[k])
		var price := float(order["prices"]["sell"].get(k, 0.0))
		if price > 0.0:
			n = mini(n, floori(o.money / price))
		if n <= 0:
			continue
		o.add(k, n)
		o.money -= n * price
		money += n * price
		order["earned"] = float(order["earned"]) + n * price
		p.carrying[k] = int(p.carrying[k]) - n
		order["sell"][k] = maxi(0, int(order["sell"][k]) - n)
		gave.append("%d %s" % [n, Defs.item_name(k)])
	for k in p.carrying.keys().duplicate():
		if int(p.carrying[k]) <= 0:
			p.carrying.erase(k)
	# buy goods
	var trip_buy: Dictionary = p.task_memory.get("trip_buy", {})
	for k in trip_buy.keys():
		var price := float(order["prices"]["buy"][k])
		var n := mini(int(trip_buy[k]), int(o.count(k)) if order.get("deal", false) else available(o, k))
		n = mini(n, floori(money / maxf(0.01, price)) if price > 0.0 else n)
		if n > 0:
			o.take(k, n)
			o.money += n * price
			money -= n * price
			order["spent"] = float(order["spent"]) + n * price
			p.add_carry(k, n)
			got.append("%d %s" % [n, Defs.item_name(k)])
		# what they couldn't supply is dropped from the order
		order["buy"][k] = maxi(0, int(order["buy"][k]) - int(trip_buy[k]))
	# buy people: they walk to your village themselves
	for pid in p.task_memory.get("trip_people", []):
		var q := sim.person(int(pid))
		var price := float(order["prices"]["people"].get(int(pid), 0))
		(order["people"] as Array).erase(int(pid))
		if q == null or not q.alive or q.civ_id != o.civ_id or q.id == o.leader_id or money < price:
			continue
		money -= price
		o.money += price
		order["spent"] = float(order["spent"]) + price
		Politics.move_people(sim, [q], o, c)
		got.append(q.name)
	sim.relations[sim._key(0, o.civ_id)] = sim.relation(0, o.civ_id) + 2.0
	p.task_memory["trade_money"] = money
	for key in ["trip_buy", "trip_people"]:
		p.task_memory.erase(key)
	if not got.is_empty() or not gave.is_empty():
		var t := "Your trader %s reached the %s" % [p.name, o.name]
		if not gave.is_empty():
			t += ", sold %s" % ", ".join(gave)
		if not got.is_empty():
			t += "%s bought %s" % [" and" if not gave.is_empty() else ",", ", ".join(got)]
		sim.emit_signal("event", t + ". Heading home.", "good")
	else:
		sim.emit_signal("event", "Your trader %s reached the %s, but they had nothing left to trade. Heading home." % [p.name, o.name], "warn")
	if not order_left(order):
		c.trade_orders.erase(order)
		c.deals_made += 1
		sim.emit_signal("event", "Trade order with the %s complete." % o.name, "good")


## Back home with the money (goods are hauled to the stockpile as usual).
static func bank(sim: Sim, p: Human) -> void:
	var m := float(p.task_memory.get("trade_money", 0.0))
	if m > 0.0:
		sim.col_of(p).money += m
		p.task_memory["trade_money"] = 0.0
	p.task_memory.erase("order")


static func on_trader_robbed(sim: Sim, p: Human) -> void:
	for key in ["trip_buy", "trip_people", "trade_civ"]:
		p.task_memory.erase(key)
	p.task_memory.erase("order")


# ---------------------------------------------------------------- save
static func load_orders(c: Colony) -> void:
	for o in c.trade_orders:
		var pp := {}
		for k in (o["prices"]["people"] as Dictionary).keys():
			pp[int(k)] = o["prices"]["people"][k]
		o["prices"]["people"] = pp
