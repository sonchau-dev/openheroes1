class_name MusicPlayer
extends Node

## HOMM1's streamed music, one numbered track at a time (heroes.exe 0xe056c;
## homm1-native-data.md 6.1, track map in
## data/knowledge_base/research/music-track-map.md).
##
## Switching follows the original:
## - asking for the track already playing does nothing;
## - with Music off the track is only remembered, and starts when music is
##   turned back on;
## - an outgoing terrain track (0..6) fades out and the next track fades in;
##   any other is cut;
## - terrain tracks, the tavern, the main menu and the computer turn resume
##   where they left off (0xdfe0f); every other track starts over.
##
## `play` sets a screen's track. `sting` plays an event track once and then
## returns to the screen's track, as the adventure loop asks for the terrain
## track again once the stream goes idle (0xd1d21).
##
## The files are an optional install (setup.gd --with-music); a
## missing one plays nothing.

const DIR := "res://assets/music/"
const STOP := -1

const PUZZLE := 13
const TELEPORT := 16
const TOWN_BASE := 29
const BATTLE_LOST := 43
const BATTLE_WON := 44
const TAVERN := 47
const MAIN_MENU := 48
const COMPUTER_TURN := 49
const CONGRATULATIONS := 54

## Track = terrain tile / 20 (table 0x410b8).
const TERRAINS := ["water", "grass", "snow", "swamp", "lava", "desert", "dirt"]
## Town type table 0x20521: 29 + this index.
const TOWN_FACTIONS := ["knight", "barbarian", "sorceress", "warlock"]
## Data 0x1e69c, picked by Random(0, 3).
const BATTLE := [41, 42, 40, 53]
const KEEPS_POSITION := [0, 1, 2, 3, 4, 5, 6, TAVERN, MAIN_MENU, COMPUTER_TURN]
## Tracks the stream rewinds to the start of when they end (loop flag +0x27,
## set at 0xdff37, rewound at 0xe0490); every other track plays once.
const LOOPS := [0, 1, 2, 3, 4, 5, 6, 29, 30, 31, 32, 40, 41, 42, 53, CONGRATULATIONS,
		TAVERN, MAIN_MENU, COMPUTER_TURN]
## The fade counter (0x41090) starts at 90 and the 64 Hz Miles timer
## (0xdf3dd, callback 0xdf134) counts it down. The track switches once
## counter / 6 <= 10 (0xdfdda).
const FADE_START := 90
const FADE_SWITCH := 65
const TIMER_HZ := 64.0

## Visit stings by object type (routine 0xb4aae, jump table at code 0x5154c).
const VISIT := {
	"mine": 23, "buoy": 20, "oasis": 20,
	"skeleton": 28, "chest": 28, "campfire": 28, "watermill": 28, "windmill": 28,
	"demon_cave": 7, "faerie_ring": 8, "fountain": 24, "gazebo": 9,
	"ancient_lamp": 10, "genie_lamp": 10, "dwelling": 22, "desert_tent": 15, "nomad_tent": 15,
	"graveyard": 11, "dragon_city": 12, "lighthouse": 26, "obelisk": 21, "shrine": 27,
	"statue": 14, "stone_liths": TELEPORT, "wagon_camp": 17, "whirlpool": 25,
}
## Converted maps keep the lamp (B8 139) and the desert tent (B8 167) as
## generic dwellings; their unit tells them apart.
const VISIT_DWELLING_UNIT := {"genie": 10, "nomad": 15}

var settings: GameSettings = null

var _player := AudioStreamPlayer.new()
var _track := STOP
var _playing := STOP
var _screen := STOP
var _positions := {}
var _fade: Tween = null
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	_player.finished.connect(_on_finished)
	_rng.randomize()


static func terrain_track(terrain: String) -> int:
	return TERRAINS.find(terrain)


static func town_track(faction: String) -> int:
	var i := TOWN_FACTIONS.find(faction)
	return TOWN_BASE + i if i >= 0 else STOP


static func visit_track(type: String, unit: String = "") -> int:
	if type == "dwelling" and VISIT_DWELLING_UNIT.has(unit):
		return VISIT_DWELLING_UNIT[unit]
	return int(VISIT.get(type, STOP))


## Plays a screen's track on the Game autoload's player, for code that runs
## without the autoload too (headless tests build these screens directly).
static func play_on_game(track: int) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	var game: Node = loop.root.get_node_or_null("Game") if loop != null and loop.root != null else null
	if game != null and "music" in game and game.music != null:
		game.music.play(track)


func battle_track() -> int:
	return BATTLE[_rng.randi_range(0, BATTLE.size() - 1)]


func current_track() -> int:
	return _track


## The track a screen plays until another screen asks for its own.
func play(track: int) -> void:
	_screen = track
	_switch(track)


## An event track that plays once; then the screen's track comes back.
func sting(track: int) -> void:
	_switch(track)


func stop() -> void:
	play(STOP)


## Call after the Music setting changes.
func refresh_volume() -> void:
	var volume := _volume()
	if volume <= 0.0:
		_save_position(_playing)
		_player.stop()
		return
	_player.volume_db = linear_to_db(volume)
	if not _player.playing:
		_start(_track)


func _switch(track: int) -> void:
	if track == _track:
		return
	# During a fade-out a new request only changes the track it switches to.
	var fading_out := _fade != null and _playing != _track
	_track = track
	if _volume() <= 0.0 or fading_out:
		return
	if _fade != null:
		_fade.kill()
		_fade = null
	if _playing >= 0 and _playing < TERRAINS.size() and _player.playing:
		_fade = create_tween()
		_fade.tween_method(_fade_tick, float(FADE_START), 0.0, FADE_START / TIMER_HZ)
		_fade.tween_callback(func() -> void: _fade = null)
	else:
		_cut()


func _cut() -> void:
	_save_position(_playing)
	_start(_track)


func _fade_tick(counter: float) -> void:
	var tick := int(counter)
	if tick <= FADE_SWITCH and _playing != _track:
		_cut()
	if _player.playing:
		_player.volume_db = linear_to_db(maxf(fade_gain(tick) * _volume(), 0.0001))


## Music gain at a fade counter value, 0..1 (0xe03ca: Miles volume 0..64 before
## the Music setting scales it). Above the switch the old track fades out over
## 90..60, at or below it the new one fades in over 60..0.
static func fade_gain(counter: int) -> float:
	var volume := (counter - 60) * 64 / 30 if counter > FADE_SWITCH else (60 - counter) * 64 / 60
	return clampi(volume, 0, 64) / 64.0


func _start(track: int) -> void:
	_playing = track
	var stream := _stream(track)
	if stream == null:
		_player.stop()
		return
	_player.stream = stream
	_player.volume_db = linear_to_db(_volume())
	_player.play(float(_positions.get(track, 0.0)) if track in KEEPS_POSITION else 0.0)


func _stream(track: int) -> AudioStreamWAV:
	if track < 0:
		return null
	var path := DIR + "heroes%02d.wav" % track
	if not ResourceLoader.exists(path):
		return null
	var wav := load(path) as AudioStreamWAV
	if wav != null and track in LOOPS and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		loop_whole(wav)
	return wav


## Loops the whole sample. Godot plays loop_end itself (its importer clamps it
## to the last frame), so loop_end = frame count read one sample past the
## buffer on every pass: on Android that hit a guard page and crashed.
static func loop_whole(wav: AudioStreamWAV) -> void:
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = maxi(0, roundi(wav.get_length() * wav.mix_rate) - 1)


func _save_position(track: int) -> void:
	if track in KEEPS_POSITION and _player.playing:
		_positions[track] = _player.get_playback_position()


func _on_finished() -> void:
	if _track != _screen:
		_switch(_screen)


func _volume() -> float:
	return settings.get_music_volume() if settings != null else 1.0
