extends RefCounted

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	# heroes.exe (0xb3899) says nothing at a whirlpool: its message 0x43 is
	# never referenced. It takes the loss first (0xb5c59), then carries the
	# ship to another whirlpool, or leaves it where it is when there is none.
	var result := VisitResult.new()
	if ctx.hero_model == null or ctx.hero_model.travel_mode != &"sea":
		return result
	# Computer players pass whirlpools without losses (KB objects.md §7.2).
	var is_ai := false
	if ctx.player_state != null:
		is_ai = ctx.player_state.is_ai
	elif Game.state != null:
		var p: PlayerState = Game.state.player_of(ctx.player_side)
		if p != null:
			is_ai = p.is_ai
	if not is_ai:
		_apply_human_loss(ctx.hero_model.army, result)
	var destinations: Array = []
	for other: MapObject in ctx.map.objects:
		if other.type == "whirlpool" and other.id != obj.id \
				and not ctx.occupied_tiles.has(other.action_tile):
			destinations.append(other.action_tile)
	if not destinations.is_empty():
		result.teleport_to = destinations[Game.rng.randi_range(0, destinations.size() - 1)]
	return result

static func _apply_human_loss(army: ArmyData, result: VisitResult) -> void:
	if army == null or army.slots.is_empty():
		return
	# KB objects.md §7.2: If army has only one creature (one stack with one creature), no loss
	if army.total() <= 1:
		return
	# Probability of passing without losses = 2/3 (66.7%); loss on 1/3 (rand 1..3 == 1)
	if Game.rng.randi_range(1, 3) != 1:
		return
	# heroes.exe 0xb5cab: the stack with the lowest count x creature rating
	# loses half (the leftmost on a tie, strict '<').
	var weakest := 0
	var weakest_value := _stack_value(army.slots[0])
	for i in range(1, army.slots.size()):
		var value := _stack_value(army.slots[i])
		if value < weakest_value:
			weakest = i
			weakest_value = value
	var survivors := int(army.slots[weakest].count) / 2
	if survivors <= 0:
		army.slots.remove_at(weakest)
	else:
		army.slots[weakest].count = survivors

static func _stack_value(slot: Dictionary) -> float:
	return float(slot.get("count", 0)) * ArmyStrength.unit_power(String(slot.get("unit", "")))
