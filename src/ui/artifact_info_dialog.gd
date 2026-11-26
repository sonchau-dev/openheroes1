# src/ui/artifact_info_dialog.gd
class_name ArtifactInfoDialog
extends MessageBox

## An artifact's information text (heroes.exe 0xb1a7c shows it as one text
## field) over the hero screen, held open under the right button or closed
## with OKAY.

var _hold := false

func setup(artifact_id: String, hold := false) -> void:
	_hold = hold
	build(ArtifactCatalog.shared().info_text(artifact_id), HOLD if hold else OKAY, [], false)
