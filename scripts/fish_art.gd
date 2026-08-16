extends RefCounted
class_name FishArt
## 外部美术鱼素材(第三方付费素材包)的定位、加载与缓存;不随软件分发。

const DIR_NAME := "FishArt"
const SHEET_NAMES := ["Fishes Sprite Sheet.png", "Fishes_Sprite_Sheet.png"]
const STORE_URL := "https://elthen.itch.io/2d-pixel-art-fish-pack"

static var _sheet: Texture2D = null
static var _missing: bool = false

static func art_dir() -> String:
	var base: String
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir() + "/"
	return base + DIR_NAME + "/"

static func sheet_path() -> String:
	var d: String = art_dir()
	for n in SHEET_NAMES:
		if FileAccess.file_exists(d + n):
			return d + n
	return ""

static func is_available() -> bool:
	return sheet_path() != ""

static func sheet() -> Texture2D:
	if _sheet != null:
		return _sheet
	if _missing:
		return null
	var p: String = sheet_path()
	if p == "":
		_missing = true
		return null
	var img: Image = Image.load_from_file(p)
	if img == null or img.is_empty():
		_missing = true
		push_warning("[FishArt] unreadable sprite sheet: " + p)
		return null
	_sheet = ImageTexture.create_from_image(img)
	return _sheet

static func reload() -> void:
	_sheet = null
	_missing = false

static func ensure_dir() -> void:
	var dir_abs: String = art_dir().trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var ignore: String = dir_abs.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var f := FileAccess.open(ignore, FileAccess.WRITE)
		if f != null:
			f.store_string("")
			f.close()
