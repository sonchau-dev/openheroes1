class_name CampaignInfoDialog
extends CanvasLayer

signal closed

const PANEL_POS := Vector2(106, 96)

## Rect of campaign.bin's description box, and of its title line.
const TITLE_RECT := Rect2(185, 51, 200, 16)
const TEXT_RECT := Rect2(29, 81, 362, 150)

## The castle the original draws behind the briefing: the title picture, which
## lines up pixel for pixel with the backdrop in the campaign 1 recording.
const BACKDROP := UiKit.ART + "heroes.png"

var _panel: Control = null

## full_screen: the briefing the original draws over its own backdrop --
## the one between missions and the one a campaign opens with. It covers the
## whole screen, never the map or the title menu.
func open(mission: CampaignMission, allow_restart := true, full_screen := false) -> void:
	layer = 320 if full_screen else 220
	var font := UiKit.font_normal()
	var blocker := ColorRect.new()
	blocker.color = Color.BLACK if full_screen else Color.TRANSPARENT
	blocker.size = Vector2(640, 480)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	if full_screen and ResourceLoader.exists(BACKDROP):
		var backdrop := TextureRect.new()
		backdrop.texture = load(BACKDROP) as Texture2D
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
	var root := Control.new()
	root.position = PANEL_POS
	add_child(root)
	_panel = root
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.position = Vector2(12, 12)
	shadow.size = Vector2(428, 287)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shadow)
	root.add_child(UiKit.texture_rect(UiKit.ART + "campback.png"))
	var number := UiKit.texture_rect(UiKit.ART + "campaign/%04d.png" % (mission.id + 3))
	number.position = Vector2(150, 49)
	root.add_child(number)
	UiKit.add_label_rect(root, mission.title, TITLE_RECT, font, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	var text := Homm1Font.wrap(font, mission.description, TEXT_RECT.size.x) if font != null else mission.description
	UiKit.add_label_rect(root, text, TEXT_RECT, font, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP, "", 2)
	var okay := IcnButton.new()
	okay.setup(UiKit.ART + "campaign/", 0, "okay")
	okay.position = Vector2(27, 234) if allow_restart else Vector2(163, 234)
	okay.pressed.connect(func(_action):
		closed.emit()
		queue_free())
	root.add_child(okay)
	if allow_restart:
		var restart := IcnButton.new()
		restart.setup(UiKit.ART + "campaign/", 2, "restart")
		restart.position = Vector2(180, 234)
		restart.pressed.connect(func(_action):
			var game_node: Node = get_node_or_null("/root/Game")
			if game_node != null and game_node.has_method("restart_campaign_mission"):
				var err: String = game_node.restart_campaign_mission()
				if err == "" and game_node.has_method("to_map"):
					game_node.to_map())
		root.add_child(restart)

## The original draws the panel only once the backdrop has faded in.
func set_panel_visible(shown: bool) -> void:
	if _panel != null:
		_panel.visible = shown

func _input(event: InputEvent) -> void:
	if _panel != null and not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		closed.emit()
		queue_free()
		get_viewport().set_input_as_handled()
