extends RefCounted
## Shrine: teaches its rolled spell to a spellbook-carrying hero (KB objects.md:126).

const INTRO_WITH_BOOK := "Nestled in a small hidden shrine is an ancient wooden altar.  Upon the altar, a golden plaque bears an inscription with the secret to the ancient magical spell '%s'."
const INTRO_NO_BOOK := "Nestled in a small hidden shrine is an ancient wooden altar.  Upon the altar, a golden plaque bears an inscription with the secret to the ancient magical spell '%s'.  Unfortunately, you have no Magic Book to record the spell with."

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var shrine := obj as Shrine
	var r := VisitResult.new()
	if shrine == null or shrine.spell_id == "":
		return r
	var spell_name := String(SpellData.get_spell(shrine.spell_id).get("name", shrine.spell_id))
	if ctx.hero_model == null or not ctx.hero_model.has_spellbook:
		r.message = INTRO_NO_BOOK % spell_name
		r.show_dialog = true
		return r
	shrine.teach(ctx.hero_model)
	r.message = INTRO_WITH_BOOK % spell_name
	r.show_dialog = true
	return r
