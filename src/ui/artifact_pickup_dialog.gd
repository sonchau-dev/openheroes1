# src/ui/artifact_pickup_dialog.gd
class_name ArtifactPickupDialog
extends MessageBox

## An artifact found on the map (0xb3afb: the artifact icon under its text)
## or won from a Graveyard or Shipwreck with gold (0xb533c: gold first, then
## the artifact).

func setup(artifact_id: String, message: String = "", gold := 0) -> void:
	var catalog := ArtifactCatalog.shared()
	var body := message if message != "" else catalog.pickup_text(artifact_id)
	var icons := [[ICON_ARTIFACT, artifact_id]]
	if gold > 0:
		icons.push_front([ICON_GOLD, gold])
	build(body, OKAY, icons)
