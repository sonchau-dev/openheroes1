extends RefCounted
## Dragon City: captures for the visiting side (like a Mine), or launches the
## 5-stack guard battle if still un-captured. Mirrors handlers/mine.gd exactly;
## capture (owner flip) itself happens in resolve_post_battle() on victory —
## this handler only decides battle-vs-inert, same division of labor as Mine.

const TITLE := "Dragon City"
const ATTACK_PROMPT := "You have reached Dragon City, famous for its wealth and danger. Do you wish to attack?"
const CONQUERED := "You have conquered the mighty dragons. In homage to you, they offer 1000 gold a day to your cause, and will defend the city for you in case of attack."

func visit(obj: MapObject, ctx: VisitContext) -> VisitResult:
	var dc := obj as DragonCity
	var r := VisitResult.new()
	if dc == null:
		return r
	# heroes.exe 0xb2a49: the owner's own visit does nothing at all.
	if dc.owner == ctx.player_side:
		return r
	if dc.owner >= 0 and Game.state != null and ctx.player_state != null:
		var dc_owner := Game.state.player_of(dc.owner)
		if dc_owner != null and not ctx.player_state.is_hostile_to(dc_owner):
			return r
	# Everyone else is asked first (0xb2a82, Yes/No); Yes fights the dragons.
	if not dc.entry_confirmed and (ctx.player_state == null or not ctx.player_state.is_ai):
		r.source_object = dc
		r.choice = {
			"type": "event_enter",
			"title": TITLE,
			"prompt": ATTACK_PROMPT,
			"object": dc,
			"options": [
				{"label": "Yes", "confirm_entry": true},
				{"label": "No"},
			],
		}
		return r
	dc.entry_confirmed = false
	# Authentic HOMM1: Dragons defend the city against rival attack (homm1-native-data.md §3.12:
	# "defends itself for you in case of attack"; heroes.exe: "will defend the city for you in case of attack").
	if dc.is_armed() and dc.owner != ctx.player_side:
		r.start_battle = dc.guard
		return r
	# If city is ever unguarded (e.g. guard is empty), capture on walkover.
	dc.owner = ctx.player_side
	r.message = CONQUERED
	r.show_dialog = true
	return r
