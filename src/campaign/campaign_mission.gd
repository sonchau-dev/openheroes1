class_name CampaignMission
extends RefCounted

var id: int
var title: String
var map_path: String
var description: String
var completion_text: String
var objective: StringName
var target_faction: int = -1
var map_description: String = ""

func _init(p_id := 1, p_title := "", p_description := "", p_completion := "",
		p_objective: StringName = &"eliminate", p_target_faction := -1,
		p_map_description := "") -> void:
	id = p_id
	title = p_title
	map_path = "res://data/maps/camp%d.json" % id
	description = p_description
	completion_text = p_completion
	objective = p_objective
	target_faction = p_target_faction
	map_description = p_map_description
