class_name Fx
extends RefCounted
## Short-lived combat effects: slashes, bites, impact bursts, blood, dust puffs, damage numbers,
## the attacker's lunge and the victim's flash. Pure visuals: they are queued on the Sim
## (sim.fx) and drawn and aged by the EntityLayer. Nothing here changes the simulation.

const MAX := 400


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _push(sim: Sim, e: Dictionary) -> void:
	if not sim.fx_on:
		return
	e["t0"] = now()
	e["seed"] = sim.rng.randi() if not e.has("seed") else e["seed"]
	sim.fx.append(e)
	if sim.fx.size() > MAX:
		sim.fx = sim.fx.slice(sim.fx.size() - MAX)


## The striker lunges toward its target (people and animals alike).
static func lunge(who: Object, toward: Vector2) -> void:
	var p: Vector2 = who.get("pos")
	var d := toward - p
	who.set("strike_at", now())
	who.set("strike_dir", d.normalized() if d.length() > 0.01 else Vector2.RIGHT)


## The one who got hit flashes and is knocked back a little.
static func hurt(who: Object, from: Vector2) -> void:
	var p: Vector2 = who.get("pos")
	var d := p - from
	who.set("hurt_at", now())
	who.set("hurt_dir", d.normalized() if d.length() > 0.01 else Vector2.LEFT)


## A landed blow. style: "slash" (blades), "blunt" (clubs, stones, fists), "pierce" (spears,
## arrows), "bite" (teeth and claws).
static func hit(sim: Sim, at: Vector2, from: Vector2, dmg: float, style := "blunt", blood := true, metal := Color(0.92, 0.92, 0.88)) -> void:
	var dir := (at - from).normalized() if (at - from).length() > 0.01 else Vector2.RIGHT
	_push(sim, {"k": style, "p": at + Vector2(0, -6), "d": dir, "dur": 0.32, "c": metal})
	_push(sim, {"k": "burst", "p": at + Vector2(0, -6), "d": dir, "dur": 0.22, "s": clampf(dmg / 12.0, 0.6, 1.8)})
	if blood:
		_push(sim, {"k": "blood", "p": at + Vector2(0, -6), "d": dir, "dur": 0.7, "n": clampi(int(dmg / 3.0) + 3, 3, 10)})
		if dmg >= 6.0:
			_push(sim, {"k": "stain", "p": at + dir * 4.0 + Vector2(0, 3), "dur": 20.0, "s": clampf(dmg / 10.0, 0.6, 1.6)})
	_push(sim, {"k": "num", "p": at + Vector2(0, -16), "dur": 0.9, "v": int(ceilf(dmg))})


## A swing that found only air.
static func miss(sim: Sim, at: Vector2, from: Vector2) -> void:
	var dir := (at - from).normalized() if (at - from).length() > 0.01 else Vector2.RIGHT
	_push(sim, {"k": "whiff", "p": from + dir * 6.0 + Vector2(0, -6), "d": dir, "dur": 0.25})
	_push(sim, {"k": "dust", "p": at + Vector2(0, 2), "dur": 0.5})


## Stone, wood and dust flying off a wall or hut under attack.
static func smash(sim: Sim, at: Vector2, from: Vector2) -> void:
	var dir := (at - from).normalized() if (at - from).length() > 0.01 else Vector2.RIGHT
	_push(sim, {"k": "chips", "p": at, "d": dir, "dur": 0.6, "n": 6})
	_push(sim, {"k": "dust", "p": at, "dur": 0.6})


## Blow style and colour for a person's strike.
static func style_of(p: Human) -> Array:
	if p.weapon == "":
		return ["blunt", Color(0.9, 0.86, 0.78)]
	var wd: Dictionary = Defs.weapon(p.weapon)
	var metal: Color = [Color(0.7, 0.68, 0.62), Color(0.7, 0.68, 0.62), Color(0.95, 0.70, 0.35), Color(0.85, 0.88, 0.94)][int(wd["era"])]
	var n := str(wd["name"]).to_lower()
	if float(wd["range"]) > 2.0 or n.contains("spear") or n.contains("javelin") or n.contains("pike"):
		return ["pierce", metal]
	if n.contains("sword") or n.contains("axe") or n.contains("blade") or n.contains("knife") or n.contains("dagger") or n.contains("sickle"):
		return ["slash", metal]
	return ["blunt", metal]
