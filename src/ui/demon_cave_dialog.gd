# src/ui/demon_cave_dialog.gd
class_name DemonCaveDialog
extends MessageBox

## Daemon Cave texts 0x04..0x0a: only the entry prompt carries the title. The
## victory texts show the experience star (0xb400e), with the artifact
## (0xb408b) or the 2500 gold (0xb40ca) in front of it.

func setup(message: String, yes_no: bool, artifact_id: String = "") -> void:
	var text := message
	if message == GuardedPickup.DEMON_CAVE_ENTER_MESSAGE:
		text = GuardedPickup.DEMON_CAVE_TITLE + "\n\n" + message
	var icons := []
	match message:
		GuardedPickup.DEMON_CAVE_EXP_MESSAGE:
			icons = [[ICON_EXPERIENCE, 1000]]
		GuardedPickup.DEMON_CAVE_EXP_GOLD_MESSAGE:
			icons = [[ICON_GOLD, 2500], [ICON_EXPERIENCE, 1000]]
		GuardedPickup.DEMON_CAVE_EXP_ARTIFACT_MESSAGE:
			icons = [[ICON_ARTIFACT, artifact_id], [ICON_EXPERIENCE, 1000]]
	build(text, YES_NO if yes_no else OKAY, icons)
