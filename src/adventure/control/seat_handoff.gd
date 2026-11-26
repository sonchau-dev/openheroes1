class_name SeatHandoff
extends RefCounted

## Manages hotseat player handoffs and network session coordination for the adventure map.

var net_box: NetworkStatusBox = null

func show_hotseat_handoff(map_root: Node2D, hud: AdventureHud, side: int,
		_new_day: bool, reload_on_confirm: bool,
		freeze_fn: Callable = Callable(),
		unfreeze_fn: Callable = Callable()) -> void:
	if Game.state == null:
		return
	var player := Game.state.player_of(side)
	if player == null:
		return
	Game.hotseat_handoff_pending = true
	if freeze_fn.is_valid():
		freeze_fn.call()
	if hud != null:
		hud.show_new_day(Game.state.day, true)
		if hud.minimap != null:
			hud.minimap.set_show_logo(true)
		if hud.roster_panel != null:
			hud.roster_panel.visible = false
	var handoff := HotseatHandoff.new()
	map_root.add_child(handoff)
	handoff.open(side, player.crest_idx, Game.state.day)
	handoff.confirmed.connect(func():
		Game.hotseat_handoff_pending = false
		if hud != null:
			if hud.minimap != null:
				hud.minimap.set_show_logo(false)
			if hud.roster_panel != null:
				hud.roster_panel.visible = true
			hud.hide_turn_transition()
		if reload_on_confirm:
			player.select_turn_start_hero()
			if not Game.activate_local_player(side):
				return
			Game.to_map()
		else:
			if unfreeze_fn.is_valid():
				unfreeze_fn.call()
			handoff.queue_free())

func attach_network_session(map_root: Node2D, show_game_over_fn: Callable,
		freeze_fn: Callable = Callable(),
		update_ui_fn: Callable = Callable(),
		unfreeze_fn: Callable = Callable()) -> void:
	if not Net.is_active():
		return
	var on_link_lost := func(): on_network_link_lost(map_root, update_ui_fn, unfreeze_fn)
	Net.link_lost.connect(on_link_lost)
	var on_status_changed := func(lines: PackedStringArray): on_network_status_changed(lines)
	Net.status_changed.connect(on_status_changed)
	# Net outlives every map; drop this map's handlers with it or they pile up.
	map_root.tree_exiting.connect(func():
		if Net.link_lost.is_connected(on_link_lost):
			Net.link_lost.disconnect(on_link_lost)
		if Net.status_changed.is_connected(on_status_changed):
			Net.status_changed.disconnect(on_status_changed))

	if Net.role == Net.Role.HOST:
		var opening := Net.begin_hosted_game()
		if opening != "":
			push_warning(opening)
	if Net.pending_game_over != "":
		var message := Net.pending_game_over
		Net.pending_game_over = ""
		show_game_over_fn.call(message)
		return
	if Net.is_waiting_for_remote():
		show_network_wait(map_root, freeze_fn)

func on_remote_handoff_requested(map_root: Node2D, side: int, _new_day: bool,
		freeze_fn: Callable = Callable(),
		unfreeze_fn: Callable = Callable()) -> void:
	var err := Net.send_state(side)
	if err != "":
		push_warning(err)
		MapDialogs.choice(map_root, err, ["Okay"], {}, func(_i: int):
			if unfreeze_fn.is_valid():
				unfreeze_fn.call())
		return
	show_network_wait(map_root, freeze_fn)

func show_network_wait(map_root: Node2D, freeze_fn: Callable = Callable()) -> void:
	if freeze_fn.is_valid():
		freeze_fn.call()
	if net_box != null and is_instance_valid(net_box):
		net_box.set_lines(Net.status_lines())
		return
	net_box = NetworkStatusBox.new()
	map_root.add_child(net_box)
	net_box.open(Net.status_lines())
	net_box.aborted.connect(func():
		Net.close()
		Game.to_menu())

func hide_network_wait() -> void:
	if net_box != null and is_instance_valid(net_box):
		net_box.queue_free()
	net_box = null

func on_network_status_changed(lines: PackedStringArray) -> void:
	if net_box != null and is_instance_valid(net_box):
		net_box.set_lines(lines)

func on_network_link_lost(map_root: Node2D, update_ui_fn: Callable,
		unfreeze_fn: Callable = Callable()) -> void:
	# Only the waiting banner froze input; a drop during the AI phase must
	# not release it under the computer players.
	var was_waiting := net_box != null and is_instance_valid(net_box)
	hide_network_wait()
	var prompt := Net.takeover_prompt()
	if prompt == "":
		Game.to_menu()
		return
	MapDialogs.choice(map_root, prompt, ["Yes", "No"], {}, func(index: int):
		if index == 0 and Net.fill_remote_with_ai():
			if was_waiting and unfreeze_fn.is_valid():
				unfreeze_fn.call()
			update_ui_fn.call()
		else:
			Net.close()
			Game.to_menu())
