# src/ui/paid_artifact_dialog.gd
class_name PaidArtifactDialog
extends MessageBox

## The leprechaun's offer (text 0x47, a Yes/No box with the artifact icon,
## 0xb3c4a) and his refusal (0x48, text only).

const REFUSAL_MESSAGE := "Insulted by your refusal of his generous offer, the leprechaun stamps his foot ferociously and vanishes."

var _is_offer := true

func setup_offer(artifact_id: String, _price: int = 2000) -> void:
	_is_offer = true
	build("Artifact\n\n" + ArtifactPickup.offer_text(artifact_id), YES_NO, [[ICON_ARTIFACT, artifact_id]])

func setup_refusal() -> void:
	_is_offer = false
	build(REFUSAL_MESSAGE)
