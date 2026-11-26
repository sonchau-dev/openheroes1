class_name DevFlags
extends RefCounted

## The developer command line: `--shot*` screenshots, `--probe=` key scripts,
## `--trace-pathfinding` and the scene fixtures. The code these flags drive
## lives under src/tools/, which the export leaves out, so scenes load it by
## path through `tool()` and only when a flag asks for it.

const SMOKE := "res://src/tools/scene_smoke.gd"

static var _shot_mode := -1

## The headless smoke run drives a scene by itself and quits. A test that
## wants to drive the same scene turns the smoke off first, so the scene
## stays under the test's control.
static var smoke_disabled := false

## True when any `--shot*` flag is on the command line, before or after `--`,
## or Movie Maker is recording: both capture the bare 640x480 frame.
static func shot_mode() -> bool:
	if _shot_mode < 0:
		_shot_mode = 1 if Engine.get_write_movie_path() != "" else 0
		for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
			if arg.begins_with("--shot"):
				_shot_mode = 1
				break
	return _shot_mode == 1

## True when a user argument starts with one of `prefixes`.
static func any(prefixes: Array) -> bool:
	for arg in OS.get_cmdline_user_args():
		for prefix: String in prefixes:
			if arg.begins_with(prefix):
				return true
	return false

## A new instance of the developer script at `path`, or null when no user
## argument starts with one of `prefixes` or the script is not there (an
## exported build).
static func tool(path: String, prefixes: Array = ["--shot"]) -> Object:
	return load_tool(path) if any(prefixes) else null

## A new instance of the developer script at `path`, or null in a build
## without it.
static func load_tool(path: String) -> Object:
	if not ResourceLoader.exists(path):
		push_warning("DevFlags: %s is not in this build" % path)
		return null
	return (load(path) as Script).new()

## The headless smoke test (SceneSmoke) under the dummy renderer, else null.
static func smoke() -> Object:
	if smoke_disabled:
		return null
	return load_tool(SMOKE) if DisplayServer.get_name() == "headless" else null
