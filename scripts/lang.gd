extends Node
## i18n 单例:Lang.t(key) 取译文,切换语言发信号;Autoload。

signal language_changed(new_lang: String)

const STRINGS_PATH := "res://i18n/strings.json"
const FALLBACK_LANG := "en"

var _strings: Dictionary = {}
var _current: String = "en"


func _ready() -> void:
	_load_strings()
	if IdleSystem != null:
		_current = IdleSystem.get_language()
		IdleSystem.language_changed.connect(_on_idle_language_changed)
	print("[Lang] Ready. current=", _current, " keys_loaded=", _count_keys())


func _load_strings() -> void:
	if not FileAccess.file_exists(STRINGS_PATH):
		push_error("[Lang] Strings file missing: " + STRINGS_PATH)
		return
	var f := FileAccess.open(STRINGS_PATH, FileAccess.READ)
	if f == null:
		push_error("[Lang] Cannot open strings file: " + STRINGS_PATH)
		return
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[Lang] strings.json parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	if not json.data is Dictionary:
		push_error("[Lang] strings.json must be a dict at root")
		return
	_strings = json.data


func _on_idle_language_changed(new_lang: String) -> void:
	if new_lang == _current:
		return
	_current = new_lang
	language_changed.emit(_current)


func get_current() -> String:
	return _current


func t(key: String, args: Dictionary = {}) -> String:
	var s: String = _lookup(key)
	if args.is_empty():
		return s
	for k in args.keys():
		s = s.replace("{" + str(k) + "}", str(args[k]))
	return s


func _lookup(key: String) -> String:
	var cur_table: Dictionary = _strings.get(_current, {})
	if cur_table.has(key):
		return cur_table[key]
	var fallback_table: Dictionary = _strings.get(FALLBACK_LANG, {})
	if fallback_table.has(key):
		return fallback_table[key]

	push_warning("[Lang] Missing translation key: " + key)
	return key


func _count_keys() -> int:
	var cur_table: Dictionary = _strings.get(_current, {})
	return cur_table.size()
