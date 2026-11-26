class_name BattleAudio
extends Node

## Native HOMM1 combat audio: creature SFX, spell SFX and the pre-battle
## fanfare (PREBATTL), at the Effects volume.
##
## In HOMM1, the original sound mixer supported up to 32 concurrent one-shots.
## There is no battle music: heroes.exe never plays CD audio and ships no MIDI.

const CreatureCatalogScript := preload("res://src/battle/creature_catalog.gd")
const AUDIO_DIR := "res://assets/art/"
const MAX_VOICES := 32
const SHOOTER_IDS := {1: true, 7: true, 10: true, 14: true, 15: true, 18: true}

const PREBATTL_SOUND := AUDIO_DIR + "PREBATTL.wav"

var enabled := true

static func sound_path(unit: String, event: StringName) -> String:
	var id := CreatureCatalogScript.native_id(unit)
	if id < 0:
		return ""
	var prefix := ""
	match event:
		&"attack":
			prefix = "ATKSND"
		&"move":
			prefix = "MOVE"
		&"wince":
			prefix = "WINCE"
		&"shoot":
			if not SHOOTER_IDS.has(id):
				return ""
			prefix = "SHOOT"
		_:
			return ""
	return AUDIO_DIR + "%s%02d.wav" % [prefix, id]

static func prebattle_sound_path() -> String:
	return PREBATTL_SOUND

static func has_prebattle_fanfare() -> bool:
	return ResourceLoader.exists(PREBATTL_SOUND)

func _game() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("Game")
	return null

func is_sfx_enabled() -> bool:
	var g := _game()
	if g != null and "sfx_enabled" in g:
		return bool(g.sfx_enabled)
	return true

func get_sfx_volume() -> float:
	var g := _game()
	if g != null and g.has_method("get_sfx_volume"):
		return float(g.get_sfx_volume())
	return 1.0

func _calc_sfx_volume_db() -> float:
	var vol := get_sfx_volume()
	if vol <= 0.0:
		return -80.0
	return linear_to_db(vol)

func play_one_shot(path: String) -> AudioStreamPlayer:
	if not enabled or not is_sfx_enabled() or get_child_count() >= MAX_VOICES:
		return null
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = _calc_sfx_volume_db()
	voice.finished.connect(voice.queue_free)
	add_child(voice)
	if is_inside_tree():
		voice.play()
	return voice

func play_unit(unit: String, event: StringName) -> AudioStreamPlayer:
	var path := sound_path(unit, event)
	return play_one_shot(path)

func play_spell(spell_or_sound: Variant) -> AudioStreamPlayer:
	var sound_name := ""
	if spell_or_sound is Dictionary:
		sound_name = String(spell_or_sound.get("sound", ""))
	elif spell_or_sound is String or spell_or_sound is StringName:
		sound_name = String(spell_or_sound)
	if sound_name.is_empty():
		return null
	var path := AUDIO_DIR + sound_name + ".wav"
	return play_one_shot(path)

func play_prebattle_fanfare() -> AudioStreamPlayer:
	if not enabled or not is_sfx_enabled():
		return null
	if not has_prebattle_fanfare():
		return null
	return play_one_shot(PREBATTL_SOUND)
