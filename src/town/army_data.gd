class_name ArmyData
extends RefCounted

## A hero/garrison army: up to 5 stacks of { unit, count }. Reused by hero + battle.

const MAX_SLOTS := 5

var slots: Array = []   # Array of { unit: String, count: int }

func add(unit: String, n: int, merge: bool = true) -> bool:
	if n <= 0:
		return false
	if merge:
		for s: Dictionary in slots:
			if s.unit == unit:
				s.count += n
				return true
	if slots.size() >= MAX_SLOTS:
		return false
	var slot := {"unit": unit, "count": n}
	var c := first_free_column()
	if c >= 0:
		slot["col"] = c
	slots.append(slot)
	return true

## The lowest column no stack has claimed yet. A stack that joins an army takes
## the slot a dead stack left behind, so the join fills the gap the hero screen
## shows instead of piling onto a row that is already taken (KB battlefield.md
## 2.1: army slots 0-4 map top to bottom onto battlefield rows 0-4).
func first_free_column() -> int:
	var res := resolved_columns()
	for c in MAX_SLOTS:
		var taken := false
		for r: int in res:
			if r == c:
				taken = true
				break
		if not taken:
			return c
	return -1

## The column every stack ends up in, in slot order. A stack that remembers its
## column keeps it; the rest take the lowest free column. Two stacks never
## share a column, so two stacks never stand on the same battlefield row.
func resolved_columns() -> Array:
	var out: Array = []
	out.resize(slots.size())
	out.fill(-1)
	var taken: Array = []
	taken.resize(MAX_SLOTS)
	taken.fill(false)
	for i in slots.size():
		var s: Dictionary = slots[i]
		var c := int(s.get("col", -1))
		if c >= 0 and c < MAX_SLOTS and not taken[c]:
			taken[c] = true
			out[i] = c
	for i in slots.size():
		if int(out[i]) >= 0:
			continue
		for c in MAX_SLOTS:
			if not taken[c]:
				taken[c] = true
				out[i] = c
				break
	return out

## True if the army can accommodate more units of the given type:
## either by merging into an existing slot of the same unit, or if an empty slot exists.
func can_add(unit: String) -> bool:
	for s: Dictionary in slots:
		if s.unit == unit:
			return true
	return slots.size() < MAX_SLOTS


## Pull `other`'s stacks in here, strongest unit first, without disturbing the
## slots already arranged in this army: each stack merges into a matching slot
## or takes a free one, and whatever finds neither stays in `other`. This is how
## a town garrison joins the hero holding its gate.
func absorb(other: ArmyData) -> int:
	if other == null or other == self or other.slots.is_empty():
		return 0
	var order: Array = []
	for i in other.slots.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return ArmyStrength.unit_power(String(other.slots[a].unit)) \
				> ArmyStrength.unit_power(String(other.slots[b].unit)))
	var joined := {}
	var moved := 0
	for i: int in order:
		var stack: Dictionary = other.slots[i]
		var unit := String(stack.unit)
		var count := int(stack.count)
		if count <= 0 or not can_add(unit):
			continue
		if add(unit, count):
			joined[i] = true
			moved += count
	var left: Array = []
	for i in other.slots.size():
		if not joined.has(i):
			left.append(other.slots[i])
	other.slots = left
	return moved

## The army as a MAX_SLOTS-long column array (null for a gap). Each stack sits in
## its remembered `col`; stacks without a usable one take the first free column.
func to_columns() -> Array:
	var cols: Array = []
	cols.resize(MAX_SLOTS)
	cols.fill(null)
	var res := resolved_columns()
	for i in slots.size():
		var c: int = res[i]
		if c >= 0:
			cols[c] = slots[i]
	return cols

## Inverse of to_columns: stamp each stack's column and keep column order.
func set_columns(cols: Array) -> void:
	var ordered: Array = []
	for c in cols.size():
		var s = cols[c]
		if s != null:
			s["col"] = c
			ordered.append(s)
	slots = ordered

func count_of(unit: String) -> int:
	var total_count := 0
	for s: Dictionary in slots:
		if s.unit == unit:
			total_count += s.count
	return total_count

func total() -> int:
	var t := 0
	for s: Dictionary in slots:
		t += s.count
	return t

func is_empty() -> bool:
	return total() == 0

## --- save/load ---

func to_dict() -> Dictionary:
	var out: Array = []
	for s: Dictionary in slots:
		var d := {"unit": String(s.unit), "count": int(s.count)}
		if s.has("col"):
			d["col"] = int(s.col)
		out.append(d)
	return {"slots": out}

static func from_dict(d: Dictionary) -> ArmyData:
	var a := ArmyData.new()
	for s in d.get("slots", []):
		if s is Dictionary:
			if a.add(String((s as Dictionary).get("unit", "")), int((s as Dictionary).get("count", 0)), false) \
					and (s as Dictionary).has("col"):
				a.slots[-1]["col"] = int((s as Dictionary).col)
	return a

