# src/menu/credits.gd
extends Control

## credits.png full-screen; any click or ESC returns to the main menu.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := UiKit.texture_rect(UiKit.ART + "credits.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var shots = DevFlags.tool("res://src/tools/shots/menu_shots.gd")
	if shots != null:
		await shots.capture(self)

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		Game.to_menu()
