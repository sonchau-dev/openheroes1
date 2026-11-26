extends RefCounted

## Where an unpacked install keeps heroes.agg, most likely first. Kept free of
## class_name globals so tools/setup.gd can preload it on a fresh
## checkout, before any import has built the class cache.
const CANDIDATES := [
	"res://external_resources/homm1game/game/Resources/hmm/data/heroes.agg",
	"res://external_resources/homm1game/data/heroes.agg",
	"res://external_resources/homm1game/DATA/HEROES.AGG",
]
