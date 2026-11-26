class_name Shrine
extends MapObject

## Shrine (Sanctuary) (KB objects.md:126): teaches one spell of level 1-3 to a
## visiting hero who carries a spellbook. Level odds are 40% L1 / 40% L2 / 20% L3,
## rolled once when the shrine spawns; within a level the same guild weights as
## SpellData.roll_guild_spells apply (e.g. Bless is 25% within L1). Revisiting
## just re-learns the same spell, which refreshes its charges to effective Knowledge.
## A hero with no spellbook cannot learn here at all.

var spell_id: String = ""

func roll_spell(rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	var level := 1 if r < 0.4 else (2 if r < 0.8 else 3)
	var picked := SpellData.roll_guild_spells(level, 1, rng)
	if not picked.is_empty():
		spell_id = picked[0]

## Learn spell_id into hero's spellbook (sets charges to effective Knowledge). Returns
## false (no-op) if the hero has no spellbook or the shrine hasn't rolled yet.
func teach(hero: HeroModel) -> bool:
	if not hero.has_spellbook or spell_id == "":
		return false
	hero.spellbook.learn(spell_id, hero.effective_knowledge())
	return true

func save_state() -> Dictionary:
	var d := super.save_state()
	d["spell_id"] = spell_id
	return d

func apply_state(s: Dictionary) -> void:
	super.apply_state(s)
	spell_id = String(s.get("spell_id", spell_id))
