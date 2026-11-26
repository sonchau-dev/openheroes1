class_name Lighthouse
extends MapObject

func save_state() -> Dictionary:
	var saved := super.save_state()
	saved["owner"] = owner
	return saved

func apply_state(saved: Dictionary) -> void:
	super.apply_state(saved)
	owner = int(saved.get("owner", owner))

func to_spec() -> Dictionary:
	var spec := super.to_spec()
	spec["owner"] = owner
	return spec
