class_name BattleSetup
extends RefCounted

## Builds battle stacks from two armies: player in column 0, enemy in the last column.

static func build_stacks(player: ArmyData, enemy: ArmyData, split_neutral := false) -> Array:
	var out: Array = []
	out.append_array(_place(player, 0, 0))
	out.append_array(_place_neutral(enemy, 1, Hex.COLS - 1) if split_neutral \
			else _place(enemy, 1, Hex.COLS - 1))
	return out

static func _place_neutral(army: ArmyData, side: int, col: int) -> Array:
	if army == null or army.slots.size() != 1:
		return _place(army, side, col)
	var slot: Dictionary = army.slots[0]
	var total := int(slot.count)
	if total <= 0:
		return []
	var out: Array = []
	if total == 1:
		var stack := BattleStack.new()
		if stack.setup(String(slot.unit), 1, side, Vector2i(col, 2)):
			out.append(stack)
		return out
	if total == 2:
		for row in [1, 3]:
			var stack := BattleStack.new()
			if stack.setup(String(slot.unit), 1, side, Vector2i(col, row)):
				out.append(stack)
		return out
	if total == 3:
		for row in [1, 2, 3]:
			var stack := BattleStack.new()
			if stack.setup(String(slot.unit), 1, side, Vector2i(col, row)):
				out.append(stack)
		return out
	if total == 4:
		for row in [0, 1, 3, 4]:
			var stack := BattleStack.new()
			if stack.setup(String(slot.unit), 1, side, Vector2i(col, row)):
				out.append(stack)
		return out

	var base := total / Hex.ROWS
	var remainder := total % Hex.ROWS
	for row in Hex.ROWS:
		var count := base + (1 if row < remainder else 0)
		if count <= 0:
			continue
		var stack := BattleStack.new()
		if stack.setup(String(slot.unit), count, side, Vector2i(col, row)):
			out.append(stack)
	return out

## Convenience: enemy given as [[unit, count], ...].
static func from_units(player: ArmyData, enemy_units: Array) -> Array:
	var e := ArmyData.new()
	for u: Array in enemy_units:
		e.add(String(u[0]), int(u[1]))
	return build_stacks(player, e)

static func _place(army: ArmyData, side: int, col: int) -> Array:
	if army == null:
		return []
	var n := army.slots.size()
	var out: Array = []
	# The row of a stack is its army column, and every column holds one stack at
	# most. Resolving the columns (rather than falling back to the slot index)
	# keeps a stack that joined after a death off an occupied row: the slot
	# index drifts from the column as soon as a stack leaves a gap behind.
	var res := army.resolved_columns()
	for i: int in n:
		var slot: Dictionary = army.slots[i]
		var s := BattleStack.new()
		var r: int = res[i] if i < res.size() else -1
		if r < 0 or r >= Hex.ROWS:
			r = formation_row(i, n)
		if s.setup(slot.unit, slot.count, side, Vector2i(col, r)):
			s.slot_col = r
			out.append(s)
	# Equal speeds act top row first (KB turn-order.md 3.5), and TurnQueue takes
	# the first stack it meets, so the list runs by row, not by joining order.
	out.sort_custom(func(a: BattleStack, b: BattleStack) -> bool: return a.slot_col < b.slot_col)
	return out

## HOMM1 rigid slot binding (KB heroes.md): army slot i lands on battlefield
## row i, top to bottom — empty slots leave empty rows, stacks never shift up.
static func formation_row(i: int, _n: int) -> int:
	return clampi(i, 0, Hex.ROWS - 1)
