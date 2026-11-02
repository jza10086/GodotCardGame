extends RefCounted
## Deterministic physical seat numbers, clockwise from seat 1.
## Player IDs are nonempty unique strings, retained in the supplied order.
static func allocate(player_ids: Array) -> Dictionary:
	if player_ids.size() < 2 or player_ids.size() > 8: return {}
	var result := {}
	for i in player_ids.size():
		var id: Variant = player_ids[i]
		if not (id is String or id is StringName) or String(id).strip_edges().is_empty(): return {}
		var key := String(id)
		if result.has(key): return {}
		result[key] = 1 + floori(8.0 * i / player_ids.size() + 0.5)
	return result
