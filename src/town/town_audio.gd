class_name TownAudio
extends Node

## The town screen's construction sound.
##
## There is no town music yet. `heroes.agg` holds 169 sound effects and no
## music. The DOS original streamed its music from separate files on the CD
## (`HEROES\SOUND\heroesNN.82m/.82s/.62s`), which our install does not have;
## see `data/knowledge_base/homm1-native-data.md` section 6. The System Menu's
## Music setting is authentic and stays; in the original it set the volume of
## that streamed music.

const ART_DIR := "res://assets/art/"
const BUILD_SOUND := ART_DIR + "BUILDTWN.wav"

var enabled := true


static func build_sound_path() -> String:
	return BUILD_SOUND


func play_build() -> AudioStreamPlayer:
	if not enabled:
		return null
	var path := build_sound_path()
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	var sfx_player := AudioStreamPlayer.new()
	sfx_player.stream = stream
	add_child(sfx_player)
	sfx_player.finished.connect(sfx_player.queue_free)
	if is_inside_tree():
		sfx_player.play()
	return sfx_player
