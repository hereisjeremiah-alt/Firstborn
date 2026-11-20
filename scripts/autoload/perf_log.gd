extends Node
## Timing totals for the --perf check (ms per section, summed until read).

var totals := {}
var on := false


func add(key: String, ms: float) -> void:
	if on:
		totals[key] = float(totals.get(key, 0.0)) + ms


func take() -> Dictionary:
	var t := totals
	totals = {}
	return t
