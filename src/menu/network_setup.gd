extends Control

## HOMM1's network setup screen.
##
## Art and layout are the original's: `btnnet.icn` HOST / GUEST / CANCEL on the
## `redback` panel at the positions `stpnet.bin` records, and the `netbox`
## banner for every status line (KB homm1-native-data.md §5.5). Only the
## transport underneath changed — where the original asked for a COM port or a
## phone number, we ask for an address and a port.
##
## Roles follow the original: "The host sets up the game options" and "The guest
## waits for the host to set up the game, then is automatically added in."

const ART := UiKit.ART
const BG := ART + "heroes.png"
const BTNNET := ART + "btnnet/"
const PANEL := ART + "redback.png"

## Panel-local button positions, straight out of stpnet.bin.
const HOST_POS := Vector2(33, 45)
const GUEST_POS := Vector2(33, 111)
const CANCEL_POS := Vector2(33, 309)
const PANEL_POS := Vector2(399, 35)

enum Phase { CHOOSE, ENTRY, LINKING }

var _phase: int = Phase.CHOOSE
var _panel: TextureRect = null
var _shadow: ColorRect = null
var _box: NetworkStatusBox = null
var _entry: LineEdit = null
var _pending_role: int = Net.Role.NONE

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := UiKit.texture_rect(BG)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_shadow = ColorRect.new()
	_shadow.color = Color(0, 0, 0, 0.5)
	_shadow.position = PANEL_POS + Vector2(12, 12)
	_shadow.size = Vector2(194, 410)
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_panel = UiKit.texture_rect(PANEL, PANEL_POS)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	_add_button(0, "host", HOST_POS)
	_add_button(2, "guest", GUEST_POS)
	_add_button(4, "cancel", CANCEL_POS)

	Net.link_established.connect(_on_link_established)
	Net.link_failed.connect(_on_link_failed)
	Net.status_changed.connect(_on_status_changed)

	_apply_cmdline()

	var shots = DevFlags.tool("res://src/tools/shots/menu_shots.gd")
	if shots != null:
		await shots.network_setup(self)

## Two-process manual testing: `--net-host[=PORT]` on one machine,
## `--net-join=ADDR[:PORT]` on the other, both skipping the menu.
func _apply_cmdline() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--net-host" or arg.begins_with("--net-host="):
			var port := Net.DEFAULT_PORT
			if arg.contains("="):
				port = arg.split("=")[1].to_int()
			_start_host(port)
			return
		if arg.begins_with("--net-join="):
			var target := arg.split("=")[1]
			_start_guest(_address_of(target), _port_of(target))
			return

func _add_button(base: int, action: String, pos: Vector2) -> void:
	var btn := IcnButton.new()
	btn.setup(BTNNET, base, action)
	btn.position = pos
	btn.pressed.connect(_on_action)
	_panel.add_child(btn)

func _on_action(action: String) -> void:
	match action:
		"host":
			_open_entry("Listen on port:", str(Net.DEFAULT_PORT), Net.Role.HOST)
		"guest":
			_open_entry("Enter the host player's address:",
					"127.0.0.1:%d" % Net.DEFAULT_PORT, Net.Role.GUEST)
		"cancel":
			_abort()

# --- address entry -----------------------------------------------------------

## The banner's lighter lower strip is netbox.bin's third text line; the
## original put the modem phone number there, so the address goes there too.
func _open_entry(prompt: String, initial: String, role: int) -> void:
	_phase = Phase.ENTRY
	_pending_role = role
	_set_panel_visible(false)
	_show_box(PackedStringArray([prompt, "", ""]))
	_entry = LineEdit.new()
	_entry.text = initial
	_entry.max_length = 64
	_entry.position = Vector2(NetworkStatusBox.LINE_X, NetworkStatusBox.LINE_Y[2])
	_entry.custom_minimum_size = Vector2(NetworkStatusBox.LINE_W, NetworkStatusBox.LINE_H)
	_entry.size = Vector2(NetworkStatusBox.LINE_W, NetworkStatusBox.LINE_H)
	_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_entry.add_theme_color_override("font_color", Color8(255, 255, 255))
	_entry.add_theme_color_override("caret_color", Color8(255, 234, 120))
	var font := UiKit.font_normal()
	if font != null:
		_entry.add_theme_font_override("font", font)
		_entry.add_theme_font_size_override("font_size", font.fixed_size)
	_entry.text_submitted.connect(func(_t: String): confirm_entry())
	_box.banner().add_child(_entry)
	_entry.grab_focus()

func confirm_entry() -> void:
	if _entry == null:
		return
	var value := _entry.text.strip_edges()
	if _pending_role == Net.Role.HOST:
		_start_host(_port_of(value) if value.contains(":") else maxi(1, value.to_int()))
	else:
		_start_guest(_address_of(value), _port_of(value))

# --- linking -----------------------------------------------------------------

func _start_host(port: int) -> void:
	var err := Net.host_game(port)
	if err != "":
		_fail(err)
		return
	_enter_linking()

func _start_guest(address: String, port: int) -> void:
	if address == "":
		_fail("Enter the host player's address.")
		return
	var err := Net.join_game(address, port)
	if err != "":
		_fail(err)
		return
	_enter_linking()

func _enter_linking() -> void:
	_phase = Phase.LINKING
	_set_panel_visible(false)
	if _entry != null:
		_entry.queue_free()
		_entry = null
	_show_box(Net.status_lines())

func _on_link_established() -> void:
	if Net.role == Net.Role.HOST:
		# "The host sets up the game options" — hand the host the normal new-game
		# screen, locked to the two seats a network game allows.
		Game.setup = NewGameSettings.new()
		Game.setup.human_player_count = 2
		Game.setup.network = true
		get_tree().change_scene_to_file("res://src/menu/new_game_setup.tscn")
	# The guest simply waits here; Net applies the host's first state and
	# switches to the map on its own.

func _on_link_failed(reason: String) -> void:
	_fail(reason)

func _on_status_changed(lines: PackedStringArray) -> void:
	if _box != null:
		_box.set_lines(lines)

func _fail(reason: String) -> void:
	_phase = Phase.LINKING
	_show_box(PackedStringArray([reason, "", "  Press 'CANCEL' to abort."]))

func _abort() -> void:
	Net.close()
	Game.to_menu()

# --- helpers -----------------------------------------------------------------

func _show_box(lines: PackedStringArray) -> void:
	if _box == null:
		_box = NetworkStatusBox.new()
		add_child(_box)
		_box.open(lines, false)
		_box.aborted.connect(_abort)
	else:
		_box.set_lines(lines)

func _set_panel_visible(visible_now: bool) -> void:
	if _panel != null:
		_panel.visible = visible_now
	if _shadow != null:
		_shadow.visible = visible_now

static func _address_of(target: String) -> String:
	var parts := target.split(":")
	return String(parts[0]).strip_edges()

static func _port_of(target: String) -> int:
	var parts := target.split(":")
	if parts.size() < 2:
		return Net.DEFAULT_PORT
	var port := String(parts[1]).to_int()
	return port if port > 0 else Net.DEFAULT_PORT

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if _phase == Phase.CHOOSE:
			_abort()
		else:
			get_viewport().set_input_as_handled()
			_abort()
	elif _phase == Phase.ENTRY and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		confirm_entry()
