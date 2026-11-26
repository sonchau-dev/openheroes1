class_name ResourcePile
extends MapObject

## One-time pickup. Grants `amount` of `res`, then disappears.

var res: String = "gold"
var amount: int = 0
var amount_authored: bool = false   # true when the map file pinned the amount (saver re-emits it)

func _init() -> void:
	type = "resource"
# `consumed` is the base MapObject field; base save_state()/apply_state()
# persist it. The resource and amount ride along too: the loader rolls them
# from the map's seed, so a change to that roll must not alter a pile in a run.

func save_state() -> Dictionary:
	var d := super.save_state()
	d["res"] = res
	d["amount"] = amount
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	res = String(s.get("res", res))
	amount = int(s.get("amount", amount))

func to_spec() -> Dictionary:
	var d := super.to_spec()
	d["res"] = res
	if amount_authored:
		d["amount"] = amount
	return d
