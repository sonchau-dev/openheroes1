class_name TurnQueue
extends RefCounted

## Native HOMM1 turn selection. Each side preserves army-slot order among equal
## speeds. Across sides, the faster candidate acts; exact speed ties go to the
## side opposite the last stack that performed a full action.

## Single-Stack Defender Exception (data/knowledge_base/spells.md §5.4:125):
## When the attacking and defending sides have armies equal in top speed, the
## attacker normally moves first. But if the attacking side has multiple stacks
## and the defender has only a single stack, the defending side moves first!
static func initial_preferred_side(stacks: Array, default_side: int = 0) -> int:
	var atk_side := default_side if (default_side == 0 or default_side == 1) else 0
	var def_side := 1 - atk_side
	var atk_stacks := []
	var def_stacks := []
	var atk_max_speed := -1
	var def_max_speed := -1
	for stack: BattleStack in stacks:
		if not stack.is_alive() or stack.side < 0 or stack.side > 1:
			continue
		if stack.side == atk_side:
			atk_stacks.append(stack)
			if stack.effective_speed() > atk_max_speed:
				atk_max_speed = stack.effective_speed()
		elif stack.side == def_side:
			def_stacks.append(stack)
			if stack.effective_speed() > def_max_speed:
				def_max_speed = stack.effective_speed()
	if atk_max_speed == def_max_speed and atk_max_speed >= 0:
		if atk_stacks.size() > 1 and def_stacks.size() == 1:
			return def_side
	return atk_side

static func next(stacks: Array, acted: Dictionary = {},
		preferred_side := 0) -> BattleStack:
	var candidates: Array = [null, null]
	for stack: BattleStack in stacks:
		if not stack.is_alive() or acted.has(stack) or stack.turn_spent \
				or stack.side < 0 or stack.side > 1:
			continue
		var current: BattleStack = candidates[stack.side]
		if current == null \
				or stack.effective_speed() > current.effective_speed():
			candidates[stack.side] = stack
	var attacker: BattleStack = candidates[0]
	var defender: BattleStack = candidates[1]
	if attacker == null:
		return defender
	if defender == null:
		return attacker
	if attacker.effective_speed() > defender.effective_speed():
		return attacker
	if defender.effective_speed() > attacker.effective_speed():
		return defender
	return candidates[preferred_side] \
			if preferred_side >= 0 and preferred_side <= 1 \
			else attacker

