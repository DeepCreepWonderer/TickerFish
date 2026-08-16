extends Node
## Headless 回归测试:数据层契约 + 对话框交互;跑前备份存档,跑后还原。

const TankNameDialog := preload("res://scripts/tank_name_dialog.gd")
const HeroEditDialog := preload("res://scripts/hero_card_edit_dialog.gd")
const CreateFishDialog := preload("res://scripts/create_fish_dialog.gd")
const DeleteFishDialog := preload("res://scripts/delete_fish_dialog.gd")
const ApiKeyDialog := preload("res://scripts/api_key_settings_dialog.gd")
const AlertSettingsDialog := preload("res://scripts/alert_settings_dialog.gd")
const AppearanceDialog := preload("res://scripts/appearance_settings_dialog.gd")
const ApiKeyGuideDialog := preload("res://scripts/api_key_guide_dialog.gd")
const StripPanel := preload("res://scripts/strip_panel.gd")
const TideDialog := preload("res://scripts/tide_dialog_window.gd")
const FishArtDialog := preload("res://scripts/fish_art_dialog.gd")

const BACKUP_DIR := "user://regression_backup/"

var _pass: int = 0
var _fail: int = 0
var _dup_events: Array = []
var _alerts: Array = []
var _backed_up: Array[String] = []
var _backup_md5: Dictionary = {}
var _backup_runtime: float = -1.0
var _saved_keys: Dictionary = {}

func _ready() -> void:
	await get_tree().process_frame
	_backup_state()
	IdleSystem.duplicate_skipped.connect(func(s): _dup_events.append(s))
	AlertSystem.alert_fired.connect(func(r): _alerts.append(r))

	print("\n=== ENV ===")
	print("data_dir=", BackendManager.get_data_dir())
	print("clock=", MarketClock.debug_et_now_str(), " is_market_open=", MarketClock.is_market_open())

	_test_add_fish_dedupe()
	_test_context_market()
	_test_rename_dialog()
	_test_hero_edit_cap()
	_test_market_tabs()
	_test_apikey_error_label()
	_test_market_holidays()
	_test_live_market_status()
	await _test_menu_ids_unique()
	_test_dialog_size_caps()
	_test_alert_settings_no_silent_write()
	_test_strip_reorder_and_groups()
	_test_apikey_verify_branches()
	_test_appearance_dialog()
	_test_guide_dialog()
	await _test_needs_config_keeps_cache()
	await _test_needs_config_with_other_market_data()
	await _test_cold_start_cache_seed()
	_test_alert_master_switch()
	_test_alert_ladder()
	_test_alert_direction_split()
	_test_alert_small_threshold()
	_test_alert_persistence()
	_test_alert_settings_dialog()
	_test_alert_gate()
	_test_stale_never_baselines()
	_test_alert_threshold_change()
	_test_save_recovery()
	_test_tls_blocked()

	_restore_state()
	print("\n=== RESULT pass=%d fail=%d ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

# ---- state isolation ----

func _state_files() -> Array[String]:
	var d: String = BackendManager.get_data_dir()
	return [
		ProjectSettings.globalize_path("user://save.json"),
		ProjectSettings.globalize_path("user://save.json.bak"),
		ProjectSettings.globalize_path("user://save.json.broken"),
		ProjectSettings.globalize_path("user://bars_cache.json"),
		d + "prices.json",
		d + "watchlist.json",
		d + "price_alerts_%d.csv" % int(MarketClock.et_now().get("year", 1970)),
	]

func _disk_runtime() -> float:
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if not FileAccess.file_exists(p):
		return -1.0
	var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
	return float(d.get("total_runtime", -1.0)) if d is Dictionary else -1.0

func _copy_file(src_path: String, dst_path: String) -> bool:
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return false
	var out := FileAccess.open(dst_path, FileAccess.WRITE)
	if out == null:
		src.close()
		return false
	out.store_buffer(src.get_buffer(src.get_length()))
	src.close()
	out.close()
	return true

func _backup_state() -> void:
	IdleSystem._tick_timer.stop()
	StockFetcher._next_due_ms = Time.get_ticks_msec() + 3600000
	for node in [PriceRecorder, DataReader]:
		for c in node.get_children():
			if c is Timer:
				c.stop()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BACKUP_DIR))
	for path in _state_files():
		if not FileAccess.file_exists(path):
			continue
		if _copy_file(path, ProjectSettings.globalize_path(BACKUP_DIR) + path.get_file()):
			_backed_up.append(path)
			_backup_md5[path] = FileAccess.get_md5(path)
		else:
			push_error("[Regression] backup failed: " + path)
	_saved_keys = BackendManager.get_api_keys().duplicate(true)
	BackendManager.save_api_keys({"finnhub": ""})
	_backup_runtime = _disk_runtime()
	print("[Regression] backed up ", _backed_up.size(), " files; autosave stopped; api key blanked")

func _restore_files() -> void:
	for path in _state_files():
		var src_path: String = ProjectSettings.globalize_path(BACKUP_DIR) + path.get_file()
		if path in _backed_up and FileAccess.file_exists(src_path):
			if not _copy_file(src_path, path):
				push_error("[Regression] restore failed: " + path)
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _restore_state() -> void:
	print("\n=== state restore ===")
	BackendManager.save_api_keys(_saved_keys)
	_restore_files()

	var live: float = _disk_runtime()
	if _backup_runtime >= 0.0 and absf(live - _backup_runtime) > 0.001:
		push_warning("[Regression] another Tickerfish instance is writing save.json")
		print("  WARN  另一个 Tickerfish 实例正在运行并写存档(total_runtime %+.0f 秒)。" % (live - _backup_runtime))
		print("        关掉正在运行的 app 再跑这套测试,否则两个进程会互相覆盖存档。")

	IdleSystem._load_or_create_save()
	IdleSystem._write_watchlist_file()
	DataReader._bars = {}
	DataReader._current_bars = {}
	DataReader._load_bars()
	_restore_files()

	for path in _backed_up:
		_ok("restored " + path.get_file(),
			FileAccess.file_exists(path) and FileAccess.get_md5(path) == _backup_md5[path],
			"expected md5 " + str(_backup_md5[path]))
	_ok("api key put back",
		str(BackendManager.get_api_keys().get("finnhub", "")) == str(_saved_keys.get("finnhub", "")))

# ---- helpers ----

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  FAIL  ", label, "  ", detail)

func _reset_tanks(fish: Array) -> void:
	var tanks: Array = IdleSystem.get_tanks()
	tanks.clear()
	tanks.append({"id": "tank_1", "name": "T1", "icon": "F", "is_preset": false, "fish": fish})
	IdleSystem._data["tanks"] = tanks
	IdleSystem.set_active_tank("tank_1")

func _clear_numeric_list() -> void:
	var settings: Dictionary = IdleSystem._data.get("settings", {})
	settings["numeric_watchlist"] = []
	IdleSystem._data["settings"] = settings

func _write_prices(snap: Dictionary) -> void:
	var path: String = BackendManager.get_data_dir() + "prices.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, "  "))
	f.close()

func _read_prices() -> Dictionary:
	var path: String = BackendManager.get_data_dir() + "prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return parsed if parsed is Dictionary else {}

func _run_one_cycle() -> bool:
	StockFetcher._busy = false
	StockFetcher._klines_next_ms = Time.get_ticks_msec() + 600000
	StockFetcher._run_cycle()
	for i in range(3000):
		await get_tree().process_frame
		if not StockFetcher._busy:
			return true
	return false

# ---- watchlist ----

func _test_add_fish_dedupe() -> void:
	print("\n=== add_fish dedupe ===")
	_reset_tanks([])
	_clear_numeric_list()
	_dup_events.clear()
	var a: Dictionary = IdleSystem.add_fish("AAPL", "stocks", "AAPL")
	var b: Dictionary = IdleSystem.add_fish("AAPL", "stocks", "AAPL")
	_ok("first add succeeds", not a.is_empty())
	_ok("second add rejected", b.is_empty())
	_ok("tank still has 1 fish", IdleSystem.get_fish_list().size() == 1,
		"size=%d" % IdleSystem.get_fish_list().size())
	_ok("duplicate_skipped emitted once", _dup_events.size() == 1, str(_dup_events))

	var c: Dictionary = IdleSystem.add_fish(" msft ", "stocks", "  msft  ")
	_ok("symbol normalized", c.get("symbol", "") == "MSFT", str(c.get("symbol", "")))
	_ok("case-insensitive dedupe", IdleSystem.add_fish("MSFT", "stocks", "MSFT").is_empty())
	_ok("same symbol other market allowed", not IdleSystem.add_fish("BTC", "crypto", "BTC").is_empty())

	_dup_events.clear()
	IdleSystem.add_numeric_item("AAPL", "stocks", "AAPL")
	var n2: Dictionary = IdleSystem.add_numeric_item("AAPL", "stocks", "AAPL")
	_ok("numeric dedupe also signals", n2.is_empty() and _dup_events.size() == 1, str(_dup_events))

func _test_context_market() -> void:
	print("\n=== get_context_market ===")
	IdleSystem.save_display_mode("fish_tank")
	IdleSystem.set_selected_market("stocks")

	_reset_tanks([{"id": "f1", "nickname": "BTC", "market": "crypto", "symbol": "BTC"}])
	_ok("crypto-only tank -> crypto", IdleSystem.get_context_market() == "crypto")

	_reset_tanks([{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"}])
	_ok("stock-only tank -> stocks", IdleSystem.get_context_market() == "stocks")

	_reset_tanks([
		{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"},
		{"id": "f2", "nickname": "BTC", "market": "crypto", "symbol": "BTC"},
	])
	IdleSystem.set_selected_market("crypto")
	_ok("mixed tank -> last selected", IdleSystem.get_context_market() == "crypto")
	IdleSystem.set_selected_market("stocks")
	_ok("mixed tank follows setter", IdleSystem.get_context_market() == "stocks")

	_reset_tanks([])
	_ok("empty tank -> last selected", IdleSystem.get_context_market() == "stocks")
	IdleSystem.set_selected_market("bogus")
	_ok("invalid market normalized", IdleSystem.get_selected_market() == "stocks")

# ---- dialogs ----

func _test_rename_dialog() -> void:
	print("\n=== tank rename blank guard ===")
	var dlg = TankNameDialog.new()
	dlg.setup("rename", "OldName")
	add_child(dlg)
	var submitted: Array = []
	dlg.name_submitted.connect(func(n): submitted.append(n))
	_ok("ok enabled with preset name", not dlg.get_ok_button().disabled)

	dlg._name_edit.text = "   "
	dlg._on_text_changed("   ")
	_ok("ok disabled on blank", dlg.get_ok_button().disabled)
	dlg._on_confirm()
	_ok("blank confirm emits nothing", submitted.is_empty(), str(submitted))
	_ok("dialog not freed on blank confirm", is_instance_valid(dlg))

	dlg._name_edit.text = " New "
	dlg._on_text_changed(" New ")
	_ok("ok re-enabled", not dlg.get_ok_button().disabled)
	dlg._on_confirm()
	_ok("valid confirm emits trimmed name", submitted == ["New"], str(submitted))

	var dlg2 = TankNameDialog.new()
	dlg2.setup("create", "")
	add_child(dlg2)
	_ok("create mode allows blank", not dlg2.get_ok_button().disabled)
	dlg2.queue_free()

func _test_hero_edit_cap() -> void:
	print("\n=== hero card cap ===")
	var settings: Dictionary = IdleSystem._data.get("settings", {})
	var nl: Array = []
	var syms := ["AAA", "BBB", "CCC", "DDD", "EEE", "FFF"]
	for i in range(syms.size()):
		nl.append({"id": "n%d" % i, "symbol": syms[i], "nickname": syms[i], "market": "stocks"})
	settings["numeric_watchlist"] = nl
	IdleSystem._data["settings"] = settings

	var dlg = HeroEditDialog.new()
	dlg.setup(0, "stocks", syms.slice(0, 6), "Six", 60)
	add_child(dlg)
	_ok("6 checked -> save disabled", dlg.get_ok_button().disabled)
	var saved: Array = []
	dlg.saved.connect(func(i, s, t, iv): saved.append(s))
	dlg._on_confirm()
	_ok("confirm blocked while over cap", saved.is_empty(), str(saved))

	dlg._checks[0]["tog"].button_pressed = false
	dlg._on_toggle(false)
	_ok("5 checked -> save enabled", not dlg.get_ok_button().disabled)
	dlg._on_confirm()
	_ok("saves exactly 5, no silent drop", saved.size() == 1 and saved[0].size() == 5, str(saved))
	dlg.queue_free()

func _test_market_tabs() -> void:
	print("\n=== dialog default market tab ===")
	_reset_tanks([{"id": "f1", "nickname": "BTC", "market": "crypto", "symbol": "BTC"}])
	IdleSystem.set_selected_market("stocks")

	var del = AcceptDialog.new()
	del.set_script(DeleteFishDialog)
	del.setup(IdleSystem.get_context_market(),
		[{"id": "f1", "symbol": "BTC", "nickname": "BTC", "market": "crypto"}])
	add_child(del)
	_ok("delete dialog -> crypto tab", del._current_market == "crypto", del._current_market)
	del.queue_free()

	var add_dlg = CreateFishDialog.new()
	add_child(add_dlg)
	_ok("add dialog -> crypto tab", add_dlg._current_market == "crypto", add_dlg._current_market)
	add_dlg._select_market("stocks")
	_ok("switching tab persists", IdleSystem.get_selected_market() == "stocks")
	add_dlg.queue_free()

func _test_apikey_error_label() -> void:
	print("\n=== api key save error ui ===")
	var dlg = ApiKeyDialog.new()
	add_child(dlg)
	_ok("error label exists", dlg._save_error != null)
	_ok("error label hidden by default", dlg._save_error != null and not dlg._save_error.visible)
	_ok("error label width locked", dlg._save_error != null and dlg._save_error.custom_minimum_size.x > 0.0)
	_ok("save_failed string resolves", Lang.t("settings.save_failed") != "settings.save_failed")
	dlg.queue_free()

func _syms_in_order() -> Array:
	var out: Array = []
	for it in IdleSystem.get_numeric_list():
		out.append(str(it.get("symbol", "")))
	return out

func _seed_numeric(syms: Array) -> void:
	var settings: Dictionary = IdleSystem._data.get("settings", {})
	var list: Array = []
	for i in range(syms.size()):
		list.append({"id": "n%d" % i, "symbol": str(syms[i]), "nickname": str(syms[i]),
			"market": "stocks"})
	settings["numeric_watchlist"] = list
	IdleSystem._data["settings"] = settings

func _test_market_holidays() -> void:
	print("\n=== NYSE holiday table ===")
	_ok("New Year's Day 2026 is closed", MarketClock.is_holiday("2026-01-01"))
	_ok("Good Friday 2026 is closed", MarketClock.is_holiday("2026-04-03"))
	_ok("Thanksgiving 2026 is closed", MarketClock.is_holiday("2026-11-26"))
	_ok("Juneteenth 2026 is closed", MarketClock.is_holiday("2026-06-19"))
	_ok("a normal Monday is open", not MarketClock.is_holiday("2026-03-16"))

	_ok("Jul 4 2026 falls Saturday -> observed Fri Jul 3", MarketClock.is_holiday("2026-07-03"))
	_ok("Sat Jul 4 2026 itself is not listed", not MarketClock.is_holiday("2026-07-04"))
	_ok("Dec 25 2027 falls Saturday -> observed Fri Dec 24", MarketClock.is_holiday("2027-12-24"))
	_ok("Jan 1 2028 falls Saturday -> no observed holiday",
		not MarketClock.is_holiday("2028-01-01") and not MarketClock.is_holiday("2027-12-31"))
	_ok("Jan 1 2034 falls Sunday -> observed Mon Jan 2", MarketClock.is_holiday("2034-01-02"))
	_ok("Dec 25 2033 falls Sunday -> observed Mon Dec 26", MarketClock.is_holiday("2033-12-26"))

	_ok("day after Thanksgiving 2026 is a half day", MarketClock.is_half_day("2026-11-27"))
	_ok("Christmas Eve 2026 is a half day", MarketClock.is_half_day("2026-12-24"))
	_ok("Christmas Eve 2027 is a full holiday, not a half day",
		not MarketClock.is_half_day("2027-12-24"))
	_ok("Jul 3 2026 is a holiday, not a half day", not MarketClock.is_half_day("2026-07-03"))
	_ok("Jul 3 2028 is a half day", MarketClock.is_half_day("2028-07-03"))

	_ok("half day closes at 13:00 ET",
		MarketClock.close_minute("2026-11-27") == MarketClock.NYSE_HALF_DAY_CLOSE_MIN)
	_ok("normal day closes at 16:00 ET",
		MarketClock.close_minute("2026-03-16") == MarketClock.NYSE_CLOSE_MIN)
	_ok("table covers through %d" % MarketClock.HOLIDAY_TABLE_LAST_YEAR,
		MarketClock.is_holiday("2035-12-25"))
	_ok("beyond the table nothing is a holiday", not MarketClock.is_holiday("2040-12-25"))

func _test_live_market_status() -> void:
	print("\n=== live market status overrides the table ===")
	MarketClock.clear_live_status()
	_ok("no live status by default", not MarketClock.has_live_status())
	_ok("falls back to the table", MarketClock.is_holiday("2026-12-25"))

	MarketClock.set_live_status(true, "")
	_ok("live status is fresh once pushed", MarketClock.has_live_status())
	_ok("live open -> market open", MarketClock.is_market_open())
	_ok("live open -> stocks awake", MarketClock.is_stock_awake())
	_ok("live says no holiday -> not a holiday", not MarketClock.is_holiday())

	MarketClock.set_live_status(false, "Christmas")
	_ok("live holiday name -> is_holiday true", MarketClock.is_holiday())
	_ok("live closed -> market closed", not MarketClock.is_market_open())
	_ok("live closed on a holiday -> not awake", not MarketClock.is_stock_awake())
	_ok("live holiday name is readable", MarketClock.live_holiday_name() == "Christmas")

	MarketClock.set_live_status(false, "")
	_ok("live closed without holiday -> market closed", not MarketClock.is_market_open())
	_ok("explicit date query still uses the table",
		MarketClock.is_holiday("2026-12-25") and not MarketClock.is_holiday("2026-03-16"))

	MarketClock._live_at_ms = Time.get_ticks_msec() - MarketClock.LIVE_STALE_MS - 1000
	_ok("stale live status is ignored", not MarketClock.has_live_status())
	_ok("stale -> table takes over again", MarketClock.is_holiday("2026-12-25"))
	_ok("stale -> holiday name cleared", MarketClock.live_holiday_name() == "")
	MarketClock.clear_live_status()

func _test_menu_ids_unique() -> void:
	print("\n=== context menu ids are unique ===")
	var tank := Control.new()
	tank.set_script(load("res://scripts/fish_tank_window.gd"))
	tank.size = Vector2(600, 400)
	add_child(tank)
	await get_tree().process_frame

	for mode in ["fish_tank", "numeric", "strip", "hero"]:
		IdleSystem.save_display_mode(mode)
		await get_tree().process_frame
		tank._display_mode = mode
		tank._show_context_menu(Vector2(20, 20))
		await get_tree().process_frame
		var menu: PopupMenu = null
		for c in tank.get_children():
			if c is PopupMenu:
				menu = c
		if menu == null:
			_ok("%s: menu built" % mode, false, "no PopupMenu")
			continue
		var seen := {}
		var dupes: Array = []
		for i in range(menu.item_count):
			if menu.is_item_separator(i):
				continue
			var id: int = menu.get_item_id(i)
			if seen.has(id):
				dupes.append("%s/%s share id %d" % [seen[id], menu.get_item_text(i), id])
			seen[id] = menu.get_item_text(i)
		_ok("%s: no duplicate menu ids" % mode, dupes.is_empty(), str(dupes))
		_ok("%s: quit id 0 is not shared" % mode,
			str(seen.get(0, "")) == Lang.t("menu.quit"), str(seen.get(0, "(absent)")))
		menu.queue_free()
		await get_tree().process_frame

	var usable := DisplayServer.screen_get_usable_rect(0)
	for corner in [Vector2i(usable.position.x + usable.size.x - 4, usable.position.y + usable.size.y - 4),
			Vector2i(usable.position.x - 500, usable.position.y - 500)]:
		var m := PopupMenu.new()
		for i in range(8):
			m.add_item("item %d" % i, i)
		tank.add_child(m)
		tank._popup_menu_clamped(m, corner)
		var ms := Vector2i(m.get_contents_minimum_size())
		_ok("menu never lands past the top-left edge, from %s" % str(corner),
			m.position.x >= usable.position.x and m.position.y >= usable.position.y,
			"pos=%s usable=%s" % [str(m.position), str(usable)])
		if usable.size.x > 0 and usable.size.y > 0:
			_ok("menu never overruns the bottom-right edge, from %s" % str(corner),
				m.position.x + ms.x <= usable.position.x + usable.size.x
				and m.position.y + ms.y <= usable.position.y + usable.size.y,
				"pos=%s size=%s usable=%s" % [str(m.position), str(ms), str(usable)])
		else:
			print("  SKIP  bottom-right clamp needs a real screen (headless reports 0x0)")
		m.queue_free()

	_ok("right button blocks activation", not _guard_check(tank, MOUSE_BUTTON_RIGHT))
	_ok("middle button blocks activation", not _guard_check(tank, MOUSE_BUTTON_MIDDLE))
	_ok("left button allows activation", _guard_check(tank, MOUSE_BUTTON_LEFT))

	tank._on_menu_window_input(_btn_event(MOUSE_BUTTON_RIGHT), null)
	var key_ev := InputEventKey.new()
	key_ev.pressed = true
	key_ev.keycode = KEY_ENTER
	tank._on_menu_window_input(key_ev, null)
	_ok("keyboard activation still works after a right click", tank._menu_allows())
	tank.queue_free()

func _btn_event(btn: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = true
	return ev

func _guard_check(tank, btn: int) -> bool:
	tank._on_menu_window_input(_btn_event(btn), null)
	return tank._menu_allows()

func _test_dialog_size_caps() -> void:
	print("\n=== every secondary window shares one size ===")
	var scripts := [ApiKeyDialog, AlertSettingsDialog, AppearanceDialog, ApiKeyGuideDialog,
		load("res://scripts/about_dialog.gd"), load("res://scripts/alert_history_dialog.gd"),
		load("res://scripts/onboarding_dialog.gd"), load("res://scripts/price_record_settings_dialog.gd"),
		FishArtDialog]
	var sizes: Array = []
	var mins: Array = []
	for sc in scripts:
		var dlg = (sc as GDScript).new()
		add_child(dlg)
		var who: String = dlg.get_script().resource_path.get_file()
		_ok("%s inherits the base helpers" % who,
			dlg.has_method("set_tank_size") and dlg.has_method("popup_centered_on_parent")
			and dlg.has_method("apply_tide_size"))
		dlg.set_tank_size(Vector2i.ZERO)
		dlg._resize_to_fit_screen()
		sizes.append(dlg.size)
		mins.append(dlg.min_size)
		dlg.queue_free()

	var first_size = sizes[0]
	var first_min = mins[0]
	var same_size := true
	var same_min := true
	for i in range(sizes.size()):
		if sizes[i] != first_size:
			same_size = false
		if mins[i] != first_min:
			same_min = false
	_ok("all 9 dialogs resize to the same size", same_size, str(sizes))
	_ok("all 9 dialogs share one min_size", same_min, str(mins))
	_ok("min_size matches the canonical constant",
		first_min == TideDialog.DIALOG_MIN, str(first_min))

	var dlg2 = (AppearanceDialog as GDScript).new()
	add_child(dlg2)
	dlg2.set_tank_size(Vector2i(200, 200))
	dlg2._resize_to_fit_screen()
	_ok("a tiny tank clamps down to min_size, never below",
		dlg2.size.x >= TideDialog.DIALOG_MIN.x and dlg2.size.y >= TideDialog.DIALOG_MIN.y,
		str(dlg2.size))
	dlg2.queue_free()

func _test_alert_settings_no_silent_write() -> void:
	print("\n=== alert settings does not write on open/close ===")
	_reset_tanks([{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"}])
	IdleSystem._data["alerts"] = {}
	IdleSystem.save_alerts_enabled(true)

	var dlg = AlertSettingsDialog.new()
	add_child(dlg)
	dlg._on_close_requested()
	_ok("opening then closing writes no config",
		(IdleSystem._data.get("alerts", {}) as Dictionary).is_empty(),
		str(IdleSystem._data.get("alerts", {})))
	dlg.queue_free()

	var dlg2 = AlertSettingsDialog.new()
	add_child(dlg2)
	dlg2._toggle.button_pressed = true
	dlg2._on_close_requested()
	_ok("an actual change is still written",
		IdleSystem.get_alert_config("stocks:AAPL").get("enabled", false))
	dlg2.queue_free()

func _grouped(pairs: Array) -> Array:
	var list: Array = []
	for i in range(pairs.size()):
		var it := {"id": "n%d" % i, "symbol": str(pairs[i][0]), "nickname": str(pairs[i][0]),
			"market": "stocks"}
		if str(pairs[i][1]) != "":
			it["group"] = str(pairs[i][1])
		list.append(it)
	return list

func _test_strip_drop_target() -> void:
	print("\n--- strip drop target (drag decides the group) ---")
	var panel = StripPanel.new()
	panel._grid_x = 0.0
	panel._grid_y = 0.0
	panel._cell_w = 100.0
	panel._cell_h = 50.0
	panel._label_w = 0.0

	var list := _grouped([["AAA", "Tech"], ["BBB", "Tech"], ["CCC", "Crypto"],
		["DDD", "Crypto"], ["EEE", ""]])

	panel._drag_src = 4
	var d1: Dictionary = panel.drop_target(list, Vector2(50.0, 25.0))
	_ok("dropping on the Tech row adopts Tech", str(d1["group"]) == "Tech", str(d1))
	_ok("slot lands inside Tech", int(d1["slot"]) == 0, str(d1))

	var d2: Dictionary = panel.drop_target(list, Vector2(150.0, 75.0))
	_ok("dropping on the Crypto row adopts Crypto", str(d2["group"]) == "Crypto", str(d2))
	_ok("slot lands after the first Crypto card", int(d2["slot"]) == 3, str(d2))

	panel._drag_src = 0
	var d3: Dictionary = panel.drop_target(list, Vector2(50.0, 125.0))
	_ok("dropping on the ungrouped row clears the group", str(d3["group"]) == "", str(d3))

	panel._drag_src = 2
	var d4: Dictionary = panel.drop_target(list, Vector2(50.0, 9999.0))
	_ok("dropping below everything clamps to the last row",
		str(d4["group"]) == "", str(d4))

	var solo_list := _grouped([["AAA", "Tech"]])
	panel._drag_src = 0
	var d5: Dictionary = panel.drop_target(solo_list, Vector2(50.0, 25.0))
	_ok("dragging the only card keeps its group", str(d5["group"]) == "Tech", str(d5))
	panel._drag_src = -1

	var solo := _grouped([["AAA", "Solo"], ["BBB", "Tech"]])
	_ok("two groups -> two rows before the move", StripPanel.rows_for(solo) == 2)
	solo[0].erase("group")
	solo[0]["group"] = "Tech"
	_ok("last member joins the other group -> one row", StripPanel.rows_for(solo) == 1,
		str(StripPanel.rows_for(solo)))

func _test_strip_reorder_and_groups() -> void:
	print("\n=== strip reorder + groups ===")
	_seed_numeric(["AAA", "BBB", "CCC", "DDD"])

	_ok("reorder moves an item back", IdleSystem.reorder_numeric_item(0, 2)
		and _syms_in_order() == ["BBB", "CCC", "AAA", "DDD"], str(_syms_in_order()))
	_ok("reorder moves an item forward", IdleSystem.reorder_numeric_item(3, 0)
		and _syms_in_order() == ["DDD", "BBB", "CCC", "AAA"], str(_syms_in_order()))
	_ok("same index is a no-op", not IdleSystem.reorder_numeric_item(1, 1))
	_ok("out of range is rejected", not IdleSystem.reorder_numeric_item(9, 0))
	_ok("target index is clamped", IdleSystem.reorder_numeric_item(0, 99)
		and _syms_in_order()[3] == "DDD", str(_syms_in_order()))

	_seed_numeric(["AAA", "BBB", "CCC"])
	_ok("group starts empty", StripPanel.group_of(IdleSystem.get_numeric_list()[0]) == "")
	_ok("set group writes through", IdleSystem.set_numeric_item_group("n0", " Tech ")
		and StripPanel.group_of(IdleSystem.get_numeric_item("n0")) == "Tech",
		StripPanel.group_of(IdleSystem.get_numeric_item("n0")))
	_ok("setting the same group again is a no-op",
		not IdleSystem.set_numeric_item_group("n0", "Tech"))
	_ok("empty group clears the field", IdleSystem.set_numeric_item_group("n0", "")
		and not IdleSystem.get_numeric_item("n0").has("group"))
	_ok("unknown id is rejected", not IdleSystem.set_numeric_item_group("nope", "X"))

	_seed_numeric(["AAA", "BBB", "CCC", "DDD"])
	_ok("no groups -> one row", StripPanel.rows_for(IdleSystem.get_numeric_list()) == 1,
		str(StripPanel.rows_for(IdleSystem.get_numeric_list())))
	IdleSystem.set_numeric_item_group("n2", "Crypto")
	IdleSystem.set_numeric_item_group("n3", "Crypto")
	_ok("two groups -> two rows", StripPanel.rows_for(IdleSystem.get_numeric_list()) == 2,
		str(StripPanel.rows_for(IdleSystem.get_numeric_list())))
	IdleSystem.set_numeric_item_group("n1", "Crypto")
	IdleSystem.set_numeric_item_group("n2", "")
	_ok("non-adjacent same name -> separate sections",
		StripPanel.rows_for(IdleSystem.get_numeric_list()) == 4,
		str(StripPanel.rows_for(IdleSystem.get_numeric_list())))

	IdleSystem.set_numeric_item_group("n0", "Tech")
	IdleSystem.set_numeric_item_group("n1", "Tech")
	var dlg = TankNameDialog.new()
	dlg.setup("group", "Tech")
	add_child(dlg)
	var got: Array = []
	dlg.name_submitted.connect(func(n): got.append(n))
	dlg._on_clear_group()
	_ok("dialog clear button emits an empty name", got == [""], str(got))
	_ok("only that one item leaves the group",
		IdleSystem.get_numeric_item("n1").get("group", "") == "Tech")
	dlg.queue_free()

	_test_strip_drop_target()

	var many: Array = []
	for i in range(20):
		many.append("S%d" % i)
	_seed_numeric(many)
	_ok("20 ungrouped items wrap into 3 rows",
		StripPanel.rows_for(IdleSystem.get_numeric_list()) == 3,
		str(StripPanel.rows_for(IdleSystem.get_numeric_list())))
	_ok("empty list still reports one row", StripPanel.rows_for([]) == 1)

func _test_apikey_verify_branches() -> void:
	print("\n=== api key verify branches ===")
	var ok_body := JSON.stringify({"c": 212.5, "pc": 210.0}).to_utf8_buffer()
	var empty := PackedStringArray()

	var dlg = ApiKeyDialog.new()
	add_child(dlg)
	dlg._on_verify_done(HTTPRequest.RESULT_SUCCESS, 401, empty, ok_body)
	_ok("401 -> rejected message", dlg._save_error.visible
		and dlg._save_error.text == Lang.t("settings.verify_rejected"), dlg._save_error.text)

	dlg._on_verify_done(HTTPRequest.RESULT_SUCCESS, 429, empty, ok_body)
	_ok("429 -> rate limited message",
		dlg._save_error.text == Lang.t("settings.verify_rate_limited"), dlg._save_error.text)

	dlg._on_verify_done(HTTPRequest.RESULT_CANT_CONNECT, 0, empty, PackedByteArray())
	_ok("no connection -> offline message",
		dlg._save_error.text == Lang.t("settings.verify_offline"), dlg._save_error.text)

	dlg._on_verify_done(HTTPRequest.RESULT_SUCCESS, 200,
		empty, JSON.stringify({"c": 0}).to_utf8_buffer())
	_ok("200 with zero price -> rejected (bad key returns empty quote)",
		dlg._save_error.text == Lang.t("settings.verify_rejected"), dlg._save_error.text)

	var confirmed_count: Array = []
	dlg.confirmed.connect(func(): confirmed_count.append(1))
	dlg._verifying = true
	dlg._on_verify_done(HTTPRequest.RESULT_SUCCESS, 200, empty, ok_body)
	_ok("200 with a real price -> save completes", confirmed_count.size() == 1, str(confirmed_count))
	_ok("success clears the error line", not dlg._save_error.visible)
	_ok("verify flag released", not dlg._verifying)
	dlg.queue_free()

func _test_appearance_dialog() -> void:
	print("\n=== appearance & language dialog ===")
	IdleSystem.save_language("en")
	IdleSystem.save_color_tone("deep_water")

	var dlg = AppearanceDialog.new()
	add_child(dlg)
	_ok("language picker preselects current", dlg._lang_pick.selected == 0, str(dlg._lang_pick.selected))
	_ok("tone picker preselects current", dlg._tone_pick.selected == 0, str(dlg._tone_pick.selected))
	_ok("language picker has both languages", dlg._lang_pick.item_count == 2)
	_ok("tone picker has three tones", dlg._tone_pick.item_count == 3)

	dlg._on_lang_selected(1)
	_ok("picking a language writes through", IdleSystem.get_language() == "zh", IdleSystem.get_language())
	dlg._on_tone_selected(2)
	_ok("picking a tone writes through", IdleSystem.get_color_tone() == "indigo", IdleSystem.get_color_tone())
	_ok("labels follow the language switch",
		dlg._lang_label.text == Lang.t("appearance.language"), dlg._lang_label.text)

	dlg._on_lang_selected(0)
	dlg._on_tone_selected(0)
	dlg.queue_free()

func _test_guide_dialog() -> void:
	print("\n=== api key guide ===")
	var dlg = ApiKeyGuideDialog.new()
	add_child(dlg)
	_ok("guide exposes request_settings", dlg.has_signal("request_settings"))
	var asked: Array = []
	dlg.request_settings.connect(func(): asked.append(1))
	dlg._on_have_key_pressed()
	_ok("have-key button asks to open settings", asked.size() == 1, str(asked))

	for i in range(1, 6):
		var k: String = "guide.step%d" % i
		_ok("step %d text exists" % i, Lang.t(k) != k, Lang.t(k))
	_ok("crypto note exists", Lang.t("guide.crypto_note") != "guide.crypto_note")
	for k in ["settings.verifying", "settings.verify_rejected", "settings.verify_offline",
			"settings.verify_rate_limited", "menu.appearance", "appearance.title", "dialog.close"]:
		_ok("string %s resolves" % k, Lang.t(k) != k)
	dlg.queue_free()

# ---- data layer ----

func _test_needs_config_keeps_cache() -> void:
	print("\n=== no key: stock cache kept ===")
	_reset_tanks([
		{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"},
		{"id": "f2", "nickname": "NVDA", "market": "stocks", "symbol": "NVDA"},
	])
	StockFetcher._prev_tickers = {
		"stocks:AAPL": {"symbol": "AAPL", "price": 212.5, "change_pct": 1.2, "market_open": true},
		"stocks:NVDA": {"symbol": "NVDA", "price": 98.0, "change_pct": -0.4, "market_open": true},
	}
	if not await _run_one_cycle():
		_ok("cycle finished", false, "timed out")
		return

	var snap: Dictionary = _read_prices()
	var tk: Dictionary = snap.get("tickers", {})
	_ok("prices.json written", not snap.is_empty())
	_ok("status=needs_config", str(snap.get("status", "")) == "needs_config", str(snap.get("status", "")))
	_ok("stock cache preserved", tk.has("stocks:AAPL") and tk.has("stocks:NVDA"), str(tk.keys()))
	_ok("cached price intact", tk.has("stocks:AAPL") and abs(float(tk["stocks:AAPL"].get("price", 0.0)) - 212.5) < 0.001)
	_ok("providers_not_ready.stocks set", snap.get("providers_not_ready", {}).has("stocks"))
	_ok("_prev_tickers not wiped", StockFetcher._prev_tickers.has("stocks:AAPL"))
	_ok("cached entries are flagged as not live",
		tk.has("stocks:AAPL") and tk["stocks:AAPL"].get("market_open", true) == false,
		str(tk.get("stocks:AAPL", {})))

	DataReader._read_file()
	_ok("DataReader.needs_config()", DataReader.needs_config())
	_ok("DataReader serves cached price",
		abs(float(DataReader.get_ticker("stocks:AAPL").get("price", 0.0)) - 212.5) < 0.001)

func _test_needs_config_with_other_market_data() -> void:
	print("\n=== no key + crypto data present (regression: Bug#1) ===")
	_reset_tanks([
		{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"},
		{"id": "f2", "nickname": "BTC", "market": "crypto", "symbol": "BTC"},
	])
	StockFetcher._prev_tickers = {
		"stocks:AAPL": {"symbol": "AAPL", "price": 212.5, "change_pct": 1.2, "market_open": true},
		"crypto:BTC": {"symbol": "BTC", "price": 61000.0, "change_pct": 2.1, "market_open": true},
	}
	if not await _run_one_cycle():
		_ok("cycle finished", false, "timed out")
		return

	var snap: Dictionary = _read_prices()
	var tk: Dictionary = snap.get("tickers", {})
	print("  info  status=", snap.get("status", ""), " tickers=", tk.keys())
	_ok("crypto entry present", tk.has("crypto:BTC"), str(tk.keys()))
	_ok("stock cache survives alongside crypto", tk.has("stocks:AAPL"), str(tk.keys()))
	_ok("cached stock price intact",
		tk.has("stocks:AAPL") and abs(float(tk["stocks:AAPL"].get("price", 0.0)) - 212.5) < 0.001)
	_ok("status=needs_config despite crypto data",
		str(snap.get("status", "")) == "needs_config", str(snap.get("status", "")))
	_ok("_prev_tickers keeps stock", StockFetcher._prev_tickers.has("stocks:AAPL"))

func _test_cold_start_cache_seed() -> void:
	print("\n=== cold start seeds cache from prices.json ===")
	_write_prices({
		"updated_at": "2026-08-04T12:00:00Z",
		"status": "ok",
		"error": "",
		"tickers": {
			"stocks:AAPL": {"symbol": "AAPL", "price": 199.9, "change_pct": 0.7, "market_open": false},
		},
	})
	var seeded: Dictionary = StockFetcher._load_cached_tickers()
	_ok("seed reads tickers off disk", seeded.has("stocks:AAPL"), str(seeded.keys()))
	_ok("seeded price matches disk",
		seeded.has("stocks:AAPL") and abs(float(seeded["stocks:AAPL"].get("price", 0.0)) - 199.9) < 0.001)

	_reset_tanks([{"id": "f1", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"}])
	StockFetcher._prev_tickers = seeded
	if not await _run_one_cycle():
		_ok("cycle finished", false, "timed out")
		return
	var tk: Dictionary = _read_prices().get("tickers", {})
	_ok("cold start does not clear the screen", tk.has("stocks:AAPL"), str(tk.keys()))
	_ok("cold start keeps last known price",
		tk.has("stocks:AAPL") and abs(float(tk["stocks:AAPL"].get("price", 0.0)) - 199.9) < 0.001)

	_write_prices({"updated_at": "x", "status": "ok", "tickers": "not a dict"})
	_ok("malformed tickers ignored", StockFetcher._load_cached_tickers().is_empty())

# ---- alerts ----

var _seq: int = 0

func _feed(changes: Dictionary, market_open: Dictionary = {}) -> void:
	_seq += 1
	var tickers: Dictionary = {}
	for key in changes.keys():
		var sym: String = str(key).split(":")[1]
		tickers[key] = {
			"symbol": sym,
			"price": 100.0 + float(changes[key]),
			"change_pct": float(changes[key]),
			"market_open": bool(market_open.get(key, true)),
		}
	_write_prices({
		"updated_at": "2026-01-01T00:%02d:00Z" % _seq,
		"status": "ok", "error": "", "tickers": tickers,
	})
	DataReader._read_file()
	AlertSystem._on_prices_updated()

func _arm(key: String, threshold: float) -> void:
	_reset_tanks([{"id": "f1", "nickname": key.split(":")[1],
		"market": key.split(":")[0], "symbol": key.split(":")[1]}])
	IdleSystem.set_alert_config(key, threshold, true)
	IdleSystem.save_alerts_enabled(true)
	AlertSystem._steps.clear()
	AlertSystem._steps_date = ""
	IdleSystem.clear_alert_steps()
	_alerts.clear()

func _test_alert_master_switch() -> void:
	print("\n=== alerts: master switch ===")
	_arm("crypto:BTC", 5.0)

	IdleSystem.save_alerts_enabled(false)
	_alerts.clear()
	_feed({"crypto:BTC": 1.0})
	_feed({"crypto:BTC": 20.0})
	_ok("nothing fires while master off", _alerts.is_empty(), str(_fired()))
	_ok("no ladder state written while off", IdleSystem.get_alert_steps(AlertSystem._today()).is_empty())

	IdleSystem.save_alerts_enabled(true)
	_ok("turning on clears ladder state", AlertSystem._steps.is_empty())
	_feed({"crypto:BTC": 20.0})
	_ok("first poll after turning on is a silent baseline", _alerts.is_empty(), str(_fired()))
	_feed({"crypto:BTC": 26.0})
	_ok("next higher step fires", _fired().has("BTC"), str(_fired()))

	IdleSystem.save_alerts_enabled(false)
	IdleSystem.save_alerts_enabled(true)
	IdleSystem.save_alerts_enabled(false)
	IdleSystem.save_alerts_enabled(true)
	_ok("toggling repeatedly leaves clean state", AlertSystem._steps.is_empty())

func _test_alert_ladder() -> void:
	print("\n=== alerts: ladder, high-water mark only ===")
	_arm("crypto:BTC", 5.0)

	_feed({"crypto:BTC": 1.0})
	_ok("first sight silent", _alerts.size() == 0, str(_alerts.size()))
	_feed({"crypto:BTC": 5.0})
	_ok("step 1 fires at exactly 5%", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 6.2})
	_ok("same step does not refire", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 2.0})
	_ok("pullback fires nothing", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 6.0})
	_ok("re-cross of a passed step stays silent", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 10.0})
	_ok("step 2 fires at 10%", _alerts.size() == 2, str(_alerts.size()))
	_ok("step 2 record carries the real change", abs(float(_alerts[1].get("change_pct", 0.0)) - 10.0) < 0.001)
	_feed({"crypto:BTC": 14.9})
	_ok("still step 2, silent", _alerts.size() == 2, str(_alerts.size()))
	_feed({"crypto:BTC": 15.0})
	_ok("step 3 fires at 15%", _alerts.size() == 3, str(_alerts.size()))

func _test_alert_direction_split() -> void:
	print("\n=== alerts: up and down laddered separately ===")
	_arm("crypto:BTC", 5.0)

	_feed({"crypto:BTC": 0.0})
	_feed({"crypto:BTC": 6.0})
	_ok("up step 1 fires", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": -6.0})
	_ok("reversal to -6% fires on the down ladder", _alerts.size() == 2, str(_alerts.size()))
	_ok("down record is negative", float(_alerts[1].get("change_pct", 0.0)) < 0.0)
	_feed({"crypto:BTC": 7.0})
	_ok("returning to a passed up step stays silent", _alerts.size() == 2, str(_alerts.size()))
	_feed({"crypto:BTC": -11.0})
	_ok("down step 2 fires", _alerts.size() == 3, str(_alerts.size()))

func _test_alert_small_threshold() -> void:
	print("\n=== alerts: 0.5% threshold no longer deadlocks ===")
	_arm("crypto:BTC", 0.5)

	_feed({"crypto:BTC": 0.0})
	_feed({"crypto:BTC": 0.5})
	_ok("0.5% step 1 fires", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 0.6})
	_ok("same step silent", _alerts.size() == 1, str(_alerts.size()))
	_feed({"crypto:BTC": 1.0})
	_ok("0.5% step 2 fires (old code deadlocked here)", _alerts.size() == 2, str(_alerts.size()))
	_feed({"crypto:BTC": 1.5})
	_ok("0.5% step 3 fires", _alerts.size() == 3, str(_alerts.size()))

func _test_alert_persistence() -> void:
	print("\n=== alerts: ladder persisted per trading day ===")
	_arm("crypto:BTC", 5.0)
	_feed({"crypto:BTC": 0.0})
	_feed({"crypto:BTC": 12.0})

	var today: String = AlertSystem._today()
	var saved: Dictionary = IdleSystem.get_alert_steps(today)
	_ok("steps saved under today", saved.has("crypto:BTC"), str(saved))
	_ok("saved up step is 2", int(saved.get("crypto:BTC", {}).get("up", -1)) == 2, str(saved))
	_ok("another date reads empty (cross-day reset)",
		IdleSystem.get_alert_steps("1999-01-01").is_empty())

	AlertSystem._steps.clear()
	AlertSystem._steps_date = ""
	_alerts.clear()
	_feed({"crypto:BTC": 12.0})
	_ok("restart reloads steps, no duplicate alert", _alerts.is_empty(), str(_fired()))
	_feed({"crypto:BTC": 16.0})
	_ok("restart still fires on a genuinely new step", _alerts.size() == 1, str(_alerts.size()))

func _test_alert_settings_dialog() -> void:
	print("\n=== alerts: settings dialog master switch ===")
	_arm("crypto:BTC", 5.0)
	IdleSystem.save_alerts_enabled(true)

	var dlg = AlertSettingsDialog.new()
	add_child(dlg)
	_ok("master toggle reflects saved state", dlg._master_toggle.button_pressed)
	_ok("config area visible when on", dlg._scroll_main.visible)
	_ok("off hint hidden when on", not dlg._off_hint.visible)

	dlg._master_toggle.button_pressed = false
	dlg._on_master_toggled(false)
	_ok("switch writes through to IdleSystem", not IdleSystem.get_alerts_enabled())
	_ok("config area hidden when off", not dlg._scroll_main.visible)
	_ok("off hint shown when off", dlg._off_hint.visible)
	_ok("none-enabled hint hidden when off", not dlg._none_enabled_hint.visible)

	dlg._master_toggle.button_pressed = true
	dlg._on_master_toggled(true)
	_ok("config area back when on", dlg._scroll_main.visible)
	dlg.queue_free()

func _test_alert_gate() -> void:
	print("\n=== alerts: per-ticker gate, not NYSE clock ===")
	_reset_tanks([
		{"id": "f1", "nickname": "BTC", "market": "crypto", "symbol": "BTC"},
		{"id": "f2", "nickname": "AAPL", "market": "stocks", "symbol": "AAPL"},
	])
	IdleSystem.set_alert_config("crypto:BTC", 3.0, true)
	IdleSystem.set_alert_config("stocks:AAPL", 3.0, true)
	IdleSystem.save_alerts_enabled(true)
	AlertSystem._steps.clear()
	AlertSystem._steps_date = ""
	IdleSystem.clear_alert_steps()
	_alerts.clear()

	_feed({"crypto:BTC": 0.5, "stocks:AAPL": 0.5}, {"stocks:AAPL": false})
	_ok("baseline pass fires nothing", _alerts.is_empty(), str(_alerts.size()))

	_feed({"crypto:BTC": 7.5, "stocks:AAPL": 7.5}, {"stocks:AAPL": false})
	_ok("crypto alert fires regardless of NYSE clock", _fired().has("BTC"), str(_fired()))
	_ok("stale stock (market_open=false) gated", not _fired().has("AAPL"), str(_fired()))

	_feed({"crypto:BTC": 7.5, "stocks:AAPL": 0.5})
	_ok("fresh stock builds baseline silently", not _fired().has("AAPL"), str(_fired()))

	_feed({"crypto:BTC": 7.5, "stocks:AAPL": 7.5})
	_ok("stock alert fires after baseline", _fired().has("AAPL"), str(_fired()))

func _test_stale_never_baselines() -> void:
	print("\n=== stale quotes do not poison the ladder baseline ===")
	_arm("crypto:BTC", 5.0)

	_feed({"crypto:BTC": 20.0}, {"crypto:BTC": false})
	_ok("a stale quote fires nothing", _alerts.is_empty(), str(_fired()))
	_ok("a stale quote records no baseline",
		not AlertSystem._steps.has("crypto:BTC"), str(AlertSystem._steps))

	_feed({"crypto:BTC": 1.0})
	_ok("the first live quote becomes the baseline",
		int(AlertSystem._steps.get("crypto:BTC", {}).get("up", -1)) == 0,
		str(AlertSystem._steps))
	_ok("baseline pass is still silent", _alerts.is_empty(), str(_fired()))

	_feed({"crypto:BTC": 6.0})
	_ok("today's real crossing fires", _alerts.size() == 1, str(_alerts.size()))

func _test_alert_threshold_change() -> void:
	print("\n=== alerts: changing the threshold rebuilds that ticker's ladder ===")
	_arm("crypto:BTC", 3.0)

	_feed({"crypto:BTC": 0.0})
	_feed({"crypto:BTC": 7.0})
	_ok("3% ladder fires at +7%", _alerts.size() == 1, str(_alerts.size()))
	_ok("ladder sits on step 2", int(AlertSystem._steps.get("crypto:BTC", {}).get("up", -1)) == 2,
		str(AlertSystem._steps))

	IdleSystem.set_alert_config("crypto:BTC", 8.0, true)
	_ok("raising the threshold drops the in-memory ladder",
		not AlertSystem._steps.has("crypto:BTC"), str(AlertSystem._steps))
	_ok("raising the threshold drops the saved ladder",
		not IdleSystem.get_alert_steps(AlertSystem._today()).has("crypto:BTC"),
		str(IdleSystem.get_alert_steps(AlertSystem._today())))

	_alerts.clear()
	_feed({"crypto:BTC": 9.0})
	_ok("first pass on the new threshold is a silent baseline", _alerts.is_empty(), str(_fired()))
	_feed({"crypto:BTC": 17.0})
	_ok("next 8% step fires (old code stayed muted all day)", _alerts.size() == 1, str(_alerts.size()))

	IdleSystem.set_alert_config("crypto:BTC", 8.0, false)
	_ok("re-saving the same threshold keeps the ladder",
		AlertSystem._steps.has("crypto:BTC"), str(AlertSystem._steps))

func _test_save_recovery() -> void:
	print("\n=== save.json: atomic write, backup, quarantine ===")
	print("  NOTE  下面的 JSON parse 报错与 save 警告是本节故意写坏存档触发的,属预期输出。")
	var save_path: String = ProjectSettings.globalize_path("user://save.json")
	var bak_path: String = ProjectSettings.globalize_path("user://save.json.bak")
	var broken_path: String = ProjectSettings.globalize_path("user://save.json.broken")
	var tmp_path: String = save_path + ".tmp"

	IdleSystem._data["_regression_marker"] = "keep-me"
	IdleSystem._save()
	IdleSystem._save()
	_ok("no .tmp left behind", not FileAccess.file_exists(tmp_path))
	_ok("previous save kept as save.json.bak", FileAccess.file_exists(bak_path))

	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string("{ truncated")
	f.close()
	IdleSystem._load_or_create_save()
	_ok("corrupt save.json recovers from the backup",
		str(IdleSystem._data.get("_regression_marker", "")) == "keep-me")
	_ok("recovered save keeps its tanks", not IdleSystem.get_tanks().is_empty())

	IdleSystem._save()
	for p in [save_path, bak_path]:
		var g := FileAccess.open(p, FileAccess.WRITE)
		g.store_string("{ truncated")
		g.close()
	IdleSystem._load_or_create_save()
	_ok("both copies unreadable falls back to defaults",
		not IdleSystem._data.has("_regression_marker"))
	_ok("unreadable save quarantined as save.json.broken", FileAccess.file_exists(broken_path))

func _test_tls_blocked() -> void:
	print("\n=== TLS 握手失败:不退回,直接报白名单 ===")
	_ok("string status.error.tls_blocked resolves", Lang.t("status.error.tls_blocked") != "status.error.tls_blocked")

	StockFetcher._last_tls_fail = true
	_ok("handshake failure maps to tls_blocked",
		StockFetcher._transport_error() == "tls_blocked", StockFetcher._transport_error())
	StockFetcher._last_tls_fail = false
	_ok("other transport failure stays no_connection",
		StockFetcher._transport_error() == "no_connection", StockFetcher._transport_error())

	_ok("handshake result is recognised as a TLS failure",
		StockFetcher._is_tls_fail([HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, [], PackedByteArray()]))
	_ok("a plain connection failure is not",
		not StockFetcher._is_tls_fail([HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray()]))
	_ok("an empty result does not", not StockFetcher._is_tls_fail([]))
	_ok("no unverified TLS fallback exists",
		not StockFetcher.has_method("_reset_tls_mode") and not ("_tls_fallback_used" in StockFetcher))

func _fired() -> Array:
	var out: Array = []
	for r in _alerts:
		out.append(str(r.get("symbol", "")))
	return out
