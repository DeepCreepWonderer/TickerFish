extends RefCounted
class_name FishSpecies
## 鱼种定义表(精灵图行坐标等)。

const FRAME_W := 64
const FRAME_H := 32
const FRAMES_PER_ANIM := 8

const DEFAULT_SPECIES := "Anchovy"

const SPECIES_LIST := [
	{"id": "Anchovy",          "name": "Anchovy",          "y_move": 0,   "y_death": 32},
	{"id": "Tuna Fish",        "name": "Tuna",             "y_move": 64,  "y_death": 96},
	{"id": "Shortfin Batfish", "name": "Shortfin Batfish", "y_move": 128, "y_death": 160},
	{"id": "Sailfish",         "name": "Sailfish",         "y_move": 192, "y_death": 224},
	{"id": "Great Barracuda",  "name": "Great Barracuda",  "y_move": 256, "y_death": 288},
	{"id": "Silver Salmon",    "name": "Silver Salmon",    "y_move": 320, "y_death": 352},
	{"id": "Alaska Pollock",   "name": "Alaska Pollock",   "y_move": 384, "y_death": 416},
	{"id": "Red Parrot Fish",  "name": "Red Parrot Fish",  "y_move": 448, "y_death": 480},
	{"id": "Clown Fish",       "name": "Clown Fish",       "y_move": 512, "y_death": 544},
	{"id": "Atlantic Cod",     "name": "Atlantic Cod",     "y_move": 576, "y_death": 608},
	{"id": "Frontosa",         "name": "Frontosa",         "y_move": 640, "y_death": 672},
	{"id": "Blue Tang",        "name": "Blue Tang",        "y_move": 704, "y_death": 736},
]

static func get_all() -> Array:
	return SPECIES_LIST

static func is_valid(species_id: String) -> bool:
	for s in SPECIES_LIST:
		if s.id == species_id:
			return true
	return false

static func get_movement_y(species_id: String) -> int:
	for s in SPECIES_LIST:
		if s.id == species_id:
			return s.y_move
	return SPECIES_LIST[0].y_move

static func get_display_name(species_id: String) -> String:
	var fallback: String = species_id
	for s in SPECIES_LIST:
		if s.id == species_id:
			fallback = s.name
			break
	var key: String = "species." + species_id.to_lower().replace(" ", "_")
	var translated: String = Lang.t(key)
	if translated == key:
		return fallback
	return translated
