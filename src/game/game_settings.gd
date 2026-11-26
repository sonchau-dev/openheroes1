class_name GameSettings
extends RefCounted

## Game Options / Settings (KB timings.md §1, ui-bin-format.md cpanel.bin).

enum MovementSpeed { WALK = 0, TROT = 1, CANTER = 2, GALLOP = 3, JUMP = 4 }

const DEFAULT_SETTINGS_PATH := "user://settings.cfg"

## Setting index 0..10: 0 = Off, 1 = On, 2..10 = Volume 9..Volume 1
var music_setting: int = 1
var sfx_setting: int = 1

var music_enabled: bool:
	get:
		return music_setting != 0
	set(v):
		if v:
			if music_setting == 0:
				music_setting = 1
		else:
			music_setting = 0

var sfx_enabled: bool:
	get:
		return sfx_setting != 0
	set(v):
		if v:
			if sfx_setting == 0:
				sfx_setting = 1
		else:
			sfx_setting = 0

func get_music_volume() -> float:
	if music_setting == 0:
		return 0.0
	if music_setting == 1:
		return 1.0
	return float(11 - music_setting) / 10.0

func get_sfx_volume() -> float:
	if sfx_setting == 0:
		return 0.0
	if sfx_setting == 1:
		return 1.0
	return float(11 - sfx_setting) / 10.0

var movement_speed: int = MovementSpeed.CANTER
var autosave_enabled: bool = true
var show_path: bool = true
var view_enemy_movement: bool = true

## Where save_settings() / load_settings() writes. An environment knob (tests
## point it at a scratch path so the real user settings are never touched).
var settings_path: String = DEFAULT_SETTINGS_PATH

func save_settings() -> void:
	var dir := settings_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_setting", music_setting)
	cfg.set_value("audio", "sfx_setting", sfx_setting)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("gameplay", "movement_speed", movement_speed)
	cfg.set_value("gameplay", "autosave_enabled", autosave_enabled)
	cfg.set_value("gameplay", "show_path", show_path)
	cfg.set_value("gameplay", "view_enemy_movement", view_enemy_movement)
	cfg.save(settings_path)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		if cfg.has_section_key("audio", "music_setting"):
			music_setting = clampi(int(cfg.get_value("audio", "music_setting", 1)), 0, 10)
		else:
			music_setting = 1 if bool(cfg.get_value("audio", "music_enabled", true)) else 0
		if cfg.has_section_key("audio", "sfx_setting"):
			sfx_setting = clampi(int(cfg.get_value("audio", "sfx_setting", 1)), 0, 10)
		else:
			sfx_setting = 1 if bool(cfg.get_value("audio", "sfx_enabled", true)) else 0
		movement_speed = cfg.get_value("gameplay", "movement_speed", MovementSpeed.CANTER)
		autosave_enabled = cfg.get_value("gameplay", "autosave_enabled", true)
		show_path = cfg.get_value("gameplay", "show_path", true)
		view_enemy_movement = cfg.get_value("gameplay", "view_enemy_movement", true)
