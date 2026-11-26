class_name Spellbook
extends RefCounted

## HOMM1 charge model (KB spells.md 5.1): no mana pool. Each known spell holds
## its own charge count, set to the hero's Knowledge when learned/refreshed.
## A spell at 0 charges disappears from the book.

var spells: Dictionary = {}  # id: String -> charges: int

func learn(id: String, knowledge: int) -> void:
	if knowledge <= 0:
		return
	spells[id] = knowledge

func knows(id: String) -> bool:
	return spells.has(id)

func charges(id: String) -> int:
	return spells.get(id, 0)

func cast(id: String) -> bool:
	if not spells.has(id):
		return false
	spells[id] -= 1
	if spells[id] <= 0:
		spells.erase(id)
	return true

func refresh_all(knowledge: int) -> void:
	if knowledge <= 0:
		return
	for id in spells.keys():
		spells[id] = knowledge

func battle_spells() -> Array:
	return _filtered("battle")

func map_spells() -> Array:
	return _filtered("map")

## Learn order, as the DOS book shows it (heroes.exe 0x7df0c reads the hero's
## spell slots in order; 0xb0c58 fills the first free slot, 0xb0b4c closes the
## gap when a spell's last charge is spent). The Dictionary keeps insertion
## order, and a spent spell is erased, so a relearned one goes to the end.
func _filtered(context: String) -> Array:
	return spells.keys().filter(
		func(id): return SpellData.get_spell(id).get("context", "") == context)

## --- save/load ---

func to_dict() -> Dictionary:
	var out := {}
	for id in spells:
		out[String(id)] = int(spells[id])
	return {"spells": out}

static func from_dict(d: Dictionary) -> Spellbook:
	var b := Spellbook.new()
	var src: Dictionary = d.get("spells", {})
	for id in src:
		var n := int(src[id])
		if n > 0:
			b.spells[String(id)] = n
	return b
