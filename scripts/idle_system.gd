extends Node
## 存档与状态中枢:自选表、鱼、多鱼缸;Autoload。


signal fish_list_changed
signal fish_skin_changed(new_skin: String)
signal language_changed(new_lang: String)
signal color_tone_changed(new_tone: String)
signal show_ticker_labels_changed(new_value: bool)
signal display_mode_changed(new_mode: String)
signal numeric_list_changed
signal tank_list_changed
signal active_tank_changed(tank_id: String)
signal price_stream_changed(enabled: bool)
signal alert_history_changed
signal global_limit_reached
signal tank_full
signal duplicate_skipped(symbol: String)
signal alerts_enabled_changed(enabled: bool)
signal alert_threshold_changed(key: String)


const SAVE_VERSION := 2
const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.json.bak"
const BROKEN_PATH := "user://save.json.broken"

const TICK_SECONDS := 1.0
const SAVE_INTERVAL_SECONDS := 30

# ---- 上限(全局唯一标的数压在 Finnhub 60/分之下) ----
const MAX_FISH_PER_TANK := 20
const MAX_TOTAL_SYMBOLS := 50
const MAX_TANKS := 10

const DEFAULT_TANK_ID := "tank_1"
const DEFAULT_TANK_NAME := ""
const DEFAULT_TANK_ICON := "🐟"

const DEFAULT_FIRST_FISH := [
	{"id": "f001", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"},
	{"id": "f002", "nickname": "NVDA", "market": "stocks", "symbol": "NVDA"},
	{"id": "f003", "nickname": "TSLA", "market": "stocks", "symbol": "TSLA"},
]


var _data: Dictionary = {}
var _last_save_at_runtime: float = 0.0
var _tick_timer: Timer
var _last_realtime_ms: int = 0


func _ready() -> void:
	_load_or_create_save()
	_maybe_recover_lost_active()
	_last_realtime_ms = Time.get_ticks_msec()

	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_SECONDS
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_tick_timer.start()

	_write_watchlist_file()

	var active := get_active_tank()
	var fish_count: int = active.get("fish", []).size() if not active.is_empty() else 0
	print("[Idle] Save loaded. runtime=", _format_seconds(_data.get("total_runtime", 0)),
		" tanks=", get_tanks().size(),
		" active=", get_active_tank_id(),
		" fish_in_active=", fish_count)

func _on_tick() -> void:
	var now_ms := Time.get_ticks_msec()
	var dt_ms := now_ms - _last_realtime_ms
	_last_realtime_ms = now_ms

	var dt_sec: float
	if dt_ms < 0 or dt_ms > 5000:
		dt_sec = TICK_SECONDS
	else:
		dt_sec = dt_ms / 1000.0

	_data["total_runtime"] = _data.get("total_runtime", 0.0) + dt_sec


	var now_runtime: float = _data["total_runtime"]
	if now_runtime - _last_save_at_runtime > SAVE_INTERVAL_SECONDS:
		_save()
		_last_save_at_runtime = now_runtime


func _load_or_create_save() -> void:
	for path in [SAVE_PATH, BACKUP_PATH]:
		var parsed = _read_save_file(path)
		if not (parsed is Dictionary):
			continue
		if path == BACKUP_PATH:
			push_warning("[Idle] save.json unreadable; recovered from save.json.bak")
		_data = parsed
		var loaded_v: int = int(_data.get("version", 0))
		if loaded_v != SAVE_VERSION:
			if _try_migrate(loaded_v):
				print("[Idle] Save migrated v", loaded_v, " → v", SAVE_VERSION)
			else:
				push_warning("[Idle] Save migration failed (v%d → v%d); resetting to defaults" % [loaded_v, SAVE_VERSION])
				_data = _default_save()
		_ensure_fields()
		return
	_quarantine_broken_save()
	_data = _default_save()
	_save()

func _read_save_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

func _quarantine_broken_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var dir := DirAccess.open(SAVE_PATH.get_base_dir())
	if dir == null:
		return
	if FileAccess.file_exists(BROKEN_PATH):
		dir.remove(BROKEN_PATH.get_file())
	dir.rename(SAVE_PATH.get_file(), BROKEN_PATH.get_file())
	push_warning("[Idle] Unreadable save kept as save.json.broken; starting from defaults")

func _try_migrate(from_v: int) -> bool:
	if from_v > SAVE_VERSION:
		push_warning("[Idle] Save version newer than program (v%d > v%d); downgrade not supported" % [from_v, SAVE_VERSION])
		return false
	var v := from_v
	while v < SAVE_VERSION:
		var next_v: int = v + 1
		var ok := false
		match v:
			0:
				ok = _migrate_v1_to_v2()
				next_v = 2
			1:
				ok = _migrate_v1_to_v2()
			_:
				push_warning("[Idle] No migration function for v%d → v%d" % [v, next_v])
		if not ok:
			return false
		v = next_v
		_data["version"] = v
	return true

func _migrate_v1_to_v2() -> bool:
	var old_fish: Array = _data.get("fish_list", [])
	var default_tank := {
		"id": DEFAULT_TANK_ID,
		"name": DEFAULT_TANK_NAME,
		"icon": DEFAULT_TANK_ICON,
		"is_preset": false,
		"fish": old_fish,
	}
	_data["tanks"] = [default_tank]
	_data["active_tank_id"] = DEFAULT_TANK_ID
	_data.erase("fish_list")
	_data.erase("unlocked_slots")
	return true

func _default_save() -> Dictionary:
	var tank_1 := {
		"id": DEFAULT_TANK_ID,
		"name": DEFAULT_TANK_NAME,
		"icon": DEFAULT_TANK_ICON,
		"is_preset": false,
		"fish": DEFAULT_FIRST_FISH.duplicate(true),
	}
	var tank_2 := {
		"id": "tank_2",
		"name": "",
		"icon": DEFAULT_TANK_ICON,
		"is_preset": false,
		"fish": [],
	}
	return {
		"version": SAVE_VERSION,
		"total_runtime": 0.0,
		"tanks": [tank_1, tank_2],
		"active_tank_id": DEFAULT_TANK_ID,
		"window": {},
		"settings": {},
	}

func _ensure_fields() -> void:
	if not _data.has("tanks") or not (_data["tanks"] is Array) or _data["tanks"].is_empty():
		_data["tanks"] = [{
			"id": DEFAULT_TANK_ID,
			"name": DEFAULT_TANK_NAME,
			"icon": DEFAULT_TANK_ICON,
			"is_preset": false,
			"fish": [],
		}]
	if not _data.has("active_tank_id"):
		_data["active_tank_id"] = _data["tanks"][0].get("id", DEFAULT_TANK_ID)
	if _find_tank_index(_data["active_tank_id"]) < 0:
		_data["active_tank_id"] = _data["tanks"][0].get("id", DEFAULT_TANK_ID)
	if not _data.has("window"):
		_data["window"] = {}
	if not _data.has("settings"):
		_data["settings"] = {}
	if not _data.get("legacy_tank_names_cleared", false):
		var re := RegEx.new()
		re.compile("^Tank \\d+$")
		for t in _data["tanks"]:
			var nm: String = str(t.get("name", ""))
			if nm == "My Tank" or re.search(nm) != null:
				t["name"] = ""
		_data["legacy_tank_names_cleared"] = true

func _save() -> void:
	var tmp_path: String = SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[Idle] Failed to write save")
		return
	f.store_string(JSON.stringify(_data, "  "))
	f.close()

	var dir := DirAccess.open(SAVE_PATH.get_base_dir())
	if dir == null:
		push_error("[Idle] Failed to open user dir")
		return
	if FileAccess.file_exists(SAVE_PATH):
		dir.rename(SAVE_PATH.get_file(), BACKUP_PATH.get_file())
	if dir.rename(tmp_path.get_file(), SAVE_PATH.get_file()) != OK:
		push_error("[Idle] Failed to commit save")


func is_first_after_hours_pending() -> bool:
	return _data.get("first_after_hours_done", false) == false

func mark_first_after_hours_done() -> void:
	_data["first_after_hours_done"] = true
	_save()

func save_window_state(pos: Vector2i, size: Vector2i, mode: String = "") -> void:
	var key: String = ("window_" + mode) if mode != "" else "window"
	_data[key] = {
		"x": pos.x, "y": pos.y,
		"w": size.x, "h": size.y,
	}
	_save()

func get_window_state(mode: String = "") -> Dictionary:
	if mode != "":
		var key: String = "window_" + mode
		if _data.has(key):
			return _data[key]
		if mode == "fish_tank":
			return _data.get("window", {})
		return {}
	return _data.get("window", {})


func get_selected_market() -> String:
	var settings: Dictionary = _data.get("settings", {})
	var m: String = str(settings.get("selected_market", "stocks"))
	return m if m == "crypto" else "stocks"

func set_selected_market(market: String) -> void:
	var m: String = market if market == "crypto" else "stocks"
	var settings: Dictionary = _data.get("settings", {})
	if str(settings.get("selected_market", "")) == m:
		return
	settings["selected_market"] = m
	_data["settings"] = settings
	_save()

func get_context_market() -> String:
	var items: Array = get_numeric_list() if get_display_mode() != "fish_tank" else get_fish_list()
	var has_stocks := false
	var has_crypto := false
	for it in items:
		if str(it.get("market", "stocks")) == "crypto":
			has_crypto = true
		else:
			has_stocks = true
	if has_crypto and not has_stocks:
		return "crypto"
	if has_stocks and not has_crypto:
		return "stocks"
	return get_selected_market()

func get_always_on_top() -> bool:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("always_on_top", false)

func save_always_on_top(on: bool) -> void:
	var settings: Dictionary = _data.get("settings", {})
	settings["always_on_top"] = on
	_data["settings"] = settings
	_save()

const FISH_SKIN_DEFAULT := "minimal"

func get_fish_skin() -> String:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("fish_skin", FISH_SKIN_DEFAULT)

func save_fish_skin(skin: String) -> void:
	if skin == "":
		return
	var settings: Dictionary = _data.get("settings", {})
	var old: String = settings.get("fish_skin", FISH_SKIN_DEFAULT)
	if old == skin:
		return
	settings["fish_skin"] = skin
	_data["settings"] = settings
	_save()
	fish_skin_changed.emit(skin)
	print("[Idle] Fish skin changed: ", old, " -> ", skin)

const COLOR_TONE_DEFAULT := "deep_water"

func get_color_tone() -> String:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("color_tone", COLOR_TONE_DEFAULT)

func save_color_tone(tone: String) -> void:
	if tone == "":
		return
	var settings: Dictionary = _data.get("settings", {})
	var old: String = settings.get("color_tone", COLOR_TONE_DEFAULT)
	if old == tone:
		return
	settings["color_tone"] = tone
	_data["settings"] = settings
	_save()
	color_tone_changed.emit(tone)

const SHOW_TICKER_LABELS_DEFAULT := true

func get_show_ticker_labels() -> bool:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("show_ticker_labels", SHOW_TICKER_LABELS_DEFAULT)

func save_show_ticker_labels(value: bool) -> void:
	var settings: Dictionary = _data.get("settings", {})
	var old: bool = settings.get("show_ticker_labels", SHOW_TICKER_LABELS_DEFAULT)
	if old == value:
		return
	settings["show_ticker_labels"] = value
	_data["settings"] = settings
	_save()
	show_ticker_labels_changed.emit(value)
	print("[Idle] Show ticker labels: ", old, " -> ", value)

const DISPLAY_MODE_DEFAULT := "fish_tank"
const DISPLAY_MODE_VALID := ["fish_tank", "numeric", "hero", "strip"]

func get_display_mode() -> String:
	var settings: Dictionary = _data.get("settings", {})
	var mode: String = settings.get("display_mode", DISPLAY_MODE_DEFAULT)
	if not mode in DISPLAY_MODE_VALID:
		return DISPLAY_MODE_DEFAULT
	return mode

func save_display_mode(mode: String) -> void:
	if not mode in DISPLAY_MODE_VALID:
		push_warning("[Idle] save_display_mode got invalid mode: " + mode)
		return
	var settings: Dictionary = _data.get("settings", {})
	var old: String = settings.get("display_mode", DISPLAY_MODE_DEFAULT)
	if old == mode:
		return
	settings["display_mode"] = mode
	_data["settings"] = settings
	_save()
	display_mode_changed.emit(mode)
	print("[Idle] Display mode: ", old, " -> ", mode)

const HERO_ROTATE_DEFAULT := 60
const HERO_ROTATE_VALID := [20, 60, 300]

func get_hero_rotate_secs() -> int:
	var settings: Dictionary = _data.get("settings", {})
	var v: int = int(settings.get("hero_rotate_secs", HERO_ROTATE_DEFAULT))
	if not v in HERO_ROTATE_VALID:
		return HERO_ROTATE_DEFAULT
	return v

const HERO_MAX_PANELS := 10

const HERO_PANEL_CAP := 5

func get_hero_panels() -> Array:
	var settings: Dictionary = _data.get("settings", {})
	if settings.has("hero_panels"):
		var p = settings.get("hero_panels", [])
		if p is Array and not p.is_empty():
			return _reconcile_hero_panels(p)
	return _default_hero_panels()

func _market_syms(market: String) -> Array:
	var out: Array = []
	for it in get_numeric_list():
		if str(it.get("market", "stocks")) == market:
			out.append(str(it.get("symbol", "")))
	return out

func _default_hero_panels() -> Array:
	var out: Array = []
	for market in ["stocks", "crypto"]:
		var syms: Array = _market_syms(market)
		var i := 0
		while i < syms.size():
			out.append({"market": market, "syms": syms.slice(i, i + HERO_PANEL_CAP), "title": "", "manual": false, "interval": HERO_ROTATE_DEFAULT})
			i += HERO_PANEL_CAP
	if out.is_empty():
		out.append({"market": "stocks", "syms": [], "title": "", "manual": false, "interval": HERO_ROTATE_DEFAULT})
	return out

func _reconcile_hero_panels(stored: Array) -> Array:
	var live := {}
	for it in get_numeric_list():
		live[str(it.get("market", "stocks")) + ":" + str(it.get("symbol", ""))] = true
	var hidden := {}
	for k in (_data.get("settings", {}) as Dictionary).get("hero_hidden", []):
		hidden[str(k)] = true
	var seed_iv: int = get_hero_rotate_secs()
	var panels: Array = []
	var assigned := {}
	for p in stored:
		var market: String
		var syms: Array
		var title := ""
		var manual := false
		var interval: int = seed_iv
		if p is String:
			market = str(p)
			syms = []
		elif p is Dictionary:
			market = str(p.get("market", "stocks"))
			syms = p.get("syms", []) if p.get("syms", []) is Array else []
			title = str(p.get("title", ""))
			manual = bool(p.get("manual", false))
			interval = int(p.get("interval", seed_iv))
		else:
			continue
		if market != "stocks" and market != "crypto":
			market = "stocks"
		var kept: Array = []
		for s in syms:
			var key := market + ":" + str(s)
			if live.has(key) and not assigned.has(key) and kept.size() < HERO_PANEL_CAP:
				kept.append(str(s))
				assigned[key] = true
		panels.append({"market": market, "syms": kept, "title": title, "manual": manual, "interval": interval})
	for it in get_numeric_list():
		var m := str(it.get("market", "stocks"))
		var s := str(it.get("symbol", ""))
		var key := m + ":" + s
		if assigned.has(key):
			continue
		if hidden.has(key):
			continue
		var placed := false
		for p in panels:
			if str(p["market"]) == m and not bool(p["manual"]) and (p["syms"] as Array).size() < HERO_PANEL_CAP:
				p["syms"].append(s)
				assigned[key] = true
				placed = true
				break
		if not placed:
			panels.append({"market": m, "syms": [s], "title": "", "manual": false, "interval": HERO_ROTATE_DEFAULT})
			assigned[key] = true
	return panels

func set_hero_panel_content(index: int, syms: Array, title: String, interval: int = HERO_ROTATE_DEFAULT) -> bool:
	var cur: Array = get_hero_panels()
	if index < 0 or index >= cur.size():
		return false
	var market: String = str(cur[index]["market"])
	var live := {}
	for it in get_numeric_list():
		if str(it.get("market", "stocks")) == market:
			live[str(it.get("symbol", ""))] = true
	var clean: Array = []
	for s in syms:
		var sym := str(s)
		if live.has(sym) and not clean.has(sym) and clean.size() < HERO_PANEL_CAP:
			clean.append(sym)
	var removed: Array = []
	var readded: Array = []
	for s in (cur[index]["syms"] if cur[index]["syms"] is Array else []):
		if not (str(s) in clean):
			removed.append(market + ":" + str(s))
	for s in clean:
		readded.append(market + ":" + str(s))
	_update_hero_hidden(removed, readded)
	for i in range(cur.size()):
		if i == index or str(cur[i]["market"]) != market:
			continue
		var filtered: Array = []
		for s in cur[i]["syms"]:
			if not (str(s) in clean):
				filtered.append(s)
		cur[i]["syms"] = filtered
	cur[index]["syms"] = clean
	cur[index]["title"] = title
	cur[index]["manual"] = true
	cur[index]["interval"] = maxi(interval, 1)
	_set_hero_panels(cur)
	return true

func add_hero_panel(market: String) -> bool:
	if market != "stocks" and market != "crypto":
		return false
	var cur: Array = get_hero_panels().duplicate()
	if cur.size() >= HERO_MAX_PANELS:
		return false
	cur.append({"market": market, "syms": []})
	_set_hero_panels(cur)
	return true

func remove_hero_panel(index: int) -> bool:
	var cur: Array = get_hero_panels().duplicate()
	if cur.size() <= 1 or index < 0 or index >= cur.size():
		return false
	var market: String = str(cur[index].get("market", "stocks"))
	var hide: Array = []
	for s in (cur[index]["syms"] if cur[index]["syms"] is Array else []):
		hide.append(market + ":" + str(s))
	_update_hero_hidden(hide, [])
	cur.remove_at(index)
	_set_hero_panels(cur)
	return true

func reorder_hero_panel(from_idx: int, to_idx: int) -> bool:
	var cur: Array = get_hero_panels().duplicate()
	if from_idx < 0 or from_idx >= cur.size():
		return false
	to_idx = clampi(to_idx, 0, cur.size() - 1)
	if to_idx == from_idx:
		return false
	var v = cur[from_idx]
	cur.remove_at(from_idx)
	cur.insert(to_idx, v)
	_set_hero_panels(cur)
	return true

func reset_hero_panels() -> void:
	var settings: Dictionary = _data.get("settings", {})
	if settings.has("hero_panels") or settings.has("hero_hidden"):
		settings.erase("hero_panels")
		settings.erase("hero_hidden")
		_data["settings"] = settings
		_save()

func _update_hero_hidden(add_keys: Array, remove_keys: Array) -> void:
	var settings: Dictionary = _data.get("settings", {})
	var hidden := {}
	for k in settings.get("hero_hidden", []):
		hidden[str(k)] = true
	for k in add_keys:
		hidden[str(k)] = true
	for k in remove_keys:
		hidden.erase(str(k))
	settings["hero_hidden"] = hidden.keys()
	_data["settings"] = settings

func _set_hero_panels(arr: Array) -> void:
	var settings: Dictionary = _data.get("settings", {})
	settings["hero_panels"] = arr
	if settings.has("hero_hidden"):
		var live := {}
		for it in get_numeric_list():
			live[str(it.get("market", "stocks")) + ":" + str(it.get("symbol", ""))] = true
		var pruned: Array = []
		for k in settings.get("hero_hidden", []):
			if live.has(str(k)):
				pruned.append(str(k))
		settings["hero_hidden"] = pruned
	_data["settings"] = settings
	_save()

const LANG_DEFAULT := "en"
const LANG_VALID := ["en", "zh"]

func get_language() -> String:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("language", LANG_DEFAULT)

func save_language(lang: String) -> void:
	if not lang in LANG_VALID:
		push_warning("[Idle] save_language got invalid lang: " + lang)
		return
	var settings: Dictionary = _data.get("settings", {})
	var old: String = settings.get("language", LANG_DEFAULT)
	if old == lang:
		return
	settings["language"] = lang
	_data["settings"] = settings
	_save()
	language_changed.emit(lang)
	print("[Idle] Language: ", old, " -> ", lang)


const PRICE_STREAM_INTERVAL_DEFAULT := 30
const PRICE_STREAM_INTERVAL_VALID := [15, 30, 60]

func get_price_stream_enabled() -> bool:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("price_stream_enabled", false)

func save_price_stream_enabled(on: bool) -> void:
	var settings: Dictionary = _data.get("settings", {})
	var old: bool = settings.get("price_stream_enabled", false)
	if old == on:
		return
	settings["price_stream_enabled"] = on
	_data["settings"] = settings
	_save()
	price_stream_changed.emit(on)
	print("[Idle] Price stream enabled: ", old, " -> ", on)

func get_price_stream_interval_min() -> int:
	var settings: Dictionary = _data.get("settings", {})
	var v: int = int(settings.get("price_stream_interval_min", PRICE_STREAM_INTERVAL_DEFAULT))
	if not v in PRICE_STREAM_INTERVAL_VALID:
		return PRICE_STREAM_INTERVAL_DEFAULT
	return v

func save_price_stream_interval_min(minutes: int) -> void:
	if not minutes in PRICE_STREAM_INTERVAL_VALID:
		push_warning("[Idle] save_price_stream_interval_min got invalid value: %d" % minutes)
		return
	var settings: Dictionary = _data.get("settings", {})
	settings["price_stream_interval_min"] = minutes
	_data["settings"] = settings
	_save()
	print("[Idle] Price stream interval: ", minutes, " min")

func get_price_stream_excluded() -> Array:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("price_stream_excluded", [])

func is_symbol_recorded(market_symbol_key: String) -> bool:
	return not (market_symbol_key in get_price_stream_excluded())

func set_symbol_recorded(market_symbol_key: String, recorded: bool) -> void:
	var settings: Dictionary = _data.get("settings", {})
	var excluded: Array = settings.get("price_stream_excluded", [])
	var has: bool = market_symbol_key in excluded
	if recorded and has:
		excluded.erase(market_symbol_key)
	elif not recorded and not has:
		excluded.append(market_symbol_key)
	else:
		return
	settings["price_stream_excluded"] = excluded
	_data["settings"] = settings
	_save()

func is_price_stream_prompted() -> bool:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("price_stream_prompted", false)

func mark_price_stream_prompted() -> void:
	var settings: Dictionary = _data.get("settings", {})
	settings["price_stream_prompted"] = true
	_data["settings"] = settings
	_save()


const ALERT_THRESHOLD_DEFAULT := 3.0
const ALERT_HISTORY_CAP := 500

func get_alerts_enabled() -> bool:
	var settings: Dictionary = _data.get("settings", {})
	return bool(settings.get("alerts_enabled", false))

func save_alerts_enabled(on: bool) -> void:
	var settings: Dictionary = _data.get("settings", {})
	if bool(settings.get("alerts_enabled", false)) == on:
		return
	settings["alerts_enabled"] = on
	_data["settings"] = settings
	_save()
	print("[Idle] Alerts master switch → ", on)
	alerts_enabled_changed.emit(on)

func get_alert_steps(today: String) -> Dictionary:
	var st = _data.get("alert_state", {})
	if not (st is Dictionary) or str(st.get("date", "")) != today:
		return {}
	var steps = st.get("steps", {})
	return steps if steps is Dictionary else {}

func save_alert_steps(today: String, steps: Dictionary) -> void:
	_data["alert_state"] = {"date": today, "steps": steps}
	_save()

func clear_alert_steps() -> void:
	_data["alert_state"] = {}
	_save()

func get_alert_config(key: String) -> Dictionary:
	var alerts: Dictionary = _data.get("alerts", {})
	var c = alerts.get(key, null)
	if c is Dictionary:
		return {
			"threshold": float(c.get("threshold", ALERT_THRESHOLD_DEFAULT)),
			"enabled": bool(c.get("enabled", false)),
		}
	return {"threshold": ALERT_THRESHOLD_DEFAULT, "enabled": false}

func set_alert_config(key: String, threshold: float, enabled: bool) -> void:
	var alerts: Dictionary = _data.get("alerts", {})
	var new_threshold: float = maxf(threshold, 0.1)
	var old_threshold: float = float(get_alert_config(key).get("threshold", ALERT_THRESHOLD_DEFAULT))
	alerts[key] = {"threshold": new_threshold, "enabled": enabled}
	_data["alerts"] = alerts
	if not is_equal_approx(old_threshold, new_threshold):
		_drop_alert_step(key)
		alert_threshold_changed.emit(key)
	_save()

func _drop_alert_step(key: String) -> void:
	var st = _data.get("alert_state", {})
	if not (st is Dictionary):
		return
	var steps = st.get("steps", {})
	if steps is Dictionary and steps.has(key):
		steps.erase(key)
		st["steps"] = steps
		_data["alert_state"] = st

func prune_orphan_alert_configs() -> void:
	var alerts: Dictionary = _data.get("alerts", {})
	if alerts.is_empty():
		return
	var live := {}
	for e in get_all_watchlist_entries():
		live[str(e.get("market", "")) + ":" + str(e.get("symbol", ""))] = true
	var changed := false
	for key in alerts.keys():
		if not live.has(key):
			alerts.erase(key)
			changed = true
	if changed:
		_data["alerts"] = alerts
		_save()

func get_alert_history() -> Array:
	return _data.get("alert_history", [])

func add_alert_record(record: Dictionary) -> void:
	var hist: Array = _data.get("alert_history", [])
	record["unread"] = true
	hist.push_front(record)
	while hist.size() > ALERT_HISTORY_CAP:
		hist.pop_back()
	_data["alert_history"] = hist
	_save()
	alert_history_changed.emit()

func get_unread_alert_count() -> int:
	var n := 0
	for r in get_alert_history():
		if r is Dictionary and r.get("unread", false):
			n += 1
	return n

func mark_all_alerts_read() -> void:
	var hist: Array = _data.get("alert_history", [])
	var changed := false
	for r in hist:
		if r is Dictionary and r.get("unread", false):
			r["unread"] = false
			changed = true
	if changed:
		_data["alert_history"] = hist
		_save()
		alert_history_changed.emit()


func get_tanks() -> Array:
	return _data.get("tanks", [])

func get_active_tank_id() -> String:
	var id: String = _data.get("active_tank_id", "")
	if id == "":
		var tanks := get_tanks()
		if tanks.size() > 0:
			id = tanks[0].get("id", "")
	return id

func get_active_tank() -> Dictionary:
	return _find_tank(get_active_tank_id())

func get_tank(tank_id: String) -> Dictionary:
	return _find_tank(tank_id)

func _find_tank(tank_id: String) -> Dictionary:
	for t in get_tanks():
		if t.get("id", "") == tank_id:
			return t
	return {}

func _find_tank_index(tank_id: String) -> int:
	var tanks := get_tanks()
	for i in range(tanks.size()):
		if tanks[i].get("id", "") == tank_id:
			return i
	return -1

func set_active_tank(tank_id: String) -> bool:
	if _find_tank_index(tank_id) < 0:
		push_warning("[Idle] set_active_tank: unknown tank id: " + tank_id)
		return false
	if _data.get("active_tank_id", "") == tank_id:
		return true
	_data["active_tank_id"] = tank_id
	_save()
	active_tank_changed.emit(tank_id)
	fish_list_changed.emit()
	print("[Idle] Active tank → ", tank_id)
	return true

func is_tank_limit_reached() -> bool:
	return get_tanks().size() >= MAX_TANKS

func create_tank(tank_name: String = "", icon: String = "") -> Dictionary:
	var tanks := get_tanks()
	if tanks.size() >= MAX_TANKS:
		push_warning("[Idle] create_tank: tank limit reached (%d)" % MAX_TANKS)
		return {}
	var max_n := 0
	for t in tanks:
		var id: String = t.get("id", "")
		if id.begins_with("tank_"):
			max_n = max(max_n, int(id.substr(5)))
	var new_id := "tank_%d" % (max_n + 1)
	var new_tank := {
		"id": new_id,
		"name": tank_name.strip_edges(),
		"icon": icon if icon != "" else DEFAULT_TANK_ICON,
		"is_preset": false,
		"fish": [],
	}
	tanks.append(new_tank)
	_data["tanks"] = tanks
	_save()
	tank_list_changed.emit()
	print("[Idle] Created tank: ", new_id, " '", new_tank["name"], "'")
	return new_tank

func _maybe_recover_lost_active() -> void:
	if _data.get("v6_recovery_done", false):
		return
	_data["v6_recovery_done"] = true
	var active := get_active_tank()
	if active.is_empty() or not active.get("fish", []).is_empty():
		_save()
		return
	var best_id: String = ""
	var best_count: int = 0
	for t in get_tanks():
		if t.get("id", "") == active.get("id", ""):
			continue
		var n: int = t.get("fish", []).size()
		if n > best_count:
			best_count = n
			best_id = t.get("id", "")
	if best_id != "":
		print("[Idle] V6 recovery: active tank '", active.get("id", ""),
			"' is empty; switching to '", best_id, "' (", best_count, " fish)")
		set_active_tank(best_id)
	else:
		_save()

func rename_tank(tank_id: String, new_name: String) -> bool:
	if new_name.strip_edges() == "":
		return false
	var t := _find_tank(tank_id)
	if t.is_empty():
		return false
	t["name"] = new_name
	_save()
	tank_list_changed.emit()
	print("[Idle] Renamed tank ", tank_id, " → '", new_name, "'")
	return true

func delete_tank(tank_id: String) -> bool:
	var tanks := get_tanks()
	if tanks.size() <= 1:
		push_warning("[Idle] Cannot delete the last tank")
		return false
	var idx := _find_tank_index(tank_id)
	if idx < 0:
		return false
	if not tanks[idx].get("fish", []).is_empty():
		push_warning("[Idle] Cannot delete a tank that still has fish")
		return false
	tanks.remove_at(idx)
	_data["tanks"] = tanks
	var was_active: bool = _data.get("active_tank_id", "") == tank_id
	if was_active:
		_data["active_tank_id"] = tanks[0].get("id", "")
	_save()
	_write_watchlist_file()
	tank_list_changed.emit()
	if was_active:
		active_tank_changed.emit(_data["active_tank_id"])
		fish_list_changed.emit()
	print("[Idle] Deleted tank: ", tank_id)
	return true

func is_active_tank_full() -> bool:
	return get_fish_list().size() >= MAX_FISH_PER_TANK


func get_fish_list() -> Array:
	var t := get_active_tank()
	if t.is_empty():
		return []
	return t.get("fish", [])

func add_fish(nickname: String, market: String, symbol: String, species: String = "", design: int = -1) -> Dictionary:
	var t := get_active_tank()
	if t.is_empty():
		push_error("[Idle] add_fish: no active tank")
		return {}
	symbol = symbol.strip_edges().to_upper()
	if symbol == "":
		return {}

	var existing: Array = t.get("fish", [])
	var key := market + ":" + symbol
	for f in existing:
		if (str(f.get("market", "")) + ":" + str(f.get("symbol", "")).to_upper()) == key:
			print("[Idle] add_fish: ", key, " already in tank ", t.get("id", ""), ", skipping")
			duplicate_skipped.emit(symbol)
			return {}

	if existing.size() >= MAX_FISH_PER_TANK:
		push_warning("[Idle] add_fish: tank '%s' is full (max %d)" % [t.get("name", ""), MAX_FISH_PER_TANK])
		tank_full.emit()
		return {}

	if _is_new_global_symbol(market, symbol) and is_global_limit_reached():
		push_warning("[Idle] add_fish: global watchlist cap reached (max %d)" % MAX_TOTAL_SYMBOLS)
		global_limit_reached.emit()
		return {}

	var max_n := 0
	for tt in get_tanks():
		for f in tt.get("fish", []):
			var id: String = f.get("id", "")
			if id.begins_with("f"):
				max_n = max(max_n, int(id.substr(1)))
	var new_id := "f%03d" % (max_n + 1)

	if species == "" or not FishSpecies.is_valid(species):
		species = FishSpecies.DEFAULT_SPECIES

	var new_fish := {
		"id": new_id,
		"nickname": nickname,
		"market": market,
		"symbol": symbol,
		"species": species,
		"design": design,
	}
	existing.append(new_fish)
	t["fish"] = existing
	_save()
	_write_watchlist_file()
	fish_list_changed.emit()
	print("[Idle] Added fish: ", new_id, " ", nickname, " (", market, ":", symbol, ") species=", species, " → tank=", t.get("id", ""))
	return new_fish

func remove_fish(fish_id: String) -> bool:
	var t := get_active_tank()
	if t.is_empty():
		return false
	var existing: Array = t.get("fish", [])
	for i in range(existing.size()):
		if existing[i].get("id", "") == fish_id:
			existing.remove_at(i)
			t["fish"] = existing
			_save()
			_write_watchlist_file()
			fish_list_changed.emit()
			print("[Idle] Removed fish: ", fish_id, " from tank=", t.get("id", ""))
			return true
	return false

func update_fish_design(fish_id: String, new_design: int) -> bool:
	if new_design < 0 or new_design >= LottieFish.DESIGN_COUNT:
		push_error("[Idle] update_fish_design got invalid design: " + str(new_design))
		return false
	for t in get_tanks():
		var existing: Array = t.get("fish", [])
		for fish in existing:
			if fish.get("id", "") == fish_id:
				if int(fish.get("design", -1)) == new_design:
					return true
				fish["design"] = new_design
				t["fish"] = existing
				_save()
				fish_list_changed.emit()
				print("[Idle] Fish ", fish_id, " design changed to: ", new_design)
				return true
	return false

func update_fish_species(fish_id: String, new_species: String) -> bool:
	if not FishSpecies.is_valid(new_species):
		push_error("[Idle] update_fish_species got invalid species: " + new_species)
		return false
	for t in get_tanks():
		var existing: Array = t.get("fish", [])
		for fish in existing:
			if fish.get("id", "") == fish_id:
				if fish.get("species", "") == new_species:
					return true
				fish["species"] = new_species
				t["fish"] = existing
				_save()
				fish_list_changed.emit()
				print("[Idle] Fish ", fish_id, " species changed to: ", new_species)
				return true
	return false


const MAX_NUMERIC_ITEMS := 30

func get_numeric_list() -> Array:
	var settings: Dictionary = _data.get("settings", {})
	return settings.get("numeric_watchlist", [])

func is_numeric_list_full() -> bool:
	return get_numeric_list().size() >= MAX_NUMERIC_ITEMS

func add_numeric_item(symbol: String, market: String = "stocks", nickname: String = "") -> Dictionary:
	symbol = symbol.strip_edges().to_upper()
	if symbol == "":
		return {}
	var settings: Dictionary = _data.get("settings", {})
	var list: Array = settings.get("numeric_watchlist", [])

	var key := market + ":" + symbol
	for item in list:
		if (str(item.get("market", "")) + ":" + str(item.get("symbol", "")).to_upper()) == key:
			print("[Idle] numeric add: ", key, " already present, skipping")
			duplicate_skipped.emit(symbol)
			return {}

	if list.size() >= MAX_NUMERIC_ITEMS:
		push_warning("[Idle] add_numeric_item: list full (max %d)" % MAX_NUMERIC_ITEMS)
		return {}

	if _is_new_global_symbol(market, symbol) and is_global_limit_reached():
		push_warning("[Idle] add_numeric_item: global watchlist cap reached (max %d)" % MAX_TOTAL_SYMBOLS)
		global_limit_reached.emit()
		return {}

	var max_n := 0
	for item in list:
		var id: String = str(item.get("id", ""))
		if id.begins_with("n"):
			max_n = max(max_n, int(id.substr(1)))
	var new_id := "n%03d" % (max_n + 1)

	var new_item := {
		"id": new_id,
		"symbol": symbol,
		"market": market,
		"nickname": nickname,
	}
	list.append(new_item)
	settings["numeric_watchlist"] = list
	_data["settings"] = settings
	_save()
	_write_watchlist_file()
	numeric_list_changed.emit()
	print("[Idle] Added numeric item: ", new_id, " ", symbol, " (", key, ")")
	return new_item

func reorder_numeric_item(from_idx: int, to_idx: int) -> bool:
	var settings: Dictionary = _data.get("settings", {})
	var list: Array = settings.get("numeric_watchlist", [])
	if from_idx < 0 or from_idx >= list.size():
		return false
	to_idx = clampi(to_idx, 0, list.size() - 1)
	if to_idx == from_idx:
		return false
	var v = list[from_idx]
	list.remove_at(from_idx)
	list.insert(to_idx, v)
	settings["numeric_watchlist"] = list
	_data["settings"] = settings
	_save()
	_write_watchlist_file()
	numeric_list_changed.emit()
	print("[Idle] Reordered numeric item ", from_idx, " → ", to_idx)
	return true

func set_numeric_item_group(item_id: String, group: String) -> bool:
	var settings: Dictionary = _data.get("settings", {})
	var list: Array = settings.get("numeric_watchlist", [])
	group = group.strip_edges()
	for item in list:
		if str(item.get("id", "")) != item_id:
			continue
		if str(item.get("group", "")) == group:
			return false
		if group == "":
			item.erase("group")
		else:
			item["group"] = group
		settings["numeric_watchlist"] = list
		_data["settings"] = settings
		_save()
		numeric_list_changed.emit()
		print("[Idle] Numeric item ", item_id, " group → '", group, "'")
		return true
	return false

func get_numeric_item(item_id: String) -> Dictionary:
	for item in get_numeric_list():
		if str(item.get("id", "")) == item_id:
			return item
	return {}

func remove_numeric_item(item_id: String) -> bool:
	var settings: Dictionary = _data.get("settings", {})
	var list: Array = settings.get("numeric_watchlist", [])
	for i in range(list.size()):
		if str(list[i].get("id", "")) == item_id:
			list.remove_at(i)
			settings["numeric_watchlist"] = list
			_data["settings"] = settings
			_save()
			_write_watchlist_file()
			numeric_list_changed.emit()
			print("[Idle] Removed numeric item: ", item_id)
			return true
	return false


func get_all_watchlist_entries() -> Array:
	var seen := {}
	var out: Array = []
	for t in get_tanks():
		for f in t.get("fish", []):
			var market: String = str(f.get("market", ""))
			var symbol: String = str(f.get("symbol", ""))
			var key := market + ":" + symbol
			if key == ":" or seen.has(key):
				continue
			seen[key] = true
			var nick: String = str(f.get("nickname", ""))
			out.append({"market": market, "symbol": symbol, "name": nick if nick != "" else symbol})
	for item in get_numeric_list():
		var market: String = str(item.get("market", ""))
		var symbol: String = str(item.get("symbol", ""))
		var key := market + ":" + symbol
		if key == ":" or seen.has(key):
			continue
		seen[key] = true
		var nick: String = str(item.get("nickname", ""))
		out.append({"market": market, "symbol": symbol, "name": nick if nick != "" else symbol})
	return out

func get_total_symbol_count() -> int:
	return get_all_watchlist_entries().size()

func is_global_limit_reached() -> bool:
	return get_total_symbol_count() >= MAX_TOTAL_SYMBOLS

func _is_new_global_symbol(market: String, symbol: String) -> bool:
	var key := market + ":" + symbol
	for e in get_all_watchlist_entries():
		if (str(e.get("market", "")) + ":" + str(e.get("symbol", ""))) == key:
			return false
	return true

func _write_watchlist_file() -> void:
	var seen := {}
	var unique_tickers: Array = []
	for t in get_tanks():
		for f in t.get("fish", []):
			var market: String = str(f.get("market", ""))
			var symbol: String = str(f.get("symbol", ""))
			var key := market + ":" + symbol
			if key == ":" or seen.has(key):
				continue
			seen[key] = true
			unique_tickers.append(f)

	for item in get_numeric_list():
		var market: String = str(item.get("market", ""))
		var symbol: String = str(item.get("symbol", ""))
		var key := market + ":" + symbol
		if key == ":" or seen.has(key):
			continue
		seen[key] = true
		unique_tickers.append(item)

	var abs_path := BackendManager.get_data_dir() + "watchlist.json"
	var content := {
		"updated_at": Time.get_datetime_string_from_system(true),
		"fish_list": unique_tickers,
	}
	var tmp_path := abs_path + ".tmp"
	var dir_path := abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[Idle] Failed to write watchlist.json: " + tmp_path)
		return
	f.store_string(JSON.stringify(content, "  "))
	f.close()
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.rename(tmp_path, abs_path)
	print("[Idle] watchlist.json synced (", unique_tickers.size(), " unique tickers; ",
		get_tanks().size(), " tanks + ", get_numeric_list().size(), " numeric)")


func _format_seconds(s: float) -> String:
	var h: int = int(s / 3600)
	var m: int = int((s - h * 3600) / 60)
	var sec: int = int(s) % 60
	return "%dh%dm%ds" % [h, m, sec]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save()
