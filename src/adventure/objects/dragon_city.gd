class_name DragonCity
extends MapObject

## Dragon City (KB objects.md §7.2).
## Guarded by 5 single-unit dragon stacks (the note's "5 dragon stacks",
## one dragon per stack).
## Mine-shaped, NOT loot-once: one battle, then win -> capture (owner flips,
## like a Mine) -> the SAME site yields 1000 gold/day forever after via the
## existing per-owner advance_day sweep. `guarded_pickup`'s looted/rolled_band
## one-shot-reward shape does NOT fit this (there's no reward band to roll —
## capture itself IS the reward, paid out daily), so this is its own subclass
## mirroring Mine's owner/guard/daily_yield fields instead.

var guard: ArmyData = null
## Transient: set by the Yes on the "Do you wish to attack?" prompt so the
## resolver's immediate second visit goes on to the battle. Never saved.
var entry_confirmed: bool = false

func _init() -> void:
	type = "dragon_city"

func is_armed() -> bool:
	return guard != null and not guard.is_empty()

## Gold added per end-of-day while owned (authentic: note's flat 1000/day).
func daily_yield() -> Dictionary:
	return {"gold": 1000}

func save_state() -> Dictionary:
	var d := super.save_state()
	d["owner"] = owner
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	owner = int(s.get("owner", -1))

func to_spec() -> Dictionary:
	var d := super.to_spec()
	if guard != null and not guard.is_empty():
		d["guard"] = MapObject.army_rows(guard)
	return d
