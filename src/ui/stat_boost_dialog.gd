# src/ui/stat_boost_dialog.gd
class_name StatBoostDialog
extends MessageBox

## Statue, Fountain, Faerie Ring, Gazebo, Oasis and Buoy visits: the titled
## texts of the message table with the icons the visit handler passes
## (0xb2c69..0xb312e): two good-morale birds for the Statue, one for the Oasis
## and the Buoy, the luck rainbow for the Fountain and the Faerie Ring, the
## experience star with its amount for the Gazebo, and nothing on a revisit.

const TITLES := {
	"statue": "Statue",
	"fountain": "Fountain",
	"faerie_ring": "Faerie Ring",
	"gazebo": "Gazebo",
	"oasis": "Oasis",
	"buoy": "Buoy",
}
const ICONS := {
	"statue": [[ICON_GOOD_MORALE, 0], [ICON_GOOD_MORALE, 0]],
	"fountain": [[ICON_GOOD_LUCK, 0]],
	"faerie_ring": [[ICON_GOOD_LUCK, 0]],
	"oasis": [[ICON_GOOD_MORALE, 0]],
	"buoy": [[ICON_GOOD_MORALE, 0]],
}

func setup(obj_type: String, message: String, already_visited: bool = false, amount: int = 1000) -> void:
	var icons: Array = []
	if not already_visited:
		icons = [[ICON_EXPERIENCE, amount]] if obj_type == "gazebo" else ICONS.get(obj_type, [])
	build(String(TITLES.get(obj_type, obj_type.capitalize())) + "\n\n" + message, OKAY, icons)
