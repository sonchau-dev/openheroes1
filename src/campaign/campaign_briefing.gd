class_name CampaignBriefing
extends RefCounted

## The campaign briefing the original shows over its own backdrop: the screen
## fades to black, the backdrop fades in under the panel, and the map fades
## in again once the player presses OKAY. The panel is never drawn over the
## map or over the title menu.
##
## The campaign 1 recording shows the between-missions case at 30:28-30:37:
## the Congratulations screen dims, the backdrop shows alone, the panel comes
## up over it, and after OKAY the screen goes black before the next map fades
## in. No recording shows the briefing a campaign opens with.
##
## The campaign's first briefing and the one between missions use this, so
## the two look the same.
##
## The game singleton is passed in rather than named: a class_name script can
## be compiled before the engine registers the autoload names, and the
## compiler would not resolve them.

## Shows `mission`'s briefing as a child of `parent` and fades `fade` in over
## it. `fade` must already be in the tree and covering the screen in black.
## The panel stays hidden until the fade-in is done.
static func show(parent: Node, mission: CampaignMission, fade: ScreenFade) -> CampaignInfoDialog:
	var dialog := CampaignInfoDialog.new()
	parent.add_child(dialog)
	dialog.open(mission, false, true)
	dialog.set_panel_visible(false)
	await fade.fade(false)
	dialog.set_panel_visible(true)
	return dialog

## Fades the briefing out and hands over to the map, which then fades in
## from black, as the original does between missions.
static func leave(g: Node, fade: ScreenFade) -> void:
	await fade.fade(true)
	await g.get_tree().create_timer(ScreenFade.HOLD_MAP).timeout
	g.fade_in_pending = true
	g.to_map()

## Starts `ruler`'s campaign and shows its first briefing over the backdrop,
## the same way the original opens a campaign. `g` is the game singleton and
## `parent` hosts the briefing and the fade. Returns false when the campaign
## cannot start.
static func begin(parent: Node, g: Node, ruler: int) -> bool:
	var err: String = g.new_campaign(ruler)
	if err != "":
		push_error(err)
		return false
	var fade := ScreenFade.new()
	parent.add_child(fade)
	await fade.fade(true)
	await parent.get_tree().create_timer(ScreenFade.HOLD_BRIEFING).timeout
	var mission: CampaignMission = g.campaign.mission()
	var briefing := await show(parent, mission, fade)
	briefing.closed.connect(func() -> void:
		g.campaign_show_intro = false
		await leave(g, fade))
	return true
