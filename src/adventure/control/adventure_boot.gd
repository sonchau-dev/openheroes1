class_name AdventureBoot
extends RefCounted

## Handles command-line argument parsing, game state initialization, map loading,
## run configuration, camera centering, and benchmark dispatch for the adventure map.

const MAP_PATH := "res://data/maps/skirmish01.json"

func parse_cmdline_args() -> Dictionary:
	var force_side := -1
	var nofog := false
	var requested_map_path := ""
	var requested_campaign := -1
	var requested_hotseat := 1
	var bench_first_map := false
	var bench_frame := false
	var bench := false

	for a in OS.get_cmdline_user_args():
		if a == "--":
			continue
		var clean_a := a.trim_prefix("--")
		if clean_a.begins_with("map="):
			var stem := clean_a.substr(4).trim_suffix(".json")
			requested_map_path = "res://data/maps/%s.json" % stem
			Game.selected_map_path = requested_map_path
		elif clean_a.begins_with("side="):
			force_side = clean_a.substr(5).to_int()
		elif clean_a == "nofog":
			nofog = true
		elif clean_a.begins_with("campaign="):
			requested_campaign = clampi(clean_a.substr(9).to_int(), 0, 3)
		elif clean_a.begins_with("hotseat="):
			requested_hotseat = clampi(clean_a.substr(8).to_int(), 1, 4)
		elif clean_a == "bench":
			bench = true
			if requested_map_path == "":
				requested_map_path = "res://data/maps/aes31000.json"
				Game.selected_map_path = requested_map_path
		elif clean_a == "bench-frame":
			bench_frame = true
			if requested_map_path == "":
				requested_map_path = "res://data/maps/aes31000.json"
				Game.selected_map_path = requested_map_path
		elif clean_a == "bench-first-map":
			bench_first_map = true
			if requested_map_path == "":
				requested_map_path = "res://data/maps/aes31000.json"
				Game.selected_map_path = requested_map_path

	return {
		"force_side": force_side,
		"nofog": nofog,
		"requested_map_path": requested_map_path,
		"requested_campaign": requested_campaign,
		"requested_hotseat": requested_hotseat,
		"bench_first_map": bench_first_map,
		"bench_frame": bench_frame,
		"bench": bench,
	}

func ensure_game_state(boot_args: Dictionary) -> String:
	if Game.state != null:
		return ""
	var requested_campaign: int = boot_args.get("requested_campaign", -1)
	var requested_map_path: String = boot_args.get("requested_map_path", "")
	var requested_hotseat: int = boot_args.get("requested_hotseat", 1)

	if requested_campaign >= 0:
		return Game.new_campaign(requested_campaign)
	else:
		var initial_settings := Game.setup.duplicate_settings()
		if requested_map_path != "":
			initial_settings.map_path = requested_map_path
		initial_settings.human_player_count = requested_hotseat
		return Game.new_game(initial_settings)

func load_map(boot_args: Dictionary) -> MapData:
	var path := Game.selected_map_path if Game.selected_map_path != "" else MAP_PATH
	var force_side: int = boot_args.get("force_side", -1)
	return MapLoaderJson.load_map(path, force_side)

func configure_run(map_data: MapData) -> String:
	var setup_error := Game.configure_map_for_run(map_data)
	if setup_error != "":
		return setup_error
	if Game.state != null:
		Game.state.restore_spawned_neutral_stacks(map_data)
	Game.apply_object_states(map_data.objects)
	Game.apply_run_state(map_data)
	Game.ensure_ai_players(map_data)
	return ""

func setup_camera(cam: MapCamera, map_data: MapData, hero: Hero,
		pending_defeat_visuals: Array, active_player_side: int,
		town_tile: Vector2i) -> void:
	if cam.is_inside_tree():
		cam.setup(map_data)
	cam.view_override = Vector2(448, 448)
	cam.offset = Vector2(80, 0)
	if cam.is_inside_tree():
		cam.make_current()
		if hero != null:
			cam.center_on(hero.center())
		elif not pending_defeat_visuals.is_empty() \
				and int(pending_defeat_visuals[0].get("side", -1)) == active_player_side:
			var defeat_tile := Vector2i(pending_defeat_visuals[0].get("tile", Vector2i.ZERO))
			cam.center_on(Vector2(defeat_tile * map_data.tile_size) \
					+ Vector2(map_data.tile_size, map_data.tile_size) * 0.5)
		elif town_tile != Vector2i(-1, -1):
			cam.center_on(Vector2(town_tile) * float(map_data.tile_size))

func run_benchmarks(map_node: Node2D) -> bool:
	var args := OS.get_cmdline_user_args()
	if "--bench-first-map" in args:
		_run_bench_first_map(map_node)
		return true
	if "--bench" in args or "--bench-frame" in args:
		_run_bench_frame(map_node)
		return true
	return false

func _run_bench_first_map(map_node: Node2D) -> void:
	await RenderingServer.frame_post_draw
	await map_node.get_tree().process_frame
	var ticks_ms := Time.get_ticks_usec() / 1000.0
	print("BENCH_FIRST_MAP_MS: %.2f" % ticks_ms)
	map_node.get_tree().quit()

func _run_bench_frame(map_node: Node2D) -> void:
	var tree := map_node.get_tree()
	await RenderingServer.frame_post_draw
	await tree.process_frame
	var first_map_ms := Time.get_ticks_usec() / 1000.0
	print("BENCH_FIRST_MAP_MS: %.2f" % first_map_ms)
	var bench_script = load("res://tools/frame_time_benchmark.gd")
	if bench_script != null:
		var runner = bench_script.new()
		map_node.add_child(runner)
		await runner.run_benchmarks(map_node)
	tree.quit()
