class_name AdventureAudio
extends Node

## Native HOMM1 adventure-map audio: typed pickup/event one-shots plus the
## LOOP0000..0021 environmental bank mixed around the focused hero.

const SOUND_ROOT := "res://assets/art/"
const AMBIENT_RADIUS_TILES := 4 # Chebyshev tile distance radius: native falloff table at data 0x1e774
const AMBIENT_REFRESH_SECONDS := 0.15

const OBJECT_LOOPS := {
	"buoy": 0,
	"shipwreck": 1,
	"oracle": 3,
	"stone_liths": 4,
	"watermill": 9,
	"campfire": 10,
	"windmill": 11,
	"fountain": 12,
	"demon_cave": 17,
	"shrine": 18,
}

var _map: MapData = null
var _focus_fn: Callable
var _ai_fn: Callable
var _music := MusicPlayer.STOP
var _ambient_players: Dictionary = {} # sound path -> AudioStreamPlayer
var _refresh_elapsed := AMBIENT_REFRESH_SECONDS

func setup(map: MapData, focus_fn: Callable, ai_fn: Callable = Callable()) -> void:
	_map = map
	_focus_fn = focus_fn
	_ai_fn = ai_fn
	set_process(true)

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < AMBIENT_REFRESH_SECONDS:
		return
	_refresh_elapsed = 0.0
	_update_ambient()
	_update_music()

## The computer's turn has its own track (0x80473); otherwise the terrain
## under the focused hero picks one, asked for on entering the map and on
## every step (0x9294f, 0x9f1d7). Only a change is sent, so a town or battle
## screen's track and a sting are left alone until the map wants another.
func _update_music() -> void:
	var g := _get_game()
	if g == null or not ("music" in g) or g.music == null:
		return
	var want := MusicPlayer.STOP
	if _ai_fn.is_valid() and bool(_ai_fn.call()):
		want = MusicPlayer.COMPUTER_TURN
	else:
		var hero: Hero = _focus_fn.call() as Hero if _focus_fn.is_valid() else null
		if hero == null or _map == null:
			return
		var focus := hero.center() / float(_map.tile_size)
		want = MusicPlayer.terrain_track(_map.terrain_at(Vector2i(floori(focus.x), floori(focus.y))))
	if want != MusicPlayer.STOP and want != _music:
		_music = want
		g.music.play(want)

func play_sting(track: int) -> void:
	var g := _get_game()
	if track == MusicPlayer.STOP or g == null or not ("music" in g) or g.music == null:
		return
	if _ai_fn.is_valid() and bool(_ai_fn.call()):
		return
	g.music.sting(track)

## heroes.exe plays one visit sound, from 0xb5d88 in the visit handler's
## shared tail, and only when the visit takes the object off the map: a random
## pickup01..05 (0xdae2c) for a pickup, killfade for a monster stack that
## joins or is beaten, or a leprechaun sent away. Every other visit is silent.
static var _pickup_rng := RandomNumberGenerator.new()

static func random_pickup_path() -> String:
	return SOUND_ROOT + "PICKUP%02d.wav" % _pickup_rng.randi_range(1, 5)

## Pure mapping kept separate from playback so headless tests can pin every
## event without needing an audio device.
static func visit_sound_paths(obj: MapObject, result: VisitResult) -> Array[String]:
	var sounds: Array[String] = []
	if obj == null or result == null:
		return sounds
	# A fight is announced by the battle screen's own PREBATTL (heroes.exe
	# 0x893f0, BattleAudio), not by the map.
	if result.start_battle != null or not result.consumed:
		return sounds
	if obj is ResourcePile or obj.type in ["chest", "campfire"]:
		sounds.append(random_pickup_path())
	elif obj is ArtifactPickup:
		# Taken (free, Rogues beaten, paid) or refused: the leprechaun vanishes.
		sounds.append(random_pickup_path() if result.grant_artifact != "" else SOUND_ROOT + "KILLFADE.wav")
	elif obj is Dwelling:
		# Only the Ancient Lamp leaves the map, when its last genie is taken.
		sounds.append(random_pickup_path())
	elif obj is NeutralStack:
		# Joined, or beaten and removed on the way back from the battle.
		sounds.append(SOUND_ROOT + "KILLFADE.wav")
	return sounds

func play_visit(obj: MapObject, result: VisitResult) -> void:
	if obj != null:
		play_sting(MusicPlayer.visit_track(obj.type, (obj as Dwelling).unit if obj is Dwelling else ""))
	for path: String in visit_sound_paths(obj, result):
		play_one_shot(path)
	if result != null and result.consumed and _map != null and obj != null:
		_map.clear_ambient_sound(obj.tile)
		_map.clear_ambient_sound(obj.action_tile)

## The dig routine plays DIGSOUND only, artifact or not.
func play_dig(_found_artifact: bool) -> void:
	play_one_shot(SOUND_ROOT + "DIGSOUND.wav")

func play_spell(spell_id: String, result_kind: String) -> void:
	var spell := SpellData.get_spell(spell_id)
	var sound_name := String(spell.get("sound", ""))
	if sound_name != "":
		play_one_shot(SOUND_ROOT + sound_name + ".wav")
	if result_kind == "teleport" or result_kind == "pick_town":
		play_one_shot(SOUND_ROOT + "KILLFADE.wav")
		play_sting(MusicPlayer.TELEPORT)

static func _get_game() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null and loop.root.has_node("Game"):
		return loop.root.get_node("Game")
	return null

func play_one_shot(path: String, finished_callback: Callable = Callable()) -> float:
	var g := _get_game()
	var sfx_on: bool = bool(g.sfx_enabled) if (g != null and "sfx_enabled" in g) else true
	if not sfx_on:
		if finished_callback.is_valid():
			finished_callback.call()
		return 0.0
	var stream := load(path) as AudioStream
	if stream == null:
		return 0.0
	var player := AudioStreamPlayer.new()
	player.stream = stream
	var vol: float = float(g.get_sfx_volume()) if (g != null and g.has_method("get_sfx_volume")) else 1.0
	player.volume_db = linear_to_db(maxf(vol, 0.001))
	add_child(player)
	player.finished.connect(func() -> void:
		if finished_callback.is_valid():
			finished_callback.call()
		player.queue_free())
	player.play()
	return stream.get_length()

static func ambient_loop_index(obj: MapObject) -> int:
	if obj is Mine:
		return 16 if (obj as Mine).res == "wood" else 15
	return int(OBJECT_LOOPS.get(obj.type, -1)) if obj != null else -1

func _update_ambient() -> void:
	var g := _get_game()
	var sfx_on: bool = bool(g.sfx_enabled) if (g != null and "sfx_enabled" in g) else true
	if _map == null or not _focus_fn.is_valid() or not sfx_on:
		_clear_ambient()
		return
	var hero: Hero = _focus_fn.call() as Hero if _focus_fn.is_valid() else null
	if hero == null or _map == null:
		_clear_ambient()
		return
	var focus := hero.center() / float(_map.tile_size)
	var hero_tile := Vector2i(floori(focus.x), floori(focus.y))
	var nearest: Dictionary = {} # path -> {cheb: int}

	var scan_radius := AMBIENT_RADIUS_TILES
	if not _map.ambient_sounds.is_empty():
		for y in range(maxi(0, hero_tile.y - scan_radius), mini(_map.height, hero_tile.y + scan_radius + 1)):
			for x in range(maxi(0, hero_tile.x - scan_radius), mini(_map.width, hero_tile.x + scan_radius + 1)):
				var loop_idx := _map.get_ambient_sound(Vector2i(x, y))
				if loop_idx >= 0:
					_consider_source(nearest, loop_idx, Vector2i(x, y), hero_tile)
	else:
		# Fallback for maps without an authored ambient sound grid (e.g. procedural or custom maps)
		for obj: MapObject in _map.objects:
			if obj.consumed:
				continue
			var loop_idx := ambient_loop_index(obj)
			if loop_idx >= 0:
				_consider_source(nearest, loop_idx, obj.action_tile, hero_tile)

	for path: String in _ambient_players.keys():
		if not nearest.has(path):
			var obsolete := _ambient_players[path] as AudioStreamPlayer
			_ambient_players.erase(path)
			obsolete.stop()
			obsolete.queue_free()
	for path: String in nearest:
		var info: Dictionary = nearest[path]
		var gain := ambient_gain_for_chebyshev(int(info.cheb))
		var sfx_vol: float = float(g.get_sfx_volume()) if (g != null and g.has_method("get_sfx_volume")) else 1.0
		gain *= sfx_vol
		var player := _ambient_players.get(path) as AudioStreamPlayer
		if player == null:
			player = _start_ambient(path, gain)
			if player == null:
				continue
			_ambient_players[path] = player
		else:
			player.volume_db = linear_to_db(maxf(gain, 0.001))

## Native HOMM1 distance volume table from heroes.exe (data offset 0x1e774,
## file offset 0x122e18). Scaled against Miles Sound System's 0..127 (0x7F)
## master sample volume range where one-shot SFX play at 127.
const AMBIENT_DISTANCE_VOLUMES: Array[int] = [64, 48, 32, 16, 10, 0]

static func ambient_gain_for_chebyshev(cheb: int) -> float:
	if cheb < 0 or cheb >= AMBIENT_DISTANCE_VOLUMES.size():
		return 0.0
	return float(AMBIENT_DISTANCE_VOLUMES[cheb]) / 127.0

func _consider_source(nearest: Dictionary, loop_idx: int, source_tile: Vector2i, hero_tile: Vector2i) -> void:
	var cheb := maxi(absi(source_tile.x - hero_tile.x), absi(source_tile.y - hero_tile.y))
	if cheb > AMBIENT_RADIUS_TILES:
		return
	var path := SOUND_ROOT + "loop%04d.wav" % loop_idx
	if not nearest.has(path) or cheb < int(nearest[path].cheb):
		nearest[path] = {"cheb": cheb}

func _start_ambient(path: String, initial_gain: float = 0.0) -> AudioStreamPlayer:
	var loaded := load(path) as AudioStream
	if loaded == null:
		return null
	var stream := loaded.duplicate(true) as AudioStream
	if stream is AudioStreamWAV:
		MusicPlayer.loop_whole(stream as AudioStreamWAV)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(maxf(initial_gain, 0.001))
	add_child(player)
	if player.is_inside_tree():
		player.play()
	return player


func _clear_ambient() -> void:
	for player: AudioStreamPlayer in _ambient_players.values():
		player.stop()
		player.queue_free()
	_ambient_players.clear()
